//! Solo Pool Payment Processor
//!
//! Tracks shares and distributes rewards to miners for XMR, XTM, and ALEO pools.
//!
//! Supports multiple mining modes:
//! - monero_only: XMR via monero-pool
//! - merge: XMR + XTM via merge mining proxy
//! - tari_only: Direct solo mining (no payment processor needed for XTM)

mod api;
mod config;
mod db;
mod pools;
mod processor;
mod wallets;

use api::ApiState;
use config::{Config, PoolType};
use db::{Coin, Database};
use pools::{aleo::AleoPoolApi, minotari::MinotariMinerApi, monero_pool::MoneroPoolApi, tari::TariMergeProxyApi, PoolApi};
use processor::CoinProcessor;
use wallets::{aleo::AleoWallet, monero::MoneroWallet, tari::TariWallet, Wallet};

use std::net::SocketAddr;
use std::sync::Arc;
use tokio::signal;
use tokio::sync::broadcast;
use tokio::time::{interval, Duration};
use tracing::{error, info, Level};
use tracing_subscriber::EnvFilter;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    // Parse command line args
    let config_path = std::env::args()
        .nth(1)
        .unwrap_or_else(|| "/opt/solo-pool/payments/config.toml".to_string());

    // Load configuration
    let config = Config::load_with_env(&config_path)?;

    // Initialize logging
    let filter = EnvFilter::try_from_default_env()
        .unwrap_or_else(|_| EnvFilter::new(&config.service.log_level));

    tracing_subscriber::fmt()
        .with_env_filter(filter)
        .with_target(true)
        .init();

    info!("Starting Solo Pool Payment Processor");

    // Initialize database
    let db = Database::new(&config.database.path).await?;
    info!("Database initialized at {:?}", config.database.path);

    // Create shutdown channel
    let (shutdown_tx, _) = broadcast::channel::<()>(1);

    // Start API server
    let api_state = ApiState { db: db.clone() };
    let api_router = api::create_router(api_state);
    let api_addr: SocketAddr = format!("{}:{}", config.api.listen, config.api.port)
        .parse()
        .expect("Invalid API address");

    let api_shutdown = shutdown_tx.subscribe();
    let api_handle = tokio::spawn(async move {
        info!("API server listening on {}", api_addr);

        let listener = tokio::net::TcpListener::bind(api_addr)
            .await
            .expect("Failed to bind API server");

        axum::serve(listener, api_router)
            .with_graceful_shutdown(shutdown_signal(api_shutdown))
            .await
            .expect("API server error");
    });

    // Start coin processors
    let mut handles = vec![];

    // XMR processor
    // Uses MoneroPoolApi for monero_only mode, TariMergeProxyApi for merge mode
    if let Some(ref xmr_config) = config.xmr {
        if xmr_config.enabled {
            let share_interval = config.service.share_scan_interval_secs;
            let payment_interval = config.service.payment_interval_secs;
            let wallet = MoneroWallet::new(&xmr_config.wallet_rpc_url, xmr_config.mixin);
            let pool_api_url = xmr_config.pool_api_url.as_deref().unwrap_or("http://127.0.0.1:4243");

            match xmr_config.pool_type {
                PoolType::MoneroPool => {
                    // monero-pool API for monero_only mode
                    let processor_shutdown = shutdown_tx.subscribe();
                    let payment_shutdown = shutdown_tx.subscribe();

                    let pool_api = MoneroPoolApi::new(pool_api_url);
                    let processor = Arc::new(CoinProcessor::new(
                        Coin::Xmr,
                        pool_api,
                        wallet,
                        db.clone(),
                        xmr_config.min_payout,
                    ));

                    let proc = processor.clone();
                    handles.push(tokio::spawn(async move {
                        run_processor_loop(proc, share_interval, processor_shutdown).await;
                    }));

                    let proc = processor.clone();
                    handles.push(tokio::spawn(async move {
                        run_payment_loop(proc, payment_interval, payment_shutdown).await;
                    }));

                    info!("XMR payment processor started (monero-pool mode)");
                }
                PoolType::MergeProxy => {
                    // Merge mining proxy API for merge mode
                    let processor_shutdown = shutdown_tx.subscribe();
                    let payment_shutdown = shutdown_tx.subscribe();

                    let pool_api = TariMergeProxyApi::new(pool_api_url);
                    let processor = Arc::new(CoinProcessor::new(
                        Coin::Xmr,
                        pool_api,
                        wallet,
                        db.clone(),
                        xmr_config.min_payout,
                    ));

                    let proc = processor.clone();
                    handles.push(tokio::spawn(async move {
                        run_processor_loop(proc, share_interval, processor_shutdown).await;
                    }));

                    let proc = processor.clone();
                    handles.push(tokio::spawn(async move {
                        run_payment_loop(proc, payment_interval, payment_shutdown).await;
                    }));

                    info!("XMR payment processor started (merge mining mode)");
                }
                PoolType::MinotariMiner => {
                    // MinotariMiner is not used for XMR, log warning
                    error!("Invalid pool_type 'minotari_miner' for XMR - XMR requires 'monero_pool' or 'merge_proxy'");
                }
            }
        }
    }

    // XTM processor
    // Uses TariMergeProxyApi for merge mode, MinotariMinerApi for tari_only mode
    if let Some(ref xtm_config) = config.xtm {
        if xtm_config.enabled {
            let share_interval = config.service.share_scan_interval_secs;
            let payment_interval = config.service.payment_interval_secs;
            let wallet = TariWallet::new(&xtm_config.wallet_rpc_url);

            match xtm_config.pool_type {
                PoolType::MergeProxy => {
                    // Merge mining proxy API for merge mode
                    let processor_shutdown = shutdown_tx.subscribe();
                    let payment_shutdown = shutdown_tx.subscribe();
                    let pool_api_url = xtm_config.pool_api_url.as_deref().unwrap_or("http://127.0.0.1:18081");

                    let pool_api = TariMergeProxyApi::new(pool_api_url);
                    let processor = Arc::new(CoinProcessor::new(
                        Coin::Xtm,
                        pool_api,
                        wallet,
                        db.clone(),
                        xtm_config.min_payout,
                    ));

                    let proc = processor.clone();
                    handles.push(tokio::spawn(async move {
                        run_processor_loop(proc, share_interval, processor_shutdown).await;
                    }));

                    let proc = processor.clone();
                    handles.push(tokio::spawn(async move {
                        run_payment_loop(proc, payment_interval, payment_shutdown).await;
                    }));

                    info!("XTM payment processor started (merge mining mode)");
                }
                PoolType::MinotariMiner => {
                    // Minotari miner API for tari_only mode
                    let processor_shutdown = shutdown_tx.subscribe();
                    let payment_shutdown = shutdown_tx.subscribe();
                    let pool_api_url = xtm_config.pool_api_url.as_deref().unwrap_or("http://127.0.0.1:18084");

                    let pool_api = MinotariMinerApi::new(pool_api_url);
                    let processor = Arc::new(CoinProcessor::new(
                        Coin::Xtm,
                        pool_api,
                        wallet,
                        db.clone(),
                        xtm_config.min_payout,
                    ));

                    let proc = processor.clone();
                    handles.push(tokio::spawn(async move {
                        run_processor_loop(proc, share_interval, processor_shutdown).await;
                    }));

                    let proc = processor.clone();
                    handles.push(tokio::spawn(async move {
                        run_payment_loop(proc, payment_interval, payment_shutdown).await;
                    }));

                    info!("XTM payment processor started (tari_only mode)");
                }
                PoolType::MoneroPool => {
                    // MoneroPool is not used for XTM, log warning
                    error!("Invalid pool_type 'monero_pool' for XTM - XTM requires 'merge_proxy' or 'minotari_miner'");
                }
            }
        }
    }

    // ALEO processor
    if let Some(ref aleo_config) = config.aleo {
        if aleo_config.enabled {
            let processor_shutdown = shutdown_tx.subscribe();
            let payment_shutdown = shutdown_tx.subscribe();
            let share_interval = config.service.share_scan_interval_secs;
            let payment_interval = config.service.payment_interval_secs;

            let pool_api = AleoPoolApi::new(
                aleo_config.pool_api_url.as_deref().unwrap_or("http://127.0.0.1:4000"),
            );
            let wallet = AleoWallet::new(
                &aleo_config.node_rpc_url,
                &aleo_config.pool_wallet_address,
                &aleo_config.pool_private_key,
            );
            let processor = Arc::new(CoinProcessor::new(
                Coin::Aleo,
                pool_api,
                wallet,
                db.clone(),
                aleo_config.min_payout,
            ));

            // Share sync task
            let proc = processor.clone();
            handles.push(tokio::spawn(async move {
                run_processor_loop(proc, share_interval, processor_shutdown).await;
            }));

            // Payment task
            let proc = processor.clone();
            handles.push(tokio::spawn(async move {
                run_payment_loop(proc, payment_interval, payment_shutdown).await;
            }));

            info!("ALEO payment processor started");
        }
    }

    info!("Payment processor ready");

    // Wait for shutdown signal
    tokio::select! {
        _ = signal::ctrl_c() => {
            info!("Received Ctrl+C, shutting down...");
        }
    }

    // Send shutdown signal
    let _ = shutdown_tx.send(());

    // Wait for all tasks to complete
    for handle in handles {
        let _ = handle.await;
    }
    let _ = api_handle.await;

    info!("Payment processor shut down");
    Ok(())
}

/// Run the processor loop (share sync, block processing, reward distribution)
async fn run_processor_loop<P: PoolApi + 'static, W: Wallet + 'static>(
    processor: Arc<CoinProcessor<P, W>>,
    interval_secs: u64,
    mut shutdown: broadcast::Receiver<()>,
) {
    let mut ticker = interval(Duration::from_secs(interval_secs));

    loop {
        tokio::select! {
            _ = ticker.tick() => {
                if let Err(e) = processor.run_cycle().await {
                    error!("Processor cycle error: {}", e);
                }
            }
            _ = shutdown.recv() => {
                info!("Processor loop shutting down");
                break;
            }
        }
    }
}

/// Run the payment loop
async fn run_payment_loop<P: PoolApi + 'static, W: Wallet + 'static>(
    processor: Arc<CoinProcessor<P, W>>,
    interval_secs: u64,
    mut shutdown: broadcast::Receiver<()>,
) {
    let mut ticker = interval(Duration::from_secs(interval_secs));

    loop {
        tokio::select! {
            _ = ticker.tick() => {
                if let Err(e) = processor.run_payment_cycle().await {
                    error!("Payment cycle error: {}", e);
                }
            }
            _ = shutdown.recv() => {
                info!("Payment loop shutting down");
                break;
            }
        }
    }
}

/// Wait for shutdown signal
async fn shutdown_signal(mut shutdown: broadcast::Receiver<()>) {
    let _ = shutdown.recv().await;
}
