//! Tari Merge Mining Proxy API integration
//!
//! The Minotari merge mining proxy provides a JSON-RPC API for:
//! - Pool statistics
//! - Connected miners
//! - Block information

use super::{BlockInfo, MinerStats, PoolApi, PoolError, PoolResult, PoolStats, ShareInfo};
use async_trait::async_trait;
use rust_decimal::Decimal;
use serde::{Deserialize, Serialize};
use std::str::FromStr;

/// Tari Merge Mining Proxy API client
pub struct TariMergeProxyApi {
    api_url: String,
    client: reqwest::Client,
}

impl TariMergeProxyApi {
    /// Create a new Tari Merge Mining Proxy API client
    /// Default API is typically at http://127.0.0.1:18081
    pub fn new(api_url: &str) -> Self {
        Self {
            api_url: api_url.trim_end_matches('/').to_string(),
            client: reqwest::Client::builder()
                .timeout(std::time::Duration::from_secs(10))
                .build()
                .expect("Failed to create HTTP client"),
        }
    }

    async fn rpc_call<T: for<'de> Deserialize<'de>>(
        &self,
        method: &str,
        params: serde_json::Value,
    ) -> PoolResult<T> {
        let request = JsonRpcRequest {
            jsonrpc: "2.0".to_string(),
            id: 1,
            method: method.to_string(),
            params,
        };

        let response = self
            .client
            .post(&format!("{}/json_rpc", self.api_url))
            .json(&request)
            .send()
            .await
            .map_err(|e| PoolError::ConnectionFailed(e.to_string()))?;

        if !response.status().is_success() {
            return Err(PoolError::ApiError(format!(
                "HTTP {}: {}",
                response.status(),
                response.status().canonical_reason().unwrap_or("Unknown")
            )));
        }

        let rpc_response: JsonRpcResponse<T> = response
            .json()
            .await
            .map_err(|e| PoolError::ParseError(e.to_string()))?;

        if let Some(error) = rpc_response.error {
            return Err(PoolError::ApiError(error.message));
        }

        rpc_response
            .result
            .ok_or_else(|| PoolError::ParseError("No result in response".to_string()))
    }
}

#[async_trait]
impl PoolApi for TariMergeProxyApi {
    async fn is_online(&self) -> bool {
        self.rpc_call::<serde_json::Value>("get_status", serde_json::json!({}))
            .await
            .is_ok()
    }

    async fn get_pool_stats(&self) -> PoolResult<PoolStats> {
        let status: ProxyStatus = self
            .rpc_call("get_status", serde_json::json!({}))
            .await?;

        Ok(PoolStats {
            hashrate: status.hashrate.unwrap_or(0.0),
            hashrate_unit: "H/s".to_string(),
            miners: status.connected_miners.unwrap_or(0),
            blocks_found: status.blocks_found.unwrap_or(0),
            current_height: status.chain_height.unwrap_or(0) as i64,
            network_difficulty: Decimal::from(status.network_difficulty.unwrap_or(0)),
            last_block_time: status.last_block_time,
        })
    }

    async fn get_miner_stats(&self, wallet_address: &str) -> PoolResult<MinerStats> {
        // Query miner-specific stats if available
        let params = serde_json::json!({
            "wallet_address": wallet_address
        });

        match self
            .rpc_call::<MinerInfo>("get_miner_info", params)
            .await
        {
            Ok(info) => Ok(MinerStats {
                wallet_address: wallet_address.to_string(),
                hashrate: info.hashrate.unwrap_or(0.0),
                hashrate_unit: "H/s".to_string(),
                total_shares: info.total_shares.unwrap_or(0),
                valid_shares: info.accepted_shares.unwrap_or(0),
                invalid_shares: info.rejected_shares.unwrap_or(0),
                last_share: info.last_share_time,
            }),
            Err(_) => {
                // Return empty stats if miner not found
                Ok(MinerStats {
                    wallet_address: wallet_address.to_string(),
                    hashrate: 0.0,
                    hashrate_unit: "H/s".to_string(),
                    total_shares: 0,
                    valid_shares: 0,
                    invalid_shares: 0,
                    last_share: None,
                })
            }
        }
    }

    async fn get_all_miners(&self) -> PoolResult<Vec<MinerStats>> {
        let miners: Vec<MinerInfo> = self
            .rpc_call("get_connected_miners", serde_json::json!({}))
            .await
            .unwrap_or_default();

        Ok(miners
            .into_iter()
            .map(|m| MinerStats {
                wallet_address: m.wallet_address.unwrap_or_default(),
                hashrate: m.hashrate.unwrap_or(0.0),
                hashrate_unit: "H/s".to_string(),
                total_shares: m.total_shares.unwrap_or(0),
                valid_shares: m.accepted_shares.unwrap_or(0),
                invalid_shares: m.rejected_shares.unwrap_or(0),
                last_share: m.last_share_time,
            })
            .collect())
    }

    async fn get_shares_since(&self, since_timestamp: i64) -> PoolResult<Vec<ShareInfo>> {
        let params = serde_json::json!({
            "since": since_timestamp
        });

        let shares: Vec<ShareData> = self
            .rpc_call("get_shares", params)
            .await
            .unwrap_or_default();

        Ok(shares
            .into_iter()
            .map(|s| {
                // Parse wallet.worker format
                let (wallet, worker) = if let Some(pos) = s.username.find('.') {
                    (
                        s.username[..pos].to_string(),
                        s.username[pos + 1..].to_string(),
                    )
                } else {
                    (s.username.clone(), "default".to_string())
                };

                ShareInfo {
                    wallet_address: wallet,
                    worker_name: worker,
                    difficulty: Decimal::from_str(&s.difficulty.to_string()).unwrap_or_default(),
                    block_height: s.block_height,
                    is_block: s.is_block.unwrap_or(false),
                    timestamp: s.timestamp,
                }
            })
            .collect())
    }

    async fn get_blocks(&self, limit: u32) -> PoolResult<Vec<BlockInfo>> {
        let params = serde_json::json!({
            "limit": limit
        });

        let blocks: Vec<BlockData> = self
            .rpc_call("get_blocks", params)
            .await
            .unwrap_or_default();

        Ok(blocks
            .into_iter()
            .map(|b| {
                let (wallet, worker) = if let Some(pos) = b.miner.find('.') {
                    (b.miner[..pos].to_string(), b.miner[pos + 1..].to_string())
                } else {
                    (b.miner.clone(), "default".to_string())
                };

                BlockInfo {
                    height: b.height,
                    hash: b.hash,
                    reward: Decimal::from_str(&b.reward.to_string()).unwrap_or_default(),
                    finder_wallet: wallet,
                    finder_worker: worker,
                    timestamp: b.timestamp,
                }
            })
            .collect())
    }

    async fn get_blocks_since_height(&self, height: i64) -> PoolResult<Vec<BlockInfo>> {
        let params = serde_json::json!({
            "since_height": height
        });

        let blocks: Vec<BlockData> = self
            .rpc_call("get_blocks_since", params)
            .await
            .unwrap_or_default();

        Ok(blocks
            .into_iter()
            .map(|b| {
                let (wallet, worker) = if let Some(pos) = b.miner.find('.') {
                    (b.miner[..pos].to_string(), b.miner[pos + 1..].to_string())
                } else {
                    (b.miner.clone(), "default".to_string())
                };

                BlockInfo {
                    height: b.height,
                    hash: b.hash,
                    reward: Decimal::from_str(&b.reward.to_string()).unwrap_or_default(),
                    finder_wallet: wallet,
                    finder_worker: worker,
                    timestamp: b.timestamp,
                }
            })
            .collect())
    }
}

// JSON-RPC types

#[derive(Serialize)]
struct JsonRpcRequest {
    jsonrpc: String,
    id: u64,
    method: String,
    params: serde_json::Value,
}

#[derive(Deserialize)]
struct JsonRpcResponse<T> {
    result: Option<T>,
    error: Option<RpcError>,
}

#[derive(Deserialize)]
struct RpcError {
    message: String,
}

#[derive(Deserialize)]
struct ProxyStatus {
    hashrate: Option<f64>,
    connected_miners: Option<u32>,
    blocks_found: Option<u64>,
    chain_height: Option<u64>,
    network_difficulty: Option<u64>,
    last_block_time: Option<i64>,
}

#[derive(Deserialize)]
struct MinerInfo {
    wallet_address: Option<String>,
    hashrate: Option<f64>,
    total_shares: Option<u64>,
    accepted_shares: Option<u64>,
    rejected_shares: Option<u64>,
    last_share_time: Option<i64>,
}

#[derive(Deserialize)]
struct ShareData {
    username: String,
    difficulty: u64,
    block_height: Option<i64>,
    is_block: Option<bool>,
    timestamp: i64,
}

#[derive(Deserialize)]
struct BlockData {
    height: i64,
    hash: String,
    reward: u64,
    miner: String,
    timestamp: i64,
}
