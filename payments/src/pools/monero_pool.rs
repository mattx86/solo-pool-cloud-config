//! monero-pool API integration for Monero
//!
//! monero-pool (jtgrassie/monero-pool) provides a local API:
//! - GET /stats - Pool and miner statistics
//! - GET /workers - Worker list with shares

use super::{BlockInfo, MinerStats, PoolApi, PoolError, PoolResult, PoolStats, ShareInfo};
use async_trait::async_trait;
use rust_decimal::Decimal;
use serde::Deserialize;
use std::str::FromStr;

/// monero-pool API client
pub struct MoneroPoolApi {
    api_url: String,
    client: reqwest::Client,
}

impl MoneroPoolApi {
    /// Create a new monero-pool API client
    /// Default monero-pool API is at http://127.0.0.1:4243
    pub fn new(api_url: &str) -> Self {
        Self {
            api_url: api_url.trim_end_matches('/').to_string(),
            client: reqwest::Client::builder()
                .timeout(std::time::Duration::from_secs(10))
                .build()
                .expect("Failed to create HTTP client"),
        }
    }

    async fn get<T: for<'de> Deserialize<'de>>(&self, path: &str) -> PoolResult<T> {
        let url = format!("{}{}", self.api_url, path);

        let response = self
            .client
            .get(&url)
            .send()
            .await
            .map_err(|e| PoolError::ConnectionFailed(e.to_string()))?;

        if !response.status().is_success() {
            return Err(PoolError::ApiError(format!(
                "HTTP {}: {}",
                response.status(),
                response.status().canonical_reason().unwrap_or("Unknown")
            )));
        }

        response
            .json()
            .await
            .map_err(|e| PoolError::ParseError(e.to_string()))
    }
}

#[async_trait]
impl PoolApi for MoneroPoolApi {
    async fn is_online(&self) -> bool {
        self.get::<serde_json::Value>("/stats").await.is_ok()
    }

    async fn get_pool_stats(&self) -> PoolResult<PoolStats> {
        let stats: MoneroPoolStats = self.get("/stats").await?;

        Ok(PoolStats {
            hashrate: stats.pool_hashrate as f64,
            hashrate_unit: "H/s".to_string(),
            miners: stats.connected_miners,
            blocks_found: stats.pool_blocks_found,
            current_height: stats.network_height as i64,
            network_difficulty: Decimal::from(stats.network_difficulty),
            last_block_time: stats.last_block_found,
        })
    }

    async fn get_miner_stats(&self, wallet_address: &str) -> PoolResult<MinerStats> {
        // monero-pool provides miner stats in the /stats endpoint under miners array
        let stats: MoneroPoolStats = self.get("/stats").await?;

        // Find the miner in the list
        if let Some(miners) = stats.miners {
            for miner in miners {
                if miner.address == wallet_address {
                    return Ok(MinerStats {
                        wallet_address: wallet_address.to_string(),
                        hashrate: miner.hashrate as f64,
                        hashrate_unit: "H/s".to_string(),
                        total_shares: miner.hashes,
                        valid_shares: miner.valid_shares.unwrap_or(miner.hashes),
                        invalid_shares: miner.invalid_shares.unwrap_or(0),
                        last_share: miner.last_share,
                    });
                }
            }
        }

        // Miner not found
        Err(PoolError::ApiError(format!(
            "Miner {} not found",
            wallet_address
        )))
    }

    async fn get_all_miners(&self) -> PoolResult<Vec<MinerStats>> {
        let stats: MoneroPoolStats = self.get("/stats").await?;

        let miners = stats.miners.unwrap_or_default();
        Ok(miners
            .into_iter()
            .map(|m| MinerStats {
                wallet_address: m.address,
                hashrate: m.hashrate as f64,
                hashrate_unit: "H/s".to_string(),
                total_shares: m.hashes,
                valid_shares: m.valid_shares.unwrap_or(m.hashes),
                invalid_shares: m.invalid_shares.unwrap_or(0),
                last_share: m.last_share,
            })
            .collect())
    }

    async fn get_shares_since(&self, since_timestamp: i64) -> PoolResult<Vec<ShareInfo>> {
        // monero-pool tracks shares in LMDB database
        // The /workers endpoint provides share counts but not individual shares
        // We track share deltas by polling and comparing totals
        let stats: MoneroPoolStats = self.get("/stats").await?;

        let mut shares = Vec::new();
        if let Some(miners) = stats.miners {
            for miner in miners {
                // Only include miners with recent activity
                if let Some(last_share) = miner.last_share {
                    if last_share >= since_timestamp {
                        shares.push(ShareInfo {
                            wallet_address: miner.address.clone(),
                            worker_name: "default".to_string(),
                            difficulty: Decimal::from(miner.hashrate),
                            block_height: Some(stats.network_height as i64),
                            is_block: false,
                            timestamp: last_share,
                        });
                    }
                }
            }
        }

        Ok(shares)
    }

    async fn get_blocks(&self, limit: u32) -> PoolResult<Vec<BlockInfo>> {
        let stats: MoneroPoolStats = self.get("/stats").await?;

        let blocks = stats.blocks.unwrap_or_default();
        Ok(blocks
            .into_iter()
            .take(limit as usize)
            .map(|b| BlockInfo {
                height: b.height as i64,
                hash: b.hash,
                reward: Decimal::from_str(&b.reward.to_string()).unwrap_or_default(),
                finder_wallet: b.address.unwrap_or_else(|| "unknown".to_string()),
                finder_worker: "monero-pool".to_string(),
                timestamp: b.timestamp as i64,
            })
            .collect())
    }

    async fn get_blocks_since_height(&self, height: i64) -> PoolResult<Vec<BlockInfo>> {
        let blocks = self.get_blocks(100).await?;
        Ok(blocks.into_iter().filter(|b| b.height > height).collect())
    }
}

// monero-pool API response types

#[derive(Deserialize)]
struct MoneroPoolStats {
    pool_hashrate: u64,
    connected_miners: u32,
    pool_blocks_found: u64,
    network_height: u64,
    network_difficulty: u64,
    last_block_found: Option<i64>,
    miners: Option<Vec<MoneroPoolMiner>>,
    blocks: Option<Vec<MoneroPoolBlock>>,
}

#[derive(Deserialize)]
struct MoneroPoolMiner {
    address: String,
    hashrate: u64,
    hashes: u64,
    valid_shares: Option<u64>,
    invalid_shares: Option<u64>,
    last_share: Option<i64>,
}

#[derive(Deserialize)]
struct MoneroPoolBlock {
    height: u64,
    hash: String,
    reward: u64,
    address: Option<String>,
    timestamp: u64,
}
