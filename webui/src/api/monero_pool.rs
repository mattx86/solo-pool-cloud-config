use chrono::{DateTime, Utc};
use serde::Deserialize;

use crate::models::{AlgorithmStats, WorkerStats, format_hashrate};

/// Client for fetching monero-pool (Monero) statistics
pub struct MoneroPoolClient;

/// monero-pool stats response
#[derive(Debug, Deserialize)]
struct MoneroPoolStats {
    #[serde(default)]
    pool_hashrate: u64,
    #[serde(default)]
    connected_miners: u32,
    #[serde(default)]
    pool_blocks_found: u64,
    #[serde(default)]
    network_height: u64,
    #[serde(default)]
    network_difficulty: u64,
    #[serde(default)]
    last_block_found: Option<i64>,
    #[serde(default)]
    miners: Option<Vec<MoneroPoolMiner>>,
}

/// monero-pool miner info
#[derive(Debug, Deserialize)]
struct MoneroPoolMiner {
    #[serde(default)]
    address: String,
    #[serde(default)]
    hashrate: u64,
    #[serde(default)]
    hashes: u64,
    #[serde(default)]
    valid_shares: Option<u64>,
    #[serde(default)]
    invalid_shares: Option<u64>,
    #[serde(default)]
    last_share: Option<i64>,
}

impl MoneroPoolClient {
    /// Fetch statistics from monero-pool API
    pub async fn fetch_stats(api_base: &str) -> anyhow::Result<AlgorithmStats> {
        let mut stats = AlgorithmStats::default();
        stats.hashrate_unit = "H/s".to_string();

        let client = reqwest::Client::builder()
            .timeout(std::time::Duration::from_secs(5))
            .build()?;

        // Fetch pool stats
        let stats_url = format!("{}/stats", api_base.trim_end_matches('/'));
        match client.get(&stats_url).send().await {
            Ok(response) if response.status().is_success() => {
                stats.online = true;

                if let Ok(pool_stats) = response.json::<MoneroPoolStats>().await {
                    // Pool hashrate
                    let (hr, unit) = format_hashrate(pool_stats.pool_hashrate as f64);
                    stats.total_hashrate = hr;
                    stats.hashrate_unit = unit;

                    // Blocks found
                    stats.blocks_found = pool_stats.pool_blocks_found;
                    stats.worker_count = pool_stats.connected_miners as usize;

                    // Process miners if available
                    if let Some(miners) = pool_stats.miners {
                        for miner in miners {
                            let (hr, unit) = format_hashrate(miner.hashrate as f64);

                            let valid_shares = miner.valid_shares.unwrap_or(miner.hashes);
                            let invalid_shares = miner.invalid_shares.unwrap_or(0);

                            let worker = WorkerStats {
                                name: Self::shorten_address(&miner.address),
                                wallet_address: miner.address.clone(),
                                hashrate: hr,
                                hashrate_unit: unit,
                                shares_accepted: valid_shares,
                                shares_rejected: invalid_shares,
                                blocks_found: 0,
                                best_share: 0.0,
                                last_share_time: miner.last_share.and_then(|t| {
                                    DateTime::from_timestamp(t, 0)
                                }),
                                connected_since: None,
                                is_online: true,
                            };

                            stats.workers.push(worker);
                        }
                        stats.worker_count = stats.workers.len();
                    }
                }
            }
            Ok(response) => {
                tracing::warn!("Monero pool at {} returned status: {}", stats_url, response.status());
            }
            Err(e) => {
                tracing::warn!("Failed to connect to Monero pool at {}: {}", stats_url, e);
            }
        }

        // If no workers from API, create a single "local" worker
        if stats.workers.is_empty() && stats.online {
            let worker = WorkerStats {
                name: "Local Miner".to_string(),
                wallet_address: String::new(),
                hashrate: stats.total_hashrate,
                hashrate_unit: stats.hashrate_unit.clone(),
                shares_accepted: stats.blocks_found,
                shares_rejected: 0,
                blocks_found: stats.blocks_found,
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
