use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use tokio::sync::RwLock;

use crate::config::Config;

/// Application state shared across handlers
pub struct AppState {
    pub config: Config,
    pub stats: RwLock<PoolStats>,
}

/// Overall pool statistics
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct PoolStats {
    pub btc: AlgorithmStats,
    pub bch: AlgorithmStats,
    pub dgb: AlgorithmStats,
    pub xmr: AlgorithmStats,
    pub xtm: AlgorithmStats,
    pub xmr_xtm_merge: AlgorithmStats,
    pub aleo: AlgorithmStats,
    pub last_updated: Option<DateTime<Utc>>,
}

/// Statistics for a specific algorithm/pool
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct AlgorithmStats {
    pub name: String,
    pub algorithm: String,
    pub enabled: bool,
    pub online: bool,
    pub stratum_port: u16,

    // Aggregate stats
    pub total_hashrate: f64,
    pub hashrate_unit: String,
    pub blocks_found: u64,
    pub last_block_time: Option<DateTime<Utc>>,
    pub best_share: f64,

    // Worker stats
    pub workers: Vec<WorkerStats>,
    pub worker_count: usize,

    // Connection info
    pub stratum_url: String,
}

/// Statistics for an individual worker
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WorkerStats {
    pub name: String,
    pub hashrate: f64,
    pub hashrate_unit: String,
    pub shares_accepted: u64,
    pub shares_rejected: u64,
    pub best_share: f64,
    pub last_share_time: Option<DateTime<Utc>>,
    pub connected_since: Option<DateTime<Utc>>,
    pub is_online: bool,
}

impl WorkerStats {
    pub fn new(name: String) -> Self {
        Self {
            name,
            hashrate: 0.0,
            hashrate_unit: "H/s".to_string(),
            shares_accepted: 0,
            shares_rejected: 0,
            best_share: 0.0,
            last_share_time: None,
            connected_since: None,
            is_online: false,
        }
    }
}

/// CKPool log entry for parsing
#[derive(Debug, Clone)]
pub struct CkPoolLogEntry {
    pub timestamp: DateTime<Utc>,
    pub worker: String,
    pub hashrate: f64,
    pub shares: u64,
    pub best_share: f64,
}

/// Format hashrate with appropriate unit
pub fn format_hashrate(hashrate: f64) -> (f64, String) {
    if hashrate >= 1e18 {
        (hashrate / 1e18, "EH/s".to_string())
    } else if hashrate >= 1e15 {
        (hashrate / 1e15, "PH/s".to_string())
    } else if hashrate >= 1e12 {
        (hashrate / 1e12, "TH/s".to_string())
    } else if hashrate >= 1e9 {
        (hashrate / 1e9, "GH/s".to_string())
    } else if hashrate >= 1e6 {
        (hashrate / 1e6, "MH/s".to_string())
    } else if hashrate >= 1e3 {
        (hashrate / 1e3, "KH/s".to_string())
    } else {
        (hashrate, "H/s".to_string())
    }
}
