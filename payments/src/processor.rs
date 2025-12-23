//! Payment processor core logic
//!
//! Handles:
//! - Syncing shares from pool APIs to local database
//! - Calculating rewards based on shares
//! - Processing payments to miners
//! - Confirming payments

use crate::config::{AleoConfig, CoinConfig, Config};
use crate::db::{Coin, Database, PaymentStatus};
use crate::pools::{PoolApi, PoolResult};
use crate::wallets::{TxStatus, Wallet, WalletResult};
use rust_decimal::Decimal;
use std::collections::HashMap;
use std::sync::Arc;
use tokio::sync::RwLock;
use tracing::{error, info, warn};

/// Payment processor for a specific coin
pub struct CoinProcessor<P: PoolApi, W: Wallet> {
    coin: Coin,
    pool_api: Arc<P>,
    wallet: Arc<W>,
    db: Database,
    min_payout: Decimal,
    /// Last processed block height
    last_block_height: Arc<RwLock<i64>>,
    /// Last share sync timestamp
    last_share_sync: Arc<RwLock<i64>>,
}

impl<P: PoolApi, W: Wallet> CoinProcessor<P, W> {
    pub fn new(
        coin: Coin,
        pool_api: P,
        wallet: W,
        db: Database,
        min_payout: Decimal,
    ) -> Self {
        Self {
            coin,
            pool_api: Arc::new(pool_api),
            wallet: Arc::new(wallet),
            db,
            min_payout,
            last_block_height: Arc::new(RwLock::new(0)),
            last_share_sync: Arc::new(RwLock::new(0)),
        }
    }

    /// Sync shares from pool API to local database
    pub async fn sync_shares(&self) -> anyhow::Result<u64> {
        let since = *self.last_share_sync.read().await;

        let shares = self.pool_api.get_shares_since(since).await?;

        let mut count = 0;
        let mut latest_timestamp = since;

        for share in shares {
            // Record share in database
            self.db
                .record_share(
                    self.coin,
                    &share.wallet_address,
                    &share.worker_name,
                    share.difficulty,
                    share.block_height,
                    share.is_block,
                )
                .await?;

            count += 1;

            if share.timestamp > latest_timestamp {
                latest_timestamp = share.timestamp;
            }
        }

        // Update last sync timestamp
        *self.last_share_sync.write().await = latest_timestamp;

        if count > 0 {
            info!(
                coin = %self.coin,
                count = count,
                "Synced shares from pool API"
            );
        }

        Ok(count)
    }

    /// Check for new blocks and distribute rewards
    pub async fn process_blocks(&self) -> anyhow::Result<u64> {
        let last_height = *self.last_block_height.read().await;

        // Get new blocks from pool API
        let blocks = self.pool_api.get_blocks_since_height(last_height).await?;

        if blocks.is_empty() {
            return Ok(0);
        }

        let mut processed = 0;
        let mut highest_height = last_height;

        for block in blocks {
            // Record block in database
            self.db
                .record_block(
                    self.coin,
                    block.height,
                    &block.hash,
                    block.reward,
                    &block.finder_wallet,
                    &block.finder_worker,
                )
                .await?;

            info!(
                coin = %self.coin,
                height = block.height,
                hash = %block.hash,
                reward = %block.reward,
                finder = %block.finder_wallet,
                "New block found"
            );

            processed += 1;

            if block.height > highest_height {
                highest_height = block.height;
            }
        }

        // Update last processed height
        *self.last_block_height.write().await = highest_height;

        Ok(processed)
    }

    /// Distribute rewards for undistributed blocks
    pub async fn distribute_rewards(&self) -> anyhow::Result<()> {
        // Get undistributed blocks
        let blocks = self.db.get_undistributed_blocks(self.coin).await?;

        for block in blocks {
            // Calculate time window for PPLNS (e.g., 1 hour before block)
            let window_start = chrono::DateTime::from_timestamp(block.timestamp.timestamp() - 3600, 0)
                .unwrap_or(block.timestamp);
            let window_end = block.timestamp;

            // Get all miners who submitted shares in the window
            let miners = self
                .db
                .get_miners_in_range(self.coin, window_start, window_end)
                .await?;

            // Calculate total shares in window
            let total_shares = self
                .db
                .get_total_shares_in_range(self.coin, window_start, window_end)
                .await?;

            if total_shares == 0 {
                // No shares - give full reward to finder
                self.db
                    .add_pending_balance(self.coin, &block.finder_wallet, block.reward)
                    .await?;

                info!(
                    coin = %self.coin,
                    block_height = block.block_height,
                    recipient = %block.finder_wallet,
                    amount = %block.reward,
                    "Full block reward assigned to finder (no shares in window)"
                );
            } else {
                // Calculate proportional rewards
                let mut distributed = Decimal::from(0);

                for miner_wallet in &miners {
                    let miner_shares = self
                        .db
                        .get_share_count_in_range(self.coin, miner_wallet, window_start, window_end)
                        .await?;

                    if miner_shares > 0 {
                        // Calculate proportional reward
                        let share_ratio = Decimal::from(miner_shares) / Decimal::from(total_shares);
                        let reward = block.reward * share_ratio;

                        self.db
                            .add_pending_balance(self.coin, miner_wallet, reward)
                            .await?;

                        distributed += reward;

                        info!(
                            coin = %self.coin,
                            block_height = block.block_height,
                            miner = %miner_wallet,
                            shares = miner_shares,
                            share_ratio = %share_ratio,
                            reward = %reward,
                            "Reward distributed to miner"
                        );
                    }
                }

                // Handle any rounding remainder - give to block finder
                let remainder = block.reward - distributed;
                if remainder > Decimal::from(0) {
                    self.db
                        .add_pending_balance(self.coin, &block.finder_wallet, remainder)
                        .await?;
                }
            }

            // Mark block as distributed
            self.db.mark_block_distributed(block.id).await?;
        }

        Ok(())
    }

    /// Process payments for balances above threshold
    pub async fn process_payments(&self) -> anyhow::Result<u64> {
        // Get balances above minimum payout
        let payable = self
            .db
            .get_payable_balances(self.coin, self.min_payout)
            .await?;

        if payable.is_empty() {
            return Ok(0);
        }

        // Check pool wallet balance
        let wallet_balance = self.wallet.get_balance().await?;
        let total_payout: Decimal = payable.iter().map(|b| b.pending_balance).sum();

        if wallet_balance < total_payout {
            warn!(
                coin = %self.coin,
                wallet_balance = %wallet_balance,
                total_payout = %total_payout,
                "Insufficient wallet balance for all payments"
            );

            // Process what we can - sort by balance (highest first)
            let mut sorted_payable = payable.clone();
            sorted_payable.sort_by(|a, b| b.pending_balance.cmp(&a.pending_balance));

            let mut remaining_balance = wallet_balance;
            let mut processed = 0;

            for balance in sorted_payable {
                if remaining_balance >= balance.pending_balance {
                    if self.send_payment(&balance.wallet_address, balance.pending_balance).await.is_ok() {
                        remaining_balance -= balance.pending_balance;
                        processed += 1;
                    }
                }
            }

            return Ok(processed);
        }

        // Process all payments
        let mut processed = 0;

        // Try batch payment if wallet supports it
        let payments: Vec<(String, Decimal)> = payable
            .iter()
            .map(|b| (b.wallet_address.clone(), b.pending_balance))
            .collect();

        match self.wallet.send_batch_payment(&payments).await {
            Ok(results) => {
                for (address, tx_hash) in results {
                    // Create payment record
                    let amount = payable
                        .iter()
                        .find(|b| b.wallet_address == address)
                        .map(|b| b.pending_balance)
                        .unwrap_or_default();

                    let payment_id = self
                        .db
                        .create_payment(self.coin, &address, amount)
                        .await?;

                    self.db
                        .update_payment_status(
                            &payment_id,
                            PaymentStatus::Processing,
                            Some(&tx_hash),
                            None,
                        )
                        .await?;

                    info!(
                        coin = %self.coin,
                        address = %address,
                        amount = %amount,
                        tx_hash = %tx_hash,
                        "Payment sent"
                    );

                    processed += 1;
                }
            }
            Err(e) => {
                warn!(
                    coin = %self.coin,
                    error = %e,
                    "Batch payment failed, falling back to individual payments"
                );

                // Fall back to individual payments
                for balance in &payable {
                    if self
                        .send_payment(&balance.wallet_address, balance.pending_balance)
                        .await
                        .is_ok()
                    {
                        processed += 1;
                    }
                }
            }
        }

        Ok(processed)
    }

    /// Send a single payment
    async fn send_payment(&self, address: &str, amount: Decimal) -> anyhow::Result<()> {
        // Create payment record
        let payment_id = self
            .db
            .create_payment(self.coin, address, amount)
            .await?;

        // Send payment
        match self.wallet.send_payment(address, amount).await {
            Ok(tx_hash) => {
                self.db
                    .update_payment_status(
                        &payment_id,
                        PaymentStatus::Processing,
                        Some(&tx_hash),
                        None,
                    )
                    .await?;

                info!(
                    coin = %self.coin,
                    address = %address,
                    amount = %amount,
                    tx_hash = %tx_hash,
                    "Payment sent"
                );

                Ok(())
            }
            Err(e) => {
                self.db
                    .update_payment_status(
                        &payment_id,
                        PaymentStatus::Failed,
                        None,
                        Some(&e.to_string()),
                    )
                    .await?;

                error!(
                    coin = %self.coin,
                    address = %address,
                    amount = %amount,
                    error = %e,
                    "Payment failed"
                );

                Err(e.into())
            }
        }
    }

    /// Confirm pending payments
    pub async fn confirm_payments(&self) -> anyhow::Result<u64> {
        let pending = self.db.get_pending_payments(self.coin).await?;

        let mut confirmed = 0;

        for payment in pending {
            if let Some(tx_hash) = &payment.tx_hash {
                match self.wallet.get_tx_status(tx_hash).await {
                    Ok(TxStatus::Confirmed) => {
                        self.db
                            .update_payment_status(
                                &payment.id,
                                PaymentStatus::Confirmed,
                                None,
                                None,
                            )
                            .await?;

                        info!(
                            coin = %self.coin,
                            payment_id = %payment.id,
                            tx_hash = %tx_hash,
                            address = %payment.wallet_address,
                            amount = %payment.amount,
                            "Payment confirmed"
                        );

                        confirmed += 1;
                    }
                    Ok(TxStatus::Confirming { confirmations }) => {
                        info!(
                            coin = %self.coin,
                            payment_id = %payment.id,
                            tx_hash = %tx_hash,
                            confirmations = confirmations,
                            required = self.wallet.required_confirmations(),
                            "Payment confirming"
                        );
                    }
                    Ok(TxStatus::Failed(reason)) => {
                        self.db
                            .update_payment_status(
                                &payment.id,
                                PaymentStatus::Failed,
                                None,
                                Some(&reason),
                            )
                            .await?;

                        warn!(
                            coin = %self.coin,
                            payment_id = %payment.id,
                            tx_hash = %tx_hash,
                            reason = %reason,
                            "Payment failed"
                        );
                    }
                    Ok(TxStatus::NotFound) => {
                        warn!(
                            coin = %self.coin,
                            payment_id = %payment.id,
                            tx_hash = %tx_hash,
                            "Transaction not found - may be pending"
                        );
                    }
                    Ok(TxStatus::Pending) => {
                        // Still pending, no action needed
                    }
                    Err(e) => {
                        error!(
                            coin = %self.coin,
                            payment_id = %payment.id,
                            tx_hash = %tx_hash,
                            error = %e,
                            "Error checking transaction status"
                        );
                    }
                }
            }
        }

        Ok(confirmed)
    }

    /// Run a complete processing cycle
    pub async fn run_cycle(&self) -> anyhow::Result<()> {
        // Check if pool is online
        if !self.pool_api.is_online().await {
            warn!(coin = %self.coin, "Pool is offline, skipping cycle");
            return Ok(());
        }

        // 1. Sync shares
        if let Err(e) = self.sync_shares().await {
            error!(coin = %self.coin, error = %e, "Failed to sync shares");
        }

        // 2. Process new blocks
        if let Err(e) = self.process_blocks().await {
            error!(coin = %self.coin, error = %e, "Failed to process blocks");
        }

        // 3. Distribute rewards
        if let Err(e) = self.distribute_rewards().await {
            error!(coin = %self.coin, error = %e, "Failed to distribute rewards");
        }

        // 4. Confirm pending payments
        if let Err(e) = self.confirm_payments().await {
            error!(coin = %self.coin, error = %e, "Failed to confirm payments");
        }

        Ok(())
    }

    /// Run payment processing (called on payment interval)
    pub async fn run_payment_cycle(&self) -> anyhow::Result<()> {
        // Process payments for balances above threshold
        if let Err(e) = self.process_payments().await {
            error!(coin = %self.coin, error = %e, "Failed to process payments");
        }

        Ok(())
    }
}
