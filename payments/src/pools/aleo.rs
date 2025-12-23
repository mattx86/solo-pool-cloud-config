//! ALEO Pool Server API integration
//!
//! The aleo-pool-server provides a REST API for:
//! - Pool statistics
//! - Miner statistics
//! - Share and block information

use super::{BlockInfo, MinerStats, PoolApi, PoolError, PoolResult, PoolStats, ShareInfo};
use async_trait::async_trait;
use rust_decimal::Decimal;
use serde::Deserialize;
use std::str::FromStr;

/// ALEO Pool Server API client
pub struct AleoPoolApi {
    api_url: String,
    client: reqwest::Client,
}

impl AleoPoolApi {
    /// Create a new ALEO Pool Server API client
    pub fn new(api_url: &str) -> Self {
        Self {
            api_url: api_url.trim_end_matches('/').to_string(),
            client: reqwest::Client::builder()
                .timeout(std::time::Duration::from_secs(10))
                .build()
                .expect("Failed to create HTTP client"),
        }
    }

    async fn get<T: for<'de> Deserialize<'de>>(&self, path: &str) -> PoolResult<T> {
        let url = format!("{}{}", self.api_url, path);

        let response = self
            .client
            .get(&url)
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

        response
            .json()
            .await
            .map_err(|e| PoolError::ParseError(e.to_string()))
    }
}

#[async_trait]
impl PoolApi for AleoPoolApi {
    async fn is_online(&self) -> bool {
        self.get::<serde_json::Value>("/api/stats").await.is_ok()
    }

    async fn get_pool_stats(&self) -> PoolResult<PoolStats> {
        let stats: AleoPoolStats = self.get("/api/stats").await?;

        Ok(PoolStats {
            hashrate: stats.pool_hashrate.unwrap_or(0.0),
            hashrate_unit: "c/s".to_string(), // ALEO uses proof rate, not hashrate
            miners: stats.connected_miners.unwrap_or(0),
            blocks_found: stats.blocks_found.unwrap_or(0),
            current_height: stats.current_height.unwrap_or(0) as i64,
            network_difficulty: Decimal::from_str(&stats.difficulty.unwrap_or_default())
                .unwrap_or_default(),
            last_block_time: stats.last_block_time,
        })
    }

    async fn get_miner_stats(&self, wallet_address: &str) -> PoolResult<MinerStats> {
        let path = format!("/api/miner/{}", wallet_address);

        match self.get::<AleoMinerStats>(&path).await {
            Ok(stats) => Ok(MinerStats {
                wallet_address: wallet_address.to_string(),
                hashrate: stats.hashrate.unwrap_or(0.0),
                hashrate_unit: "c/s".to_string(),
                total_shares: stats.total_proofs.unwrap_or(0),
                valid_shares: stats.valid_proofs.unwrap_or(0),
                invalid_shares: stats.invalid_proofs.unwrap_or(0),
                last_share: stats.last_proof_time,
            }),
            Err(_) => Ok(MinerStats {
                wallet_address: wallet_address.to_string(),
                hashrate: 0.0,
                hashrate_unit: "c/s".to_string(),
                total_shares: 0,
                valid_shares: 0,
                invalid_shares: 0,
                last_share: None,
            }),
        }
    }

    async fn get_all_miners(&self) -> PoolResult<Vec<MinerStats>> {
        let miners: Vec<AleoMinerStats> = self.get("/api/miners").await.unwrap_or_default();

        Ok(miners
            .into_iter()
            .map(|m| MinerStats {
                wallet_address: m.address.unwrap_or_default(),
                hashrate: m.hashrate.unwrap_or(0.0),
                hashrate_unit: "c/s".to_string(),
                total_shares: m.total_proofs.unwrap_or(0),
                valid_shares: m.valid_proofs.unwrap_or(0),
                invalid_shares: m.invalid_proofs.unwrap_or(0),
                last_share: m.last_proof_time,
            })
            .collect())
    }

    async fn get_shares_since(&self, since_timestamp: i64) -> PoolResult<Vec<ShareInfo>> {
        let path = format!("/api/proofs?since={}", since_timestamp);

        let proofs: Vec<AleoProof> = self.get(&path).await.unwrap_or_default();

        Ok(proofs
            .into_iter()
            .map(|p| {
                // Parse address.worker format if present
                let (wallet, worker) = if let Some(pos) = p.miner.find('.') {
                    (p.miner[..pos].to_string(), p.miner[pos + 1..].to_string())
                } else {
                    (p.miner.clone(), "default".to_string())
                };

                ShareInfo {
                    wallet_address: wallet,
                    worker_name: worker,
                    difficulty: Decimal::from(p.target.unwrap_or(1)),
                    block_height: p.height,
                    is_block: p.is_coinbase.unwrap_or(false),
                    timestamp: p.timestamp,
                }
            })
            .collect())
    }

    async fn get_blocks(&self, limit: u32) -> PoolResult<Vec<BlockInfo>> {
        let path = format!("/api/blocks?limit={}", limit);

        let blocks: Vec<AleoBlock> = self.get(&path).await.unwrap_or_default();

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
                    hash: b.block_hash,
                    reward: Decimal::from(b.reward.unwrap_or(0)),
                    finder_wallet: wallet,
                    finder_worker: worker,
                    timestamp: b.timestamp,
                }
            })
            .collect())
    }

    async fn get_blocks_since_height(&self, height: i64) -> PoolResult<Vec<BlockInfo>> {
        let path = format!("/api/blocks?since_height={}", height);

        let blocks: Vec<AleoBlock> = self.get(&path).await.unwrap_or_default();

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
                    hash: b.block_hash,
                    reward: Decimal::from(b.reward.unwrap_or(0)),
                    finder_wallet: wallet,
                    finder_worker: worker,
                    timestamp: b.timestamp,
                }
            })
            .collect())
    }
}

// ALEO Pool API response types

#[derive(Deserialize)]
struct AleoPoolStats {
    pool_hashrate: Option<f64>,
    connected_miners: Option<u32>,
    blocks_found: Option<u64>,
    current_height: Option<u64>,
    difficulty: Option<String>,
    last_block_time: Option<i64>,
}

#[derive(Deserialize)]
struct AleoMinerStats {
    address: Option<String>,
    hashrate: Option<f64>,
    total_proofs: Option<u64>,
    valid_proofs: Option<u64>,
    invalid_proofs: Option<u64>,
    last_proof_time: Option<i64>,
}

#[derive(Deserialize)]
struct AleoProof {
    miner: String,
    target: Option<u64>,
    height: Option<i64>,
    is_coinbase: Option<bool>,
    timestamp: i64,
}

#[derive(Deserialize)]
struct AleoBlock {
    height: i64,
    block_hash: String,
    reward: Option<u64>,
    miner: String,
    timestamp: i64,
}
