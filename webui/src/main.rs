use axum::{
    body::Body,
    extract::{Query, State},
    http::{header, Request, StatusCode, Uri},
    middleware::{self, Next},
    response::{IntoResponse, Json, Redirect, Response},
    routing::{delete, get, post},
    Router,
};
use axum_server::tls_rustls::RustlsConfig;
use rust_embed::Embed;
use serde::{Deserialize, Serialize};
use std::net::SocketAddr;
use std::path::Path;
use std::sync::Arc;
use tokio::sync::RwLock;
use tower_cookies::{Cookie, CookieManagerLayer, Cookies};
use tower_http::{cors::CorsLayer, trace::TraceLayer};
use tracing_subscriber::{layer::SubscriberExt, util::SubscriberInitExt};

mod access_log;
mod api;
mod auth;
mod config;
mod db;
mod models;

use access_log::{AccessLogLayer, AccessLogWriter};
use auth::AuthState;
use config::Config;
use db::Database;
use models::{detect_server_ip, AppState, PoolStats};

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

    // Initialize authentication
    let auth_state = match AuthState::new(&config.auth) {
        Ok(auth) => {
            if config.auth.enabled {
                tracing::info!(
                    "Authentication enabled, credentials loaded from {}",
                    config.auth.credentials_file
                );
            } else {
                tracing::warn!("Authentication is DISABLED");
            }
            Arc::new(auth)
        }
        Err(e) => {
            if config.auth.enabled {
                tracing::error!("Failed to load credentials: {}", e);
                tracing::error!(
                    "Create credentials file at {} with SOLO_POOL_WEBUI_USER and SOLO_POOL_WEBUI_PASS",
                    config.auth.credentials_file
                );
                return Err(e);
            } else {
                tracing::warn!("Authentication disabled, skipping credential load");
                Arc::new(AuthState::new(&config::AuthConfig {
                    enabled: false,
                    ..Default::default()
                })?)
            }
        }
    };

    // Detect server IP for stratum URLs
    tracing::info!("Detecting server IP...");
    let server_ip = detect_server_ip().await;
    tracing::info!("Server IP detected: {}", server_ip);

    // Initialize database
    let db_dir = Path::new(&config.server.db_dir);
    std::fs::create_dir_all(db_dir)?;
    let db_path = db_dir.join("stats.db");
    tracing::info!("Database path: {}", db_path.display());

    let db = Database::new(&db_path)?;
    tracing::info!("Database initialized with WAL mode");

    // Initialize app state
    let app_state = Arc::new(AppState {
        config: config.clone(),
        stats: RwLock::new(PoolStats::default()),
        server_ip,
        db: Arc::new(db),
    });

    // Spawn background task to fetch stats
    let state_clone = app_state.clone();
    tokio::spawn(async move {
        api::stats_updater(state_clone).await;
    });

    // Spawn session cleanup task
    let auth_clone = auth_state.clone();
    tokio::spawn(async move {
        loop {
            tokio::time::sleep(tokio::time::Duration::from_secs(300)).await;
            auth_clone.sessions.cleanup().await;
        }
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

    // Build router with authentication
    let auth_state_for_middleware = auth_state.clone();
    let cookie_name = config.auth.cookie_name.clone();
    let auth_enabled = config.auth.enabled;

    let mut app = Router::new()
        // Auth routes (always accessible)
        .route("/api/auth/login", post(login))
        .route("/api/auth/logout", post(logout))
        .route("/api/auth/check", get(check_auth))
        // API routes
        .route("/api/stats", get(get_stats))
        .route("/api/stats/:pool", get(get_pool_stats))
        .route("/api/workers/:pool/:worker", delete(delete_worker))
        .route("/api/health", get(health_check))
        // Payment processor proxy routes
        .route("/api/payments/stats", get(proxy_payments_stats))
        .route("/api/payments/stats/:coin", get(proxy_payments_coin_stats))
        .route("/api/payments/coin/:coin", get(proxy_payments_list))
        .route("/api/payments/miner/:coin/:address", get(proxy_payments_miner))
        // Login page (needs special handling)
        .route("/login", get(login_page))
        // Serve embedded static files
        .fallback(static_handler)
        // Authentication middleware
        .layer(middleware::from_fn(move |cookies: Cookies, request: Request<Body>, next: Next| {
            let auth = auth_state_for_middleware.clone();
            let cookie_name = cookie_name.clone();
            async move {
                require_auth(auth, cookies, cookie_name, auth_enabled, request, next).await
            }
        }))
        .layer(CookieManagerLayer::new())
        .layer(CorsLayer::permissive())
        .layer(TraceLayer::new_for_http())
        .with_state((app_state, auth_state));

    // Add access logging layer if enabled
    if let Some(layer) = access_log_layer {
        app = app.layer(layer);
    }

    let app = app;

    // Start HTTP server
    let http_addr: SocketAddr = format!("{}:{}", config.server.host, config.server.port)
        .parse()
        .map_err(|e| {
            anyhow::anyhow!(
                "Invalid HTTP address '{}:{}': {}",
                config.server.host,
                config.server.port,
                e
            )
        })?;

    tracing::info!("HTTP server listening on http://{}", http_addr);

    // Check if HTTPS is enabled
    if config.server.https.enabled {
        let https_addr: SocketAddr =
            format!("{}:{}", config.server.host, config.server.https.port)
                .parse()
                .map_err(|e| {
                    anyhow::anyhow!(
                        "Invalid HTTPS address '{}:{}': {}",
                        config.server.host,
                        config.server.https.port,
                        e
                    )
                })?;

        // Load TLS certificate and key
        let cert_path = &config.server.https.cert_path;
        let key_path = &config.server.https.key_path;

        if std::path::Path::new(cert_path).exists() && std::path::Path::new(key_path).exists() {
            let tls_config = RustlsConfig::from_pem_file(cert_path, key_path)
                .await
                .map_err(|e| {
                    anyhow::anyhow!(
                        "Failed to load TLS certificate from '{}' and '{}': {}",
                        cert_path,
                        key_path,
                        e
                    )
                })?;

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
                cert_path,
                key_path
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

/// Authentication middleware
async fn require_auth(
    auth: Arc<AuthState>,
    cookies: Cookies,
    cookie_name: String,
    auth_enabled: bool,
    request: Request<Body>,
    next: Next,
) -> Response {
    // Skip auth if disabled
    if !auth_enabled {
        return next.run(request).await;
    }

    let path = request.uri().path();

    // Allow login page and auth endpoints
    if path == "/login"
        || path == "/login.html"
        || path.starts_with("/api/auth/")
        || path == "/css/style.css"
        || path == "/css/login.css"
        || path == "/api/health"
    {
        return next.run(request).await;
    }

    // Check for valid session
    if let Some(session_cookie) = cookies.get(&cookie_name) {
        if auth.sessions.validate(session_cookie.value()).await.is_some() {
            return next.run(request).await;
        }
    }

    // Not authenticated - redirect to login or return 401 for API
    if path.starts_with("/api/") {
        return (StatusCode::UNAUTHORIZED, "Authentication required").into_response();
    }

    Redirect::to("/login").into_response()
}

#[derive(Deserialize)]
struct LoginRequest {
    username: String,
    password: String,
}

#[derive(Serialize)]
struct LoginResponse {
    success: bool,
    username: Option<String>,
    error: Option<String>,
}

#[derive(Serialize)]
struct AuthCheckResponse {
    authenticated: bool,
    username: Option<String>,
}

/// Login endpoint
async fn login(
    State((_, auth)): State<(Arc<AppState>, Arc<AuthState>)>,
    cookies: Cookies,
    Json(req): Json<LoginRequest>,
) -> Json<LoginResponse> {
    if auth.verify(&req.username, &req.password) {
        let session_id = auth.sessions.create(req.username.clone()).await;

        // Set session cookie
        let cookie = Cookie::build((auth.cookie_name.clone(), session_id))
            .path("/")
            .http_only(true)
            .same_site(tower_cookies::cookie::SameSite::Lax)
            .build();

        cookies.add(cookie);

        tracing::info!("User '{}' logged in successfully", req.username);

        Json(LoginResponse {
            success: true,
            username: Some(req.username),
            error: None,
        })
    } else {
        tracing::warn!("Failed login attempt for user '{}'", req.username);

        Json(LoginResponse {
            success: false,
            username: None,
            error: Some("Invalid username or password".to_string()),
        })
    }
}

/// Logout endpoint
async fn logout(
    State((_, auth)): State<(Arc<AppState>, Arc<AuthState>)>,
    cookies: Cookies,
) -> Json<serde_json::Value> {
    if let Some(session_cookie) = cookies.get(&auth.cookie_name) {
        auth.sessions.remove(session_cookie.value()).await;
    }

    // Remove session cookie
    cookies.remove(Cookie::from(auth.cookie_name.clone()));

    Json(serde_json::json!({ "success": true }))
}

/// Check authentication status
async fn check_auth(
    State((_, auth)): State<(Arc<AppState>, Arc<AuthState>)>,
    cookies: Cookies,
) -> Json<AuthCheckResponse> {
    if !auth.enabled {
        return Json(AuthCheckResponse {
            authenticated: true,
            username: Some("admin".to_string()),
        });
    }

    if let Some(session_cookie) = cookies.get(&auth.cookie_name) {
        if let Some(username) = auth.sessions.validate(session_cookie.value()).await {
            return Json(AuthCheckResponse {
                authenticated: true,
                username: Some(username),
            });
        }
    }

    Json(AuthCheckResponse {
        authenticated: false,
        username: None,
    })
}

/// Serve login page
async fn login_page() -> impl IntoResponse {
    match StaticAssets::get("login.html") {
        Some(content) => Response::builder()
            .status(StatusCode::OK)
            .header(header::CONTENT_TYPE, "text/html")
            .body(Body::from(content.data.into_owned()))
            .unwrap(),
        None => Response::builder()
            .status(StatusCode::INTERNAL_SERVER_ERROR)
            .body(Body::from("Login page not found"))
            .unwrap(),
    }
}

async fn get_stats(State((state, _)): State<(Arc<AppState>, Arc<AuthState>)>) -> Json<PoolStats> {
    let stats = state.stats.read().await;
    Json(stats.clone())
}

async fn get_pool_stats(
    State((state, _)): State<(Arc<AppState>, Arc<AuthState>)>,
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

/// Delete a worker from the database
async fn delete_worker(
    State((state, _)): State<(Arc<AppState>, Arc<AuthState>)>,
    axum::extract::Path((pool, worker)): axum::extract::Path<(String, String)>,
) -> Result<Json<serde_json::Value>, StatusCode> {
    // URL decode the worker name (it may contain special characters)
    let worker_name = urlencoding::decode(&worker)
        .map(|s| s.into_owned())
        .unwrap_or(worker);

    tracing::info!(
        "Delete request for worker '{}' in pool '{}'",
        worker_name,
        pool
    );

    match state.db.delete_worker(&pool, &worker_name) {
        Ok(deleted) => {
            if deleted {
                tracing::info!("Worker '{}' deleted from pool '{}'", worker_name, pool);
                Ok(Json(serde_json::json!({
                    "success": true,
                    "message": format!("Worker '{}' deleted from pool '{}'", worker_name, pool)
                })))
            } else {
                tracing::warn!("Worker '{}' not found in pool '{}'", worker_name, pool);
                Err(StatusCode::NOT_FOUND)
            }
        }
        Err(e) => {
            tracing::error!("Failed to delete worker '{}': {}", worker_name, e);
            Err(StatusCode::INTERNAL_SERVER_ERROR)
        }
    }
}

// =============================================================================
// Payment Processor Proxy Routes
// =============================================================================

/// Proxy request to payment processor API
async fn proxy_to_payments(
    state: &AppState,
    path: &str,
) -> Result<Response, (StatusCode, String)> {
    let url = format!("{}{}", state.config.server.payments_api_url, path);

    let client = reqwest::Client::new();
    let mut request = client.get(&url).timeout(std::time::Duration::from_secs(5));

    // Add API token if configured
    if !state.config.server.payments_api_token.is_empty() {
        request = request.header("Authorization", format!("Bearer {}", state.config.server.payments_api_token));
    }

    match request.send().await {
        Ok(response) => {
            let status = StatusCode::from_u16(response.status().as_u16())
                .unwrap_or(StatusCode::INTERNAL_SERVER_ERROR);

            match response.text().await {
                Ok(body) => {
                    Response::builder()
                        .status(status)
                        .header(header::CONTENT_TYPE, "application/json")
                        .body(Body::from(body))
                        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))
                }
                Err(e) => Err((StatusCode::INTERNAL_SERVER_ERROR, e.to_string())),
            }
        }
        Err(e) => {
            if e.is_connect() {
                Err((StatusCode::SERVICE_UNAVAILABLE, "Payment processor not available".to_string()))
            } else {
                Err((StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))
            }
        }
    }
}

/// Proxy payment stats
async fn proxy_payments_stats(
    State((state, _)): State<(Arc<AppState>, Arc<AuthState>)>,
) -> Result<Response, (StatusCode, String)> {
    proxy_to_payments(&state, "/api/stats").await
}

/// Proxy payment stats for specific coin
async fn proxy_payments_coin_stats(
    State((state, _)): State<(Arc<AppState>, Arc<AuthState>)>,
    axum::extract::Path(coin): axum::extract::Path<String>,
) -> Result<Response, (StatusCode, String)> {
    proxy_to_payments(&state, &format!("/api/stats/{}", coin)).await
}

/// Proxy payment list for a coin
async fn proxy_payments_list(
    State((state, _)): State<(Arc<AppState>, Arc<AuthState>)>,
    axum::extract::Path(coin): axum::extract::Path<String>,
    Query(params): Query<std::collections::HashMap<String, String>>,
) -> Result<Response, (StatusCode, String)> {
    let query = if params.is_empty() {
        String::new()
    } else {
        format!("?{}", params.iter().map(|(k, v)| format!("{}={}", k, v)).collect::<Vec<_>>().join("&"))
    };
    proxy_to_payments(&state, &format!("/api/payments/{}{}", coin, query)).await
}

/// Proxy miner info
async fn proxy_payments_miner(
    State((state, _)): State<(Arc<AppState>, Arc<AuthState>)>,
    axum::extract::Path((coin, address)): axum::extract::Path<(String, String)>,
) -> Result<Response, (StatusCode, String)> {
    proxy_to_payments(&state, &format!("/api/miner/{}/{}", coin, urlencoding::encode(&address))).await
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
