use axum::{
    body::Body,
    extract::State,
    http::{header, StatusCode, Uri},
    response::{Html, IntoResponse, Json, Response},
    routing::get,
    Router,
};
use axum_server::tls_rustls::RustlsConfig;
use rust_embed::Embed;
use std::sync::Arc;
use std::net::SocketAddr;
use std::path::Path;
use tokio::sync::RwLock;
use tower_http::{
    cors::CorsLayer,
    trace::TraceLayer,
};
use tracing_subscriber::{layer::SubscriberExt, util::SubscriberInitExt};

mod access_log;
mod api;
mod config;
mod models;

use access_log::{AccessLogLayer, AccessLogWriter};
use config::Config;
use models::{PoolStats, AppState};

/// Embedded static files (compiled into binary at build time)
#[derive(Embed)]
#[folder = "src/static"]
struct StaticAssets;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    // Load configuration first (needed for log paths)
    let config = Config::load()?;

    // Set up logging directory
    let log_dir = Path::new(&config.server.logging.log_dir);
    std::fs::create_dir_all(log_dir)?;

    // Create error log file appender
    let error_log_path = log_dir.join("error.log");
    let error_file = std::fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open(&error_log_path)?;

    // Initialize logging with both console and file output
    let file_layer = tracing_subscriber::fmt::layer()
        .with_writer(std::sync::Mutex::new(error_file))
        .with_ansi(false);

    let console_layer = tracing_subscriber::fmt::layer();

    tracing_subscriber::registry()
        .with(tracing_subscriber::EnvFilter::new(
            std::env::var("RUST_LOG").unwrap_or_else(|_| "info".into()),
        ))
        .with(console_layer)
        .with(file_layer)
        .init();

    tracing::info!("Starting Solo Pool Web UI");
    tracing::info!("Error log: {}", error_log_path.display());
    tracing::info!("Loaded configuration: {:?}", config);

    // Initialize app state
    let state = Arc::new(AppState {
        config: config.clone(),
        stats: RwLock::new(PoolStats::default()),
    });

    // Spawn background task to fetch stats
    let state_clone = state.clone();
    tokio::spawn(async move {
        api::stats_updater(state_clone).await;
    });

    // Set up access logging if enabled
    let access_log_layer = if config.server.logging.access_log_enabled {
        let access_log_path = log_dir.join("access.log");
        match AccessLogWriter::new(&access_log_path) {
            Ok(writer) => {
                tracing::info!("Access log: {}", access_log_path.display());
                Some(AccessLogLayer::new(writer))
            }
            Err(e) => {
                tracing::warn!("Failed to create access log: {}", e);
                None
            }
        }
    } else {
        None
    };

    // Build router
    let mut app = Router::new()
        // API routes
        .route("/api/stats", get(get_stats))
        .route("/api/stats/:pool", get(get_pool_stats))
        .route("/api/health", get(health_check))
        // Serve embedded static files
        .fallback(static_handler)
        .layer(CorsLayer::permissive())
        .layer(TraceLayer::new_for_http())
        .with_state(state);

    // Add access logging layer if enabled
    if let Some(layer) = access_log_layer {
        app = app.layer(layer);
    }

    let app = app;

    // Start HTTP server
    let http_addr: SocketAddr = format!("{}:{}", config.server.host, config.server.port)
        .parse()
        .expect("Invalid HTTP address");

    tracing::info!("HTTP server listening on http://{}", http_addr);

    // Check if HTTPS is enabled
    if config.server.https.enabled {
        let https_addr: SocketAddr = format!("{}:{}", config.server.host, config.server.https.port)
            .parse()
            .expect("Invalid HTTPS address");

        // Load TLS certificate and key
        let cert_path = &config.server.https.cert_path;
        let key_path = &config.server.https.key_path;

        if std::path::Path::new(cert_path).exists() && std::path::Path::new(key_path).exists() {
            let tls_config = RustlsConfig::from_pem_file(cert_path, key_path)
                .await
                .expect("Failed to load TLS certificate");

            tracing::info!("HTTPS server listening on https://{}", https_addr);

            // Run both HTTP and HTTPS servers concurrently
            let http_app = app.clone();
            let https_app = app;

            tokio::select! {
                result = axum_server::bind(http_addr).serve(http_app.into_make_service()) => {
                    if let Err(e) = result {
                        tracing::error!("HTTP server error: {}", e);
                    }
                }
                result = axum_server::bind_rustls(https_addr, tls_config).serve(https_app.into_make_service()) => {
                    if let Err(e) = result {
                        tracing::error!("HTTPS server error: {}", e);
                    }
                }
            }
        } else {
            tracing::warn!(
                "HTTPS enabled but certificate files not found: cert={}, key={}",
                cert_path, key_path
            );
            tracing::warn!("Starting HTTP-only server");

            axum_server::bind(http_addr)
                .serve(app.into_make_service())
                .await?;
        }
    } else {
        // HTTP only
        axum_server::bind(http_addr)
            .serve(app.into_make_service())
            .await?;
    }

    Ok(())
}

async fn get_stats(
    State(state): State<Arc<AppState>>,
) -> Json<PoolStats> {
    let stats = state.stats.read().await;
    Json(stats.clone())
}

async fn get_pool_stats(
    State(state): State<Arc<AppState>>,
    axum::extract::Path(pool): axum::extract::Path<String>,
) -> Result<Json<models::AlgorithmStats>, StatusCode> {
    let stats = state.stats.read().await;

    match pool.to_lowercase().as_str() {
        "btc" => Ok(Json(stats.btc.clone())),
        "bch" => Ok(Json(stats.bch.clone())),
        "dgb" => Ok(Json(stats.dgb.clone())),
        "xmr" => Ok(Json(stats.xmr.clone())),
        "xtm" => Ok(Json(stats.xtm.clone())),
        "xmr_xtm_merge" | "merge" => Ok(Json(stats.xmr_xtm_merge.clone())),
        "aleo" => Ok(Json(stats.aleo.clone())),
        _ => Err(StatusCode::NOT_FOUND),
    }
}

async fn health_check() -> &'static str {
    "OK"
}

/// Handler for embedded static files
async fn static_handler(uri: Uri) -> impl IntoResponse {
    let path = uri.path().trim_start_matches('/');

    // Default to index.html for root path
    let path = if path.is_empty() { "index.html" } else { path };

    match StaticAssets::get(path) {
        Some(content) => {
            // Determine content type from file extension
            let mime = mime_guess::from_path(path)
                .first_or_octet_stream()
                .to_string();

            Response::builder()
                .status(StatusCode::OK)
                .header(header::CONTENT_TYPE, mime)
                .body(Body::from(content.data.into_owned()))
                .unwrap()
        }
        None => {
            // Try index.html for directory-like paths (SPA fallback)
            if !path.contains('.') {
                if let Some(content) = StaticAssets::get("index.html") {
                    return Response::builder()
                        .status(StatusCode::OK)
                        .header(header::CONTENT_TYPE, "text/html")
                        .body(Body::from(content.data.into_owned()))
                        .unwrap();
                }
            }
            Response::builder()
                .status(StatusCode::NOT_FOUND)
                .body(Body::from("Not Found"))
                .unwrap()
        }
    }
}
