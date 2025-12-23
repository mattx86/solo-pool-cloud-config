//! Wallet integration modules for different coins
//!
//! Each wallet module provides:
//! - Balance checking
//! - Transaction creation
//! - Transaction confirmation checking

pub mod aleo;
pub mod monero;
pub mod tari;

use async_trait::async_trait;
use rust_decimal::Decimal;
use thiserror::Error;

#[derive(Debug, Error)]
pub enum WalletError {
    #[error("RPC connection failed: {0}")]
    ConnectionFailed(String),

    #[error("RPC request failed: {0}")]
    RpcError(String),

    #[error("Insufficient balance: have {have}, need {need}")]
    InsufficientBalance { have: Decimal, need: Decimal },

    #[error("Invalid address: {0}")]
    InvalidAddress(String),

    #[error("Transaction failed: {0}")]
    TransactionFailed(String),

    #[error("Transaction not found: {0}")]
    TransactionNotFound(String),

    #[error("Wallet locked")]
    WalletLocked,

    #[error("Configuration error: {0}")]
    ConfigError(String),
}

/// Result type for wallet operations
pub type WalletResult<T> = Result<T, WalletError>;

/// Transaction status
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum TxStatus {
    /// Transaction is in the mempool
    Pending,
    /// Transaction has confirmations but not enough
    Confirming { confirmations: u64 },
    /// Transaction is fully confirmed
    Confirmed,
    /// Transaction failed or was rejected
    Failed(String),
    /// Transaction not found
    NotFound,
}

/// Common wallet operations trait
#[async_trait]
pub trait Wallet: Send + Sync {
    /// Get the pool wallet's unlocked balance
    async fn get_balance(&self) -> WalletResult<Decimal>;

    /// Get the pool wallet's total balance (including locked)
    async fn get_total_balance(&self) -> WalletResult<Decimal>;

    /// Validate a wallet address
    async fn validate_address(&self, address: &str) -> WalletResult<bool>;

    /// Send a payment to a single address
    /// Returns the transaction hash
    async fn send_payment(&self, to_address: &str, amount: Decimal) -> WalletResult<String>;

    /// Send payments to multiple addresses (batch payment)
    /// Returns a list of (address, tx_hash) pairs
    async fn send_batch_payment(
        &self,
        payments: &[(String, Decimal)],
    ) -> WalletResult<Vec<(String, String)>>;

    /// Check the status of a transaction
    async fn get_tx_status(&self, tx_hash: &str) -> WalletResult<TxStatus>;

    /// Get required confirmations for a transaction to be considered final
    fn required_confirmations(&self) -> u64;
}
