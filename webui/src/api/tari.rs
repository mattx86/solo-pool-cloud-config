use chrono::{DateTime, Utc};
use serde::Deserialize;

use crate::models::{AlgorithmStats, WorkerStats, format_hashrate};

/// Client for fetching Tari merge mining proxy statistics
pub struct TariMergeClient;

/// Tari merge mining proxy stats (if available via API)
#[derive(Debug, Deserialize)]
struct TariMergeStats {
    #[serde(default)]
    hashrate: f64,
    #[serde(default)]
    blocks_found: u64,
    #[serde(default)]
    connected_miners: u64,
    #[serde(default)]
    difficulty: f64,
}

#[derive(Debug, Deserialize)]
struct TariMinerStats {
    #[serde(default)]
    worker_id: String,
    #[serde(default)]
    hashrate: f64,
    #[serde(default)]
    shares: u64,
    #[serde(default)]
    last_share: i64,
    #[serde(default)]
    connected: bool,
}

impl TariMergeClient {
    /// Fetch statistics from Tari merge mining proxy
    /// Note: The actual API endpoints depend on the merge mining proxy implementation
    pub async fn fetch_stats(api_base: &str) -> anyhow::Result<AlgorithmStats> {
        let mut stats = AlgorithmStats::default();
        stats.hashrate_unit = "H/s".to_string();

        let client = reqwest::Client::builder()
            .timeout(std::time::Duration::from_secs(5))
            .build()?;

        // Try to fetch stats from merge mining proxy
        // The exact endpoints depend on the Tari merge mining proxy implementation
        let stats_url = format!("{}/stats", api_base.trim_end_matches('/'));

        match client.get(&stats_url).send().await {
            Ok(response) => {
                if response.status().is_success() {
                    stats.online = true;

                    if let Ok(merge_stats) = response.json::<TariMergeStats>().await {
                        let (hr, unit) = format_hashrate(merge_stats.hashrate);
                        stats.total_hashrate = hr;
                        stats.hashrate_unit = unit;
                        stats.blocks_found = merge_stats.blocks_found;
                        stats.worker_count = merge_stats.connected_miners as usize;
                    }
                } else {
                    stats.online = false;
                }
            }
            Err(e) => {
                tracing::warn!("Failed to connect to Tari merge proxy at {}: {}", stats_url, e);
                stats.online = false;
            }
        }

        // Try to fetch connected miners
        let miners_url = format!("{}/miners", api_base.trim_end_matches('/'));
        if let Ok(response) = client.get(&miners_url).send().await {
            if response.status().is_success() {
                if let Ok(miners) = response.json::<Vec<TariMinerStats>>().await {
                    for miner in miners {
                        let (hr, unit) = format_hashrate(miner.hashrate);

                        let worker_name = if miner.worker_id.is_empty() {
                            "Unknown".to_string()
                        } else {
                            miner.worker_id
                        };
                        let wallet_address = if worker_name.contains('.') {
                            worker_name.split('.').next().unwrap_or("").to_string()
                        } else {
                            String::new()
                        };

                        let worker = WorkerStats {
                            name: worker_name,
                            wallet_address,
                            hashrate: hr,
                            hashrate_unit: unit,
                            shares_accepted: miner.shares,
                            shares_rejected: 0,
                            blocks_found: 0,
                            best_share: 0.0,
                            last_share_time: if miner.last_share > 0 {
                                DateTime::from_timestamp(miner.last_share, 0)
                            } else {
                                None
                            },
                            connected_since: None,
                            is_online: miner.connected,
                        };

                        stats.workers.push(worker);
                    }
                    stats.worker_count = stats.workers.len();
                }
            }
        }

        Ok(stats)
    }
}

/// Client for Tari solo miner (tari_only mode)
pub struct TariMinerClient;

impl TariMinerClient {
    /// Fetch statistics from minotari_miner
    pub async fn fetch_stats(api_base: &str) -> anyhow::Result<AlgorithmStats> {
        let mut stats = AlgorithmStats::default();
        stats.hashrate_unit = "H/s".to_string();

        let client = reqwest::Client::builder()
            .timeout(std::time::Duration::from_secs(5))
            .build()?;

        // Try to get miner stats
        let stats_url = format!("{}/stats", api_base.trim_end_matches('/'));

        match client.get(&stats_url).send().await {
            Ok(response) => {
                if response.status().is_success() {
                    stats.online = true;

                    // Parse miner stats
                    if let Ok(json) = response.json::<serde_json::Value>().await {
                        if let Some(hr) = json.get("hashrate").and_then(|v| v.as_f64()) {
                            let (formatted_hr, unit) = format_hashrate(hr);
                            stats.total_hashrate = formatted_hr;
                            stats.hashrate_unit = unit;
                        }

                        if let Some(blocks) = json.get("blocks_found").and_then(|v| v.as_u64()) {
                            stats.blocks_found = blocks;
                        }
                    }

                    // Create a single worker entry for the local miner
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
                } else {
                    stats.online = false;
                }
            }
            Err(e) => {
                tracing::warn!("Failed to connect to Tari miner at {}: {}", stats_url, e);
                stats.online = false;
            }
        }

        Ok(stats)
    }
}
