//! REST API for payment processor
//!
//! Endpoints:
//! - GET /api/health - Health check (no auth required)
//! - GET /api/stats - Overall payment processor stats
//! - GET /api/stats/:coin - Stats for a specific coin
//! - GET /api/miner/:coin/:address - Miner balance and history
//! - GET /api/payments/:coin - Recent payments for a coin
//! - GET /api/payments/:coin/:address - Payment history for a miner

use crate::db::{Coin, Database, MinerBalance, Payment};
use axum::{
    body::Body,
    extract::{Path, Query, State},
    http::{Request, StatusCode},
    middleware::{self, Next},
    response::{IntoResponse, Response},
    routing::get,
    Json, Router,
};
use serde::{Deserialize, Serialize};
use std::sync::Arc;

/// Shared state for API handlers
#[derive(Clone)]
pub struct ApiState {
    pub db: Database,
    pub api_token: String,
}

/// Create the API router
pub fn create_router(state: ApiState) -> Router {
    let api_token = state.api_token.clone();

    Router::new()
        .route("/api/health", get(health_check))
        .route("/api/stats", get(get_all_stats))
        .route("/api/stats/:coin", get(get_coin_stats))
        .route("/api/miner/:coin/:address", get(get_miner_info))
        .route("/api/payments/:coin", get(get_coin_payments))
        .route("/api/payments/:coin/:address", get(get_miner_payments))
        .layer(middleware::from_fn(move |req: Request<Body>, next: Next| {
            let token = api_token.clone();
            async move { require_auth(token, req, next).await }
        }))
        .with_state(Arc::new(state))
}

/// Authentication middleware
async fn require_auth(
    api_token: String,
    request: Request<Body>,
    next: Next,
) -> Response {
    // Skip auth if token is not configured
    if api_token.is_empty() {
        return next.run(request).await;
    }

    let path = request.uri().path();

    // Allow health check without auth
    if path == "/api/health" {
        return next.run(request).await;
    }

    // Check for valid Authorization header
    if let Some(auth_header) = request.headers().get("Authorization") {
        if let Ok(auth_str) = auth_header.to_str() {
            if auth_str.starts_with("Bearer ") {
                let token = &auth_str[7..];
                if token == api_token {
                    return next.run(request).await;
                }
            }
        }
    }

    // Not authenticated
    (StatusCode::UNAUTHORIZED, "Invalid or missing API token").into_response()
}

/// Health check endpoint
async fn health_check() -> impl IntoResponse {
    Json(serde_json::json!({
        "status": "ok",
        "service": "solo-pool-payments"
    }))
}

/// Overall stats response
#[derive(Serialize)]
struct AllStatsResponse {
    xmr: Option<CoinStatsResponse>,
    xtm: Option<CoinStatsResponse>,
    aleo: Option<CoinStatsResponse>,
}

/// Stats for a single coin
#[derive(Serialize)]
struct CoinStatsResponse {
    coin: String,
    total_miners: u32,
    total_pending: String,
    total_paid: String,
    pending_payments: u32,
}

/// Get stats for all coins
async fn get_all_stats(
    State(state): State<Arc<ApiState>>,
) -> Result<Json<AllStatsResponse>, (StatusCode, String)> {
    let xmr = get_coin_stats_internal(&state.db, Coin::Xmr).await.ok();
    let xtm = get_coin_stats_internal(&state.db, Coin::Xtm).await.ok();
    let aleo = get_coin_stats_internal(&state.db, Coin::Aleo).await.ok();

    Ok(Json(AllStatsResponse { xmr, xtm, aleo }))
}

/// Get stats for a specific coin
async fn get_coin_stats(
    State(state): State<Arc<ApiState>>,
    Path(coin): Path<String>,
) -> Result<Json<CoinStatsResponse>, (StatusCode, String)> {
    let coin: Coin = coin
        .parse()
        .map_err(|_| (StatusCode::BAD_REQUEST, "Invalid coin".to_string()))?;

    let stats = get_coin_stats_internal(&state.db, coin)
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;

    Ok(Json(stats))
}

async fn get_coin_stats_internal(db: &Database, coin: Coin) -> anyhow::Result<CoinStatsResponse> {
    // Get payable balances (min = 0 to get all)
    let balances = db
        .get_payable_balances(coin, rust_decimal::Decimal::from(0))
        .await?;

    let total_pending: rust_decimal::Decimal = balances.iter().map(|b| b.pending_balance).sum();
    let total_paid: rust_decimal::Decimal = balances.iter().map(|b| b.total_paid).sum();

    let pending_payments = db.get_pending_payments(coin).await?.len();

    Ok(CoinStatsResponse {
        coin: coin.to_string(),
        total_miners: balances.len() as u32,
        total_pending: total_pending.to_string(),
        total_paid: total_paid.to_string(),
        pending_payments: pending_payments as u32,
    })
}

/// Miner info response
#[derive(Serialize)]
struct MinerInfoResponse {
    wallet_address: String,
    coin: String,
    pending_balance: String,
    total_paid: String,
    total_shares: i64,
    last_share: Option<String>,
    last_payment: Option<String>,
    recent_payments: Vec<PaymentResponse>,
}

/// Get miner info
async fn get_miner_info(
    State(state): State<Arc<ApiState>>,
    Path((coin, address)): Path<(String, String)>,
) -> Result<Json<MinerInfoResponse>, (StatusCode, String)> {
    let coin: Coin = coin
        .parse()
        .map_err(|_| (StatusCode::BAD_REQUEST, "Invalid coin".to_string()))?;

    let balance = state
        .db
        .get_miner_balance(coin, &address)
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?
        .unwrap_or(MinerBalance {
            wallet_address: address.clone(),
            coin,
            pending_balance: rust_decimal::Decimal::from(0),
            total_paid: rust_decimal::Decimal::from(0),
            total_shares: 0,
            last_share: None,
            last_payment: None,
        });

    let payments = state
        .db
        .get_miner_payments(coin, &address, 10)
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;

    Ok(Json(MinerInfoResponse {
        wallet_address: balance.wallet_address,
        coin: coin.to_string(),
        pending_balance: balance.pending_balance.to_string(),
        total_paid: balance.total_paid.to_string(),
        total_shares: balance.total_shares,
        last_share: balance.last_share.map(|d| d.to_rfc3339()),
        last_payment: balance.last_payment.map(|d| d.to_rfc3339()),
        recent_payments: payments.into_iter().map(PaymentResponse::from).collect(),
    }))
}

/// Payment response
#[derive(Serialize)]
struct PaymentResponse {
    id: String,
    coin: String,
    wallet_address: String,
    amount: String,
    tx_hash: Option<String>,
    status: String,
    created_at: String,
    confirmed_at: Option<String>,
}

impl From<Payment> for PaymentResponse {
    fn from(p: Payment) -> Self {
        Self {
            id: p.id,
            coin: p.coin.to_string(),
            wallet_address: p.wallet_address,
            amount: p.amount.to_string(),
            tx_hash: p.tx_hash,
            status: format!("{:?}", p.status).to_lowercase(),
            created_at: p.created_at.to_rfc3339(),
            confirmed_at: p.confirmed_at.map(|d| d.to_rfc3339()),
        }
    }
}

/// Query params for payments list
#[derive(Deserialize)]
struct PaymentsQuery {
    #[serde(default = "default_limit")]
    limit: i32,
}

fn default_limit() -> i32 {
    50
}

/// Get recent payments for a coin
async fn get_coin_payments(
    State(state): State<Arc<ApiState>>,
    Path(coin): Path<String>,
    Query(query): Query<PaymentsQuery>,
) -> Result<Json<Vec<PaymentResponse>>, (StatusCode, String)> {
    let coin: Coin = coin
        .parse()
        .map_err(|_| (StatusCode::BAD_REQUEST, "Invalid coin".to_string()))?;

    // Get pending payments (for all addresses)
    let payments = state
        .db
        .get_pending_payments(coin)
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;

    Ok(Json(
        payments
            .into_iter()
            .take(query.limit as usize)
            .map(PaymentResponse::from)
            .collect(),
    ))
}

/// Get payment history for a miner
async fn get_miner_payments(
    State(state): State<Arc<ApiState>>,
    Path((coin, address)): Path<(String, String)>,
    Query(query): Query<PaymentsQuery>,
) -> Result<Json<Vec<PaymentResponse>>, (StatusCode, String)> {
    let coin: Coin = coin
        .parse()
        .map_err(|_| (StatusCode::BAD_REQUEST, "Invalid coin".to_string()))?;

    let payments = state
        .db
        .get_miner_payments(coin, &address, query.limit)
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;

    Ok(Json(
        payments.into_iter().map(PaymentResponse::from).collect(),
    ))
}
