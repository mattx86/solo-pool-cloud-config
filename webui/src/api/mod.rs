mod ckpool;
mod aleo;
mod p2pool;
mod tari;

use std::sync::Arc;
use chrono::Utc;
use tokio::time::{interval, Duration};

use crate::models::{AppState, PoolStats, AlgorithmStats};

pub use ckpool::CkPoolClient;
pub use aleo::AleoPoolClient;
pub use p2pool::P2PoolClient;
pub use tari::{TariMergeClient, TariMinerClient};

/// Background task to periodically update pool statistics
pub async fn stats_updater(state: Arc<AppState>) {
    let refresh_secs = state.config.server.refresh_interval_secs;
    let mut interval = interval(Duration::from_secs(refresh_secs));

    tracing::info!("Stats updater started (refresh every {}s)", refresh_secs);

    loop {
        interval.tick().await;

        let mut new_stats = PoolStats::default();

        // Fetch BTC stats (CKPool)
        if let Some(ref btc_config) = state.config.pools.btc {
            if btc_config.enabled {
                new_stats.btc = fetch_ckpool_stats(btc_config, "BTC").await;
            }
        }

        // Fetch BCH stats (CKPool)
        if let Some(ref bch_config) = state.config.pools.bch {
            if bch_config.enabled {
                new_stats.bch = fetch_ckpool_stats(bch_config, "BCH").await;
            }
        }

        // Fetch DGB stats (CKPool)
        if let Some(ref dgb_config) = state.config.pools.dgb {
            if dgb_config.enabled {
                new_stats.dgb = fetch_ckpool_stats(dgb_config, "DGB").await;
            }
        }

        // Fetch XMR stats (P2Pool - monero_only mode)
        if let Some(ref xmr_config) = state.config.pools.xmr {
            if xmr_config.enabled {
                match P2PoolClient::fetch_stats(&xmr_config.api_url).await {
                    Ok(mut stats) => {
                        stats.name = xmr_config.name.clone();
                        stats.algorithm = xmr_config.algorithm.clone();
                        stats.enabled = true;
                        stats.stratum_port = xmr_config.stratum_port;
                        stats.stratum_url = format!("stratum+tcp://YOUR_IP:{}", xmr_config.stratum_port);
                        new_stats.xmr = stats;
                    }
                    Err(e) => {
                        tracing::warn!("Failed to fetch XMR stats: {}", e);
                        new_stats.xmr = AlgorithmStats {
                            name: xmr_config.name.clone(),
                            algorithm: xmr_config.algorithm.clone(),
                            enabled: true,
                            online: false,
                            stratum_port: xmr_config.stratum_port,
                            stratum_url: format!("stratum+tcp://YOUR_IP:{}", xmr_config.stratum_port),
                            ..Default::default()
                        };
                    }
                }
            }
        }

        // Fetch XTM stats (minotari_miner - tari_only mode)
        if let Some(ref xtm_config) = state.config.pools.xtm {
            if xtm_config.enabled {
                match TariMinerClient::fetch_stats(&xtm_config.api_url).await {
                    Ok(mut stats) => {
                        stats.name = xtm_config.name.clone();
                        stats.algorithm = xtm_config.algorithm.clone();
                        stats.enabled = true;
                        stats.stratum_port = xtm_config.stratum_port;
                        stats.stratum_url = format!("stratum+tcp://YOUR_IP:{}", xtm_config.stratum_port);
                        new_stats.xtm = stats;
                    }
                    Err(e) => {
                        tracing::warn!("Failed to fetch XTM stats: {}", e);
                        new_stats.xtm = AlgorithmStats {
                            name: xtm_config.name.clone(),
                            algorithm: xtm_config.algorithm.clone(),
                            enabled: true,
                            online: false,
                            stratum_port: xtm_config.stratum_port,
                            stratum_url: format!("stratum+tcp://YOUR_IP:{}", xtm_config.stratum_port),
                            ..Default::default()
                        };
                    }
                }
            }
        }

        // Fetch XMR+XTM merge mining stats
        if let Some(ref merge_config) = state.config.pools.xmr_xtm_merge {
            if merge_config.enabled {
                // Merge mining proxy uses Tari merge client
                let api_url = merge_config.api_url.clone()
                    .unwrap_or_else(|| format!("http://127.0.0.1:{}", merge_config.stratum_port));
                match TariMergeClient::fetch_stats(&api_url).await {
                    Ok(mut stats) => {
                        stats.name = merge_config.name.clone();
                        stats.algorithm = merge_config.algorithm.clone();
                        stats.enabled = true;
                        stats.stratum_port = merge_config.stratum_port;
                        stats.stratum_url = format!("stratum+tcp://YOUR_IP:{}", merge_config.stratum_port);
                        new_stats.xmr_xtm_merge = stats;
                    }
                    Err(e) => {
                        tracing::warn!("Failed to fetch XMR+XTM merge stats: {}", e);
                        new_stats.xmr_xtm_merge = AlgorithmStats {
                            name: merge_config.name.clone(),
                            algorithm: merge_config.algorithm.clone(),
                            enabled: true,
                            online: false,
                            stratum_port: merge_config.stratum_port,
                            stratum_url: format!("stratum+tcp://YOUR_IP:{}", merge_config.stratum_port),
                            ..Default::default()
                        };
                    }
                }
            }
        }

        // Fetch ALEO stats
        if let Some(ref aleo_config) = state.config.pools.aleo {
            if aleo_config.enabled {
                match AleoPoolClient::fetch_stats(&aleo_config.api_url).await {
                    Ok(mut stats) => {
                        stats.name = aleo_config.name.clone();
                        stats.algorithm = aleo_config.algorithm.clone();
                        stats.enabled = true;
                        stats.stratum_port = aleo_config.stratum_port;
                        stats.stratum_url = format!("stratum+tcp://YOUR_IP:{}", aleo_config.stratum_port);
                        new_stats.aleo = stats;
                    }
                    Err(e) => {
                        tracing::warn!("Failed to fetch ALEO stats: {}", e);
                        new_stats.aleo = AlgorithmStats {
                            name: aleo_config.name.clone(),
                            algorithm: aleo_config.algorithm.clone(),
                            enabled: true,
                            online: false,
                            stratum_port: aleo_config.stratum_port,
                            stratum_url: format!("stratum+tcp://YOUR_IP:{}", aleo_config.stratum_port),
                            ..Default::default()
                        };
                    }
                }
            }
        }

        new_stats.last_updated = Some(Utc::now());

        // Update shared state
        let mut stats = state.stats.write().await;
        *stats = new_stats;

        tracing::debug!("Stats updated successfully");
    }
}

/// Helper function to fetch CKPool stats with proper error handling
/// Uses Unix socket API exclusively - each pool must have its own socket directory
async fn fetch_ckpool_stats(config: &crate::config::CkPoolConfig, coin: &str) -> AlgorithmStats {
    // Socket directory is required - each CKPool instance must have its own
    let Some(ref socket_dir) = config.socket_dir else {
        tracing::error!("{} pool missing socket_dir configuration", coin);
        return AlgorithmStats {
            name: config.name.clone(),
            algorithm: config.algorithm.clone(),
            enabled: true,
            online: false,
            stratum_port: config.stratum_port,
            stratum_url: format!("stratum+tcp://YOUR_IP:{}", config.stratum_port),
            ..Default::default()
        };
    };

    match CkPoolClient::fetch_stats(socket_dir).await {
        Ok(mut stats) => {
            stats.name = config.name.clone();
            stats.algorithm = config.algorithm.clone();
            stats.enabled = true;
            stats.stratum_port = config.stratum_port;
            stats.stratum_url = format!("stratum+tcp://YOUR_IP:{}", config.stratum_port);
            stats
        }
        Err(e) => {
            tracing::warn!("Failed to fetch {} stats from socket {}: {}", coin, socket_dir, e);
            AlgorithmStats {
                name: config.name.clone(),
                algorithm: config.algorithm.clone(),
                enabled: true,
                online: false,
                stratum_port: config.stratum_port,
                stratum_url: format!("stratum+tcp://YOUR_IP:{}", config.stratum_port),
                ..Default::default()
            }
        }
    }
}
