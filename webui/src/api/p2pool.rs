use chrono::{DateTime, Utc};
use serde::Deserialize;

use crate::models::{AlgorithmStats, WorkerStats, format_hashrate};

/// Client for fetching P2Pool (Monero) statistics
pub struct P2PoolClient;

/// P2Pool local stats response
#[derive(Debug, Deserialize)]
struct P2PoolLocalStats {
    #[serde(default)]
    hashrate_15m: f64,
    #[serde(default)]
    hashrate_1h: f64,
    #[serde(default)]
    hashrate_24h: f64,
    #[serde(default)]
    total_hashes: u64,
    #[serde(default)]
    shares_found: u64,
    #[serde(default)]
    shares_failed: u64,
    #[serde(default)]
    average_effort: f64,
    #[serde(default)]
    current_effort: f64,
    #[serde(default)]
    connections: u64,
}

/// P2Pool pool stats response
#[derive(Debug, Deserialize)]
struct P2PoolPoolStats {
    #[serde(default)]
    pool_hashrate: f64,
    #[serde(default)]
    pool_blocks: u64,
    #[serde(default)]
    miners: u64,
}

/// P2Pool miner info
#[derive(Debug, Deserialize)]
struct P2PoolMinerStats {
    #[serde(default)]
    address: String,
    #[serde(default)]
    hashrate: f64,
    #[serde(default)]
    shares: u64,
    #[serde(default)]
    last_share: i64,
}

impl P2PoolClient {
    /// Fetch statistics from P2Pool local API
    pub async fn fetch_stats(api_base: &str) -> anyhow::Result<AlgorithmStats> {
        let mut stats = AlgorithmStats::default();
        stats.hashrate_unit = "H/s".to_string();

        let client = reqwest::Client::builder()
            .timeout(std::time::Duration::from_secs(5))
            .build()?;

        // Fetch local stats
        let local_url = format!("{}/local/stats", api_base.trim_end_matches('/'));
        if let Ok(response) = client.get(&local_url).send().await {
            if response.status().is_success() {
                stats.online = true;

                if let Ok(local_stats) = response.json::<P2PoolLocalStats>().await {
                    // Use 15m hashrate as primary
                    let (hr, unit) = format_hashrate(local_stats.hashrate_15m);
                    stats.total_hashrate = hr;
                    stats.hashrate_unit = unit;

                    // Shares as pseudo-blocks for solo mining context
                    stats.blocks_found = local_stats.shares_found;
                    stats.worker_count = local_stats.connections as usize;
                }
            }
        }

        // Fetch connected miners/workers
        let miners_url = format!("{}/local/miners", api_base.trim_end_matches('/'));
        if let Ok(response) = client.get(&miners_url).send().await {
            if response.status().is_success() {
                if let Ok(miners) = response.json::<Vec<P2PoolMinerStats>>().await {
                    for miner in miners {
                        let (hr, unit) = format_hashrate(miner.hashrate);

                        let worker = WorkerStats {
                            name: Self::shorten_address(&miner.address),
                            hashrate: hr,
                            hashrate_unit: unit,
                            shares_accepted: miner.shares,
                            shares_rejected: 0,
                            best_share: 0.0,
                            last_share_time: if miner.last_share > 0 {
                                DateTime::from_timestamp(miner.last_share, 0)
                            } else {
                                None
                            },
                            connected_since: None,
                            is_online: true,
                        };

                        stats.workers.push(worker);
                    }
                    stats.worker_count = stats.workers.len();
                }
            }
        }

        // If no workers from API, create a single "local" worker
        if stats.workers.is_empty() && stats.online {
            let worker = WorkerStats {
                name: "Local Miner".to_string(),
                hashrate: stats.total_hashrate,
                hashrate_unit: stats.hashrate_unit.clone(),
                shares_accepted: stats.blocks_found,
                shares_rejected: 0,
                best_share: 0.0,
                last_share_time: None,
                connected_since: None,
                is_online: true,
            };
            stats.workers.push(worker);
            stats.worker_count = 1;
        }

        Ok(stats)
    }

    /// Shorten a Monero address for display
    fn shorten_address(address: &str) -> String {
        if address.len() > 20 {
            format!("{}...{}", &address[..10], &address[address.len()-8..])
        } else {
            address.to_string()
        }
    }
}
