mod ckpool;
mod aleo;
mod monero_pool;
mod tari;

use std::sync::Arc;
use chrono::Utc;
use tokio::time::{interval, Duration};

use crate::models::{AppState, PoolStats, AlgorithmStats};

pub use ckpool::CkPoolClient;
pub use aleo::AleoPoolClient;
pub use monero_pool::MoneroPoolClient;
pub use tari::{TariMergeClient, TariMinerClient};

/// Background task to periodically update pool statistics
pub async fn stats_updater(state: Arc<AppState>) {
    let refresh_secs = state.config.server.refresh_interval_secs;
    let mut interval = interval(Duration::from_secs(refresh_secs));
    let server_ip = &state.server_ip;

    tracing::info!("Stats updater started (refresh every {}s)", refresh_secs);

    loop {
        interval.tick().await;

        let mut new_stats = PoolStats::default();

        // Fetch BTC stats (CKPool)
        if let Some(ref btc_config) = state.config.pools.btc {
            if btc_config.enabled {
                new_stats.btc = fetch_ckpool_stats(btc_config, "BTC", server_ip).await;
            }
        }

        // Fetch BCH stats (CKPool)
        if let Some(ref bch_config) = state.config.pools.bch {
            if bch_config.enabled {
                new_stats.bch = fetch_ckpool_stats(bch_config, "BCH", server_ip).await;
            }
        }

        // Fetch DGB stats (CKPool)
        if let Some(ref dgb_config) = state.config.pools.dgb {
            if dgb_config.enabled {
                new_stats.dgb = fetch_ckpool_stats(dgb_config, "DGB", server_ip).await;
            }
        }

        // Fetch XMR stats (monero-pool - monero_only mode)
        if let Some(ref xmr_config) = state.config.pools.xmr {
            if xmr_config.enabled {
                match MoneroPoolClient::fetch_stats(&xmr_config.api_url).await {
                    Ok(mut stats) => {
                        stats.name = xmr_config.name.clone();
                        stats.algorithm = xmr_config.algorithm.clone();
                        stats.enabled = true;
                        stats.stratum_port = xmr_config.stratum_port;
                        stats.stratum_url = format!("stratum+tcp://{}:{}", server_ip, xmr_config.stratum_port);
                        stats.username_format = xmr_config.username_format.clone();
                        stats.password = xmr_config.password.clone();
                        stats.pool_wallet_address = xmr_config.pool_wallet_address.clone();
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
                            stratum_url: format!("stratum+tcp://{}:{}", server_ip, xmr_config.stratum_port),
                            username_format: xmr_config.username_format.clone(),
                            password: xmr_config.password.clone(),
                            pool_wallet_address: xmr_config.pool_wallet_address.clone(),
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
                        stats.stratum_url = format!("stratum+tcp://{}:{}", server_ip, xtm_config.stratum_port);
                        stats.username_format = xtm_config.username_format.clone();
                        stats.password = xtm_config.password.clone();
                        stats.pool_wallet_address = xtm_config.pool_wallet_address.clone();
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
                            stratum_url: format!("stratum+tcp://{}:{}", server_ip, xtm_config.stratum_port),
                            username_format: xtm_config.username_format.clone(),
                            password: xtm_config.password.clone(),
                            pool_wallet_address: xtm_config.pool_wallet_address.clone(),
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
                        stats.stratum_url = format!("stratum+tcp://{}:{}", server_ip, merge_config.stratum_port);
                        stats.username_format = merge_config.username_format.clone();
                        stats.password = merge_config.password.clone();
                        stats.pool_wallet_address = merge_config.xmr_pool_wallet_address.clone();
                        stats.pool_wallet_address_secondary = merge_config.xtm_pool_wallet_address.clone();
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
                            stratum_url: format!("stratum+tcp://{}:{}", server_ip, merge_config.stratum_port),
                            username_format: merge_config.username_format.clone(),
                            password: merge_config.password.clone(),
                            pool_wallet_address: merge_config.xmr_pool_wallet_address.clone(),
                            pool_wallet_address_secondary: merge_config.xtm_pool_wallet_address.clone(),
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
                        stats.stratum_url = format!("stratum+tcp://{}:{}", server_ip, aleo_config.stratum_port);
                        stats.username_format = aleo_config.username_format.clone();
                        stats.password = aleo_config.password.clone();
                        stats.pool_wallet_address = aleo_config.pool_wallet_address.clone();
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
                            stratum_url: format!("stratum+tcp://{}:{}", server_ip, aleo_config.stratum_port),
                            username_format: aleo_config.username_format.clone(),
                            password: aleo_config.password.clone(),
                            pool_wallet_address: aleo_config.pool_wallet_address.clone(),
                            ..Default::default()
                        };
                    }
                }
            }
        }

        new_stats.last_updated = Some(Utc::now());

        // All pools are fee-free (0% pool fee)
        new_stats.btc.pool_fee_percent = 0.0;
        new_stats.bch.pool_fee_percent = 0.0;
        new_stats.dgb.pool_fee_percent = 0.0;
        new_stats.xmr.pool_fee_percent = 0.0;
        new_stats.xtm.pool_fee_percent = 0.0;
        new_stats.xmr_xtm_merge.pool_fee_percent = 0.0;
        new_stats.aleo.pool_fee_percent = 0.0;

        // Store worker stats to database for persistence
        store_workers_to_db(&state.db, &new_stats).await;

        // Update shared state
        let mut stats = state.stats.write().await;
        *stats = new_stats;

        tracing::debug!("Stats updated successfully");
    }
}

/// Store worker stats to database for persistence
async fn store_workers_to_db(db: &Arc<crate::db::Database>, stats: &PoolStats) {
    let pools = [
        ("btc", &stats.btc),
        ("bch", &stats.bch),
        ("dgb", &stats.dgb),
        ("xmr", &stats.xmr),
        ("xtm", &stats.xtm),
        ("xmr_xtm_merge", &stats.xmr_xtm_merge),
        ("aleo", &stats.aleo),
    ];

    for (pool_id, pool_stats) in pools {
        if !pool_stats.enabled {
            continue;
        }

        // Collect online worker names for this pool
        let online_workers: Vec<String> = pool_stats.workers.iter()
            .filter(|w| w.is_online)
            .map(|w| w.name.clone())
            .collect();

        // Upsert each worker
        for worker in &pool_stats.workers {
            if let Err(e) = db.upsert_worker(
                pool_id,
                &worker.name,
                &worker.wallet_address,
                worker.hashrate,
                &worker.hashrate_unit,
                worker.shares_accepted,
                worker.shares_rejected,
                worker.blocks_found,
                worker.is_online,
            ) {
                tracing::warn!("Failed to upsert worker {} in {}: {}", worker.name, pool_id, e);
            }
        }

        // Mark workers as offline if they're no longer reported
        if let Err(e) = db.mark_workers_offline(pool_id, &online_workers) {
            tracing::warn!("Failed to mark offline workers in {}: {}", pool_id, e);
        }

        // Update pool aggregate stats
        if let Err(e) = db.update_pool_stats(
            pool_id,
            pool_stats.total_hashrate,
            &pool_stats.hashrate_unit,
            pool_stats.blocks_found,
        ) {
            tracing::warn!("Failed to update pool stats for {}: {}", pool_id, e);
        }
    }
}

/// Helper function to fetch CKPool stats with proper error handling
/// Uses Unix socket API exclusively - each pool must have its own socket directory
async fn fetch_ckpool_stats(config: &crate::config::CkPoolConfig, coin: &str, server_ip: &str) -> AlgorithmStats {
    // Socket directory is required - each CKPool instance must have its own
    let Some(ref socket_dir) = config.socket_dir else {
        tracing::error!("{} pool missing socket_dir configuration", coin);
        return AlgorithmStats {
            name: config.name.clone(),
            algorithm: config.algorithm.clone(),
            enabled: true,
            online: false,
            stratum_port: config.stratum_port,
            stratum_url: format!("stratum+tcp://{}:{}", server_ip, config.stratum_port),
            username_format: config.username_format.clone(),
            password: config.password.clone(),
            ..Default::default()
        };
    };

    match CkPoolClient::fetch_stats(socket_dir).await {
        Ok(mut stats) => {
            stats.name = config.name.clone();
            stats.algorithm = config.algorithm.clone();
            stats.enabled = true;
            stats.stratum_port = config.stratum_port;
            stats.stratum_url = format!("stratum+tcp://{}:{}", server_ip, config.stratum_port);
            stats.username_format = config.username_format.clone();
            stats.password = config.password.clone();
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
                stratum_url: format!("stratum+tcp://{}:{}", server_ip, config.stratum_port),
                username_format: config.username_format.clone(),
                password: config.password.clone(),
                ..Default::default()
            }
        }
    }
}
