use chrono::{DateTime, Utc};
use serde::Deserialize;
use tokio::io::{AsyncReadExt, AsyncWriteExt};

use crate::models::{AlgorithmStats, WorkerStats, format_hashrate};

/// Client for reading CKPool statistics via Unix socket API
/// Each CKPool instance must have its own socket directory configured via -s flag
pub struct CkPoolClient;

/// CKPool stats response from socket API
#[derive(Debug, Deserialize)]
struct CkPoolStatsResponse {
    #[serde(default)]
    runtime: u64,
    #[serde(default)]
    users: u64,
    #[serde(default)]
    workers: u64,
    #[serde(default)]
    idle: u64,
    #[serde(default)]
    disconnected: u64,
    #[serde(default)]
    hashrate1m: f64,
    #[serde(default)]
    hashrate5m: f64,
    #[serde(default)]
    hashrate15m: f64,
    #[serde(default)]
    hashrate1hr: f64,
    #[serde(default)]
    hashrate6hr: f64,
    #[serde(default)]
    hashrate1d: f64,
    #[serde(default)]
    hashrate7d: f64,
    #[serde(default)]
    diff: f64,
    #[serde(default)]
    accepted: u64,
    #[serde(default)]
    rejected: u64,
    #[serde(default)]
    bestshare: f64,
    #[serde(rename = "SPS1m", default)]
    sps1m: f64,
    #[serde(rename = "SPS5m", default)]
    sps5m: f64,
}

/// CKPool user/worker entry from socket API
#[derive(Debug, Deserialize)]
struct CkPoolUserEntry {
    #[serde(default)]
    user: String,
    #[serde(default)]
    worker: String,
    #[serde(default)]
    hashrate1m: f64,
    #[serde(default)]
    hashrate5m: f64,
    #[serde(default)]
    hashrate1hr: f64,
    #[serde(default)]
    shares: u64,
    #[serde(default)]
    bestshare: f64,
    #[serde(default)]
    bestever: f64,
    #[serde(default)]
    lastshare: i64,
    #[serde(default)]
    idle: bool,
}

impl CkPoolClient {
    /// Fetch statistics from CKPool via Unix socket API
    /// socket_dir: Directory containing the stratifier socket (e.g., /tmp/ckpool-btc)
    pub async fn fetch_stats(socket_dir: &str) -> anyhow::Result<AlgorithmStats> {
        Self::fetch_via_socket(socket_dir).await
    }

    /// Fetch stats via Unix socket API
    #[cfg(unix)]
    async fn fetch_via_socket(socket_dir: &str) -> anyhow::Result<AlgorithmStats> {
        use tokio::net::UnixStream;

        let socket_path = format!("{}/stratifier", socket_dir.trim_end_matches('/'));
        let mut stats = AlgorithmStats::default();

        // Connect to the stratifier socket
        let mut stream = UnixStream::connect(&socket_path).await?;
        stats.online = true;

        // Request pool stats
        stream.write_all(b"stats\n").await?;
        let mut response = vec![0u8; 8192];
        let n = stream.read(&mut response).await?;
        let response_str = String::from_utf8_lossy(&response[..n]);

        if let Ok(pool_stats) = serde_json::from_str::<CkPoolStatsResponse>(&response_str) {
            // Use 5-minute hashrate as primary
            let (hr, unit) = format_hashrate(pool_stats.hashrate5m);
            stats.total_hashrate = hr;
            stats.hashrate_unit = unit;
            stats.best_share = pool_stats.bestshare;
            stats.worker_count = pool_stats.workers as usize;
        }

        // Request worker details
        let mut stream = UnixStream::connect(&socket_path).await?;
        stream.write_all(b"workers\n").await?;
        let mut response = vec![0u8; 65536];
        let n = stream.read(&mut response).await?;
        let response_str = String::from_utf8_lossy(&response[..n]);

        // Parse workers - response may be JSON array or newline-separated JSON objects
        if response_str.trim().starts_with('[') {
            if let Ok(workers) = serde_json::from_str::<Vec<CkPoolUserEntry>>(&response_str) {
                for w in workers {
                    let (hr, unit) = format_hashrate(w.hashrate5m);
                    let worker_name = if w.worker.is_empty() { w.user.clone() } else { format!("{}.{}", w.user, w.worker) };
                    let worker = WorkerStats {
                        name: worker_name.clone(),
                        wallet_address: w.user.clone(), // CKPool uses wallet.worker format
                        hashrate: hr,
                        hashrate_unit: unit,
                        shares_accepted: w.shares,
                        shares_rejected: 0,
                        blocks_found: 0,
                        best_share: w.bestshare.max(w.bestever),
                        last_share_time: if w.lastshare > 0 {
                            DateTime::from_timestamp(w.lastshare, 0)
                        } else {
                            None
                        },
                        connected_since: None,
                        is_online: !w.idle,
                    };
                    stats.workers.push(worker);
                }
                stats.worker_count = stats.workers.len();
            }
        } else {
            // Try parsing as newline-separated JSON objects
            for line in response_str.lines() {
                if let Ok(w) = serde_json::from_str::<CkPoolUserEntry>(line) {
                    let (hr, unit) = format_hashrate(w.hashrate5m);
                    let worker_name = if w.worker.is_empty() { w.user.clone() } else { format!("{}.{}", w.user, w.worker) };
                    let worker = WorkerStats {
                        name: worker_name.clone(),
                        wallet_address: w.user.clone(), // CKPool uses wallet.worker format
                        hashrate: hr,
                        hashrate_unit: unit,
                        shares_accepted: w.shares,
                        shares_rejected: 0,
                        blocks_found: 0,
                        best_share: w.bestshare.max(w.bestever),
                        last_share_time: if w.lastshare > 0 {
                            DateTime::from_timestamp(w.lastshare, 0)
                        } else {
                            None
                        },
                        connected_since: None,
                        is_online: !w.idle,
                    };
                    stats.workers.push(worker);
                }
            }
            stats.worker_count = stats.workers.len();
        }

        // Get blocks found from users command (contains block count per user)
        let mut stream = UnixStream::connect(&socket_path).await?;
        stream.write_all(b"users\n").await?;
        let mut response = vec![0u8; 65536];
        let n = stream.read(&mut response).await?;
        let response_str = String::from_utf8_lossy(&response[..n]);

        // Parse for block information if available
        if let Ok(json) = serde_json::from_str::<serde_json::Value>(&response_str) {
            if let Some(blocks) = json.get("blocks").and_then(|v| v.as_u64()) {
                stats.blocks_found = blocks;
            }
        }

        Ok(stats)
    }

    /// Stub for non-Unix platforms - socket API not available
    #[cfg(not(unix))]
    async fn fetch_via_socket(_socket_dir: &str) -> anyhow::Result<AlgorithmStats> {
        anyhow::bail!("CKPool socket API requires Unix platform")
    }
}
