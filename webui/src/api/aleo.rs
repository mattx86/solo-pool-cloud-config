use chrono::{DateTime, Utc};
use serde::Deserialize;

use crate::models::{AlgorithmStats, WorkerStats, format_hashrate};

/// Client for fetching ALEO pool server statistics
pub struct AleoPoolClient;

/// Response from ALEO pool server stats endpoint
#[derive(Debug, Deserialize)]
struct AleoPoolStats {
    #[serde(default)]
    pool_hashrate: f64,
    #[serde(default)]
    blocks_found: u64,
    #[serde(default)]
    current_difficulty: f64,
    #[serde(default)]
    provers: Vec<AleoProverStats>,
}

#[derive(Debug, Deserialize)]
struct AleoProverStats {
    #[serde(default)]
    address: String,
    #[serde(default)]
    hashrate: f64,
    #[serde(default)]
    solutions: u64,
    #[serde(default)]
    last_solution: Option<i64>,
    #[serde(default)]
    connected: bool,
}

impl AleoPoolClient {
    /// Fetch statistics from ALEO pool server API
    pub async fn fetch_stats(api_url: &str) -> anyhow::Result<AlgorithmStats> {
        let mut stats = AlgorithmStats::default();

        // Try to fetch from pool stats endpoint
        let stats_url = format!("{}/stats", api_url.trim_end_matches('/'));

        let client = reqwest::Client::builder()
            .timeout(std::time::Duration::from_secs(5))
            .build()?;

        match client.get(&stats_url).send().await {
            Ok(response) => {
                if response.status().is_success() {
                    stats.online = true;

                    if let Ok(pool_stats) = response.json::<AleoPoolStats>().await {
                        // Set pool-level stats
                        let (hr, unit) = format_hashrate(pool_stats.pool_hashrate);
                        stats.total_hashrate = hr;
                        stats.hashrate_unit = unit;
                        stats.blocks_found = pool_stats.blocks_found;

                        // Convert provers to workers
                        for prover in pool_stats.provers {
                            let (hr, unit) = format_hashrate(prover.hashrate);

                            let worker = WorkerStats {
                                name: Self::shorten_address(&prover.address),
                                wallet_address: prover.address.clone(),
                                hashrate: hr,
                                hashrate_unit: unit,
                                shares_accepted: prover.solutions,
                                shares_rejected: 0,
                                blocks_found: 0,
                                best_share: 0.0,
                                last_share_time: prover.last_solution
                                    .and_then(|ts| DateTime::from_timestamp(ts, 0)),
                                connected_since: None,
                                is_online: prover.connected,
                            };

                            stats.workers.push(worker);
                        }

                        stats.worker_count = stats.workers.len();
                    }
                } else {
                    // Server responded but with error
                    stats.online = false;
                    tracing::warn!("ALEO pool at {} returned status: {}", stats_url, response.status());
                }
            }
            Err(e) => {
                // Try alternative endpoint or mark offline
                stats.online = false;
                tracing::warn!("Failed to connect to ALEO pool at {}: {}", stats_url, e);

                // Try provers endpoint as fallback
                if let Ok(provers_stats) = Self::fetch_provers(api_url).await {
                    stats = provers_stats;
                    stats.online = true;
                }
            }
        }

        Ok(stats)
    }

    /// Fetch provers list as fallback
    async fn fetch_provers(api_url: &str) -> anyhow::Result<AlgorithmStats> {
        let mut stats = AlgorithmStats::default();
        let provers_url = format!("{}/provers", api_url.trim_end_matches('/'));

        let client = reqwest::Client::builder()
            .timeout(std::time::Duration::from_secs(5))
            .build()?;

        let response = client.get(&provers_url).send().await?;

        if response.status().is_success() {
            if let Ok(provers) = response.json::<Vec<AleoProverStats>>().await {
                let mut total_hashrate = 0.0;

                for prover in provers {
                    total_hashrate += prover.hashrate;
                    let (hr, unit) = format_hashrate(prover.hashrate);

                    let worker = WorkerStats {
                        name: Self::shorten_address(&prover.address),
                        wallet_address: prover.address.clone(),
                        hashrate: hr,
                        hashrate_unit: unit,
                        shares_accepted: prover.solutions,
                        shares_rejected: 0,
                        blocks_found: 0,
                        best_share: 0.0,
                        last_share_time: prover.last_solution
                            .and_then(|ts| DateTime::from_timestamp(ts, 0)),
                        connected_since: None,
                        is_online: prover.connected,
                    };

                    stats.workers.push(worker);
                }

                let (hr, unit) = format_hashrate(total_hashrate);
                stats.total_hashrate = hr;
                stats.hashrate_unit = unit;
                stats.worker_count = stats.workers.len();
            }
        }

        Ok(stats)
    }

    /// Shorten an ALEO address for display
    fn shorten_address(address: &str) -> String {
        if address.len() > 16 {
            format!("{}...{}", &address[..8], &address[address.len()-6..])
        } else {
            address.to_string()
        }
    }
}
