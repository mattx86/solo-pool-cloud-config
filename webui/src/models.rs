use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use std::sync::Arc;
use tokio::sync::RwLock;

use crate::config::Config;
use crate::db::Database;

/// Application state shared across handlers
pub struct AppState {
    pub config: Config,
    pub stats: RwLock<PoolStats>,
    /// Detected server IP address
    pub server_ip: String,
    /// Database for persistent worker stats
    pub db: Arc<Database>,
}

/// Detect the server's public IP address
pub async fn detect_server_ip() -> String {
    // Try public IP detection services
    let services = [
        "https://api.ipify.org",
        "https://ifconfig.me/ip",
        "https://icanhazip.com",
    ];

    for service in &services {
        if let Ok(response) = reqwest::get(*service).await {
            if let Ok(ip) = response.text().await {
                let ip = ip.trim().to_string();
                if !ip.is_empty() && ip.parse::<std::net::IpAddr>().is_ok() {
                    return ip;
                }
            }
        }
    }

    // Fall back to local IP detection
    if let Ok(socket) = std::net::UdpSocket::bind("0.0.0.0:0") {
        if socket.connect("8.8.8.8:80").is_ok() {
            if let Ok(addr) = socket.local_addr() {
                return addr.ip().to_string();
            }
        }
    }

    // Last resort fallback
    "YOUR_SERVER_IP".to_string()
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

/// Node sync status
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct SyncStatus {
    /// Whether the node is reachable
    pub node_online: bool,
    /// Whether the blockchain is fully synced
    pub is_synced: bool,
    /// Current block height
    pub current_height: u64,
    /// Target block height (if known)
    #[serde(skip_serializing_if = "Option::is_none")]
    pub target_height: Option<u64>,
    /// Sync progress as percentage (0.0 - 100.0)
    pub sync_percent: f64,
    /// Human-readable status message
    pub status_message: String,
}

/// Statistics for a specific algorithm/pool
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct AlgorithmStats {
    pub name: String,
    pub algorithm: String,
    pub enabled: bool,
    pub online: bool,
    pub stratum_port: u16,

    // Node sync status
    #[serde(default)]
    pub sync_status: SyncStatus,

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
    pub username_format: String,
    pub password: String,

    // Pool wallet info (for pools with PPLNS payouts)
    /// Primary pool wallet address (XMR, XTM, ALEO)
    #[serde(skip_serializing_if = "Option::is_none")]
    pub pool_wallet_address: Option<String>,
    /// Secondary pool wallet address (XTM for merge mining)
    #[serde(skip_serializing_if = "Option::is_none")]
    pub pool_wallet_address_secondary: Option<String>,

    // Pool fee info
    /// Pool fee percentage (0.0 = fee-free)
    #[serde(default)]
    pub pool_fee_percent: f64,
}

/// Statistics for an individual worker
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WorkerStats {
    pub name: String,
    /// Wallet address extracted from worker name (for pools using wallet.worker format)
    #[serde(default)]
    pub wallet_address: String,
    pub hashrate: f64,
    pub hashrate_unit: String,
    pub shares_accepted: u64,
    pub shares_rejected: u64,
    /// Blocks found by this worker
    #[serde(default)]
    pub blocks_found: u64,
    pub best_share: f64,
    pub last_share_time: Option<DateTime<Utc>>,
    pub connected_since: Option<DateTime<Utc>>,
    pub is_online: bool,
}

impl WorkerStats {
    pub fn new(name: String) -> Self {
        // Extract wallet address from name if format is "wallet.worker"
        let wallet_address = if name.contains('.') {
            name.split('.').next().unwrap_or("").to_string()
        } else {
            String::new()
        };

        Self {
            name,
            wallet_address,
            hashrate: 0.0,
            hashrate_unit: "H/s".to_string(),
            shares_accepted: 0,
            shares_rejected: 0,
            blocks_found: 0,
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
