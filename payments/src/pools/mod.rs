//! Pool API integration modules
//!
//! Each pool module provides:
//! - Share tracking via pool API
//! - Block detection
//! - Miner statistics

pub mod aleo;
pub mod minotari;
pub mod monero_pool;
pub mod tari;

use async_trait::async_trait;
use rust_decimal::Decimal;
use serde::{Deserialize, Serialize};
use thiserror::Error;

#[derive(Debug, Error)]
pub enum PoolError {
    #[error("API connection failed: {0}")]
    ConnectionFailed(String),

    #[error("API request failed: {0}")]
    ApiError(String),

    #[error("Parse error: {0}")]
    ParseError(String),

    #[error("Pool offline")]
    PoolOffline,
}

pub type PoolResult<T> = Result<T, PoolError>;

/// Share information from pool
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ShareInfo {
    /// Wallet address that submitted the share
    pub wallet_address: String,
    /// Worker name (from username.worker format)
    pub worker_name: String,
    /// Share difficulty
    pub difficulty: Decimal,
    /// Block height when share was submitted
    pub block_height: Option<i64>,
    /// Whether this share found a block
    pub is_block: bool,
    /// Timestamp (Unix epoch seconds)
    pub timestamp: i64,
}

/// Block found by the pool
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BlockInfo {
    /// Block height
    pub height: i64,
    /// Block hash
    pub hash: String,
    /// Block reward in atomic units
    pub reward: Decimal,
    /// Wallet that found the block
    pub finder_wallet: String,
    /// Worker that found the block
    pub finder_worker: String,
    /// Block timestamp
    pub timestamp: i64,
}

/// Miner statistics from pool
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MinerStats {
    /// Wallet address
    pub wallet_address: String,
    /// Current hashrate
    pub hashrate: f64,
    /// Hashrate unit (H/s, KH/s, MH/s, etc.)
    pub hashrate_unit: String,
    /// Total shares submitted
    pub total_shares: u64,
    /// Valid shares in current round
    pub valid_shares: u64,
    /// Invalid/stale shares
    pub invalid_shares: u64,
    /// Last share timestamp
    pub last_share: Option<i64>,
}

/// Pool statistics
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PoolStats {
    /// Pool hashrate
    pub hashrate: f64,
    /// Hashrate unit
    pub hashrate_unit: String,
    /// Number of connected miners
    pub miners: u32,
    /// Total blocks found
    pub blocks_found: u64,
    /// Current block height
    pub current_height: i64,
    /// Network difficulty
    pub network_difficulty: Decimal,
    /// Last block found timestamp
    pub last_block_time: Option<i64>,
}

/// Common pool API trait
#[async_trait]
pub trait PoolApi: Send + Sync {
    /// Check if pool is online
    async fn is_online(&self) -> bool;

    /// Get pool statistics
    async fn get_pool_stats(&self) -> PoolResult<PoolStats>;

    /// Get statistics for a specific miner
    async fn get_miner_stats(&self, wallet_address: &str) -> PoolResult<MinerStats>;

    /// Get all active miners
    async fn get_all_miners(&self) -> PoolResult<Vec<MinerStats>>;

    /// Get recent shares (for a time range)
    /// Returns shares since the given Unix timestamp
    async fn get_shares_since(&self, since_timestamp: i64) -> PoolResult<Vec<ShareInfo>>;

    /// Get blocks found by the pool
    async fn get_blocks(&self, limit: u32) -> PoolResult<Vec<BlockInfo>>;

    /// Get blocks found since a specific height
    async fn get_blocks_since_height(&self, height: i64) -> PoolResult<Vec<BlockInfo>>;
}
