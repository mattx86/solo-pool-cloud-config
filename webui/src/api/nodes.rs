//! Node sync status checking for all supported blockchains
//!
//! Fetches sync status from:
//! - Bitcoin/BCH/DGB: bitcoin-cli getblockchaininfo (via RPC)
//! - Monero: /json_rpc sync_info endpoint
//! - Tari: gRPC or process check
//! - ALEO: REST API /latest/height

use crate::models::SyncStatus;
use serde::Deserialize;
use std::time::Duration;

/// HTTP client with short timeout for node checks
fn http_client() -> reqwest::Client {
    reqwest::Client::builder()
        .timeout(Duration::from_secs(5))
        .build()
        .unwrap_or_default()
}

/// Fetch sync status for Bitcoin-like nodes (BTC, BCH, DGB)
/// Uses JSON-RPC to call getblockchaininfo
pub async fn fetch_bitcoin_sync(rpc_url: &str, rpc_user: &str, rpc_pass: &str) -> SyncStatus {
    #[derive(Deserialize)]
    struct BlockchainInfo {
        blocks: u64,
        headers: u64,
        #[serde(default)]
        verificationprogress: f64,
        #[serde(default)]
        initialblockdownload: bool,
    }

    #[derive(Deserialize)]
    struct RpcResponse {
        result: Option<BlockchainInfo>,
        #[allow(dead_code)]
        error: Option<serde_json::Value>,
    }

    let client = http_client();
    let body = serde_json::json!({
        "jsonrpc": "1.0",
        "id": "webui",
        "method": "getblockchaininfo",
        "params": []
    });

    match client
        .post(rpc_url)
        .basic_auth(rpc_user, Some(rpc_pass))
        .json(&body)
        .send()
        .await
    {
        Ok(response) => {
            if let Ok(rpc_resp) = response.json::<RpcResponse>().await {
                if let Some(info) = rpc_resp.result {
                    let sync_percent = info.verificationprogress * 100.0;
                    let is_synced = !info.initialblockdownload && sync_percent >= 99.9;

                    return SyncStatus {
                        node_online: true,
                        is_synced,
                        current_height: info.blocks,
                        target_height: Some(info.headers),
                        sync_percent: sync_percent.min(100.0),
                        status_message: if is_synced {
                            format!("Synced ({})", info.blocks)
                        } else {
                            format!("Syncing {:.1}%", sync_percent)
                        },
                    };
                }
            }
            SyncStatus {
                node_online: true,
                status_message: "Error parsing response".to_string(),
                ..Default::default()
            }
        }
        Err(_) => SyncStatus {
            node_online: false,
            status_message: "Node offline".to_string(),
            ..Default::default()
        },
    }
}

/// Fetch sync status for Monero node
/// Uses JSON-RPC /json_rpc endpoint with sync_info method
pub async fn fetch_monero_sync(rpc_url: &str) -> SyncStatus {
    #[derive(Deserialize)]
    struct SyncInfo {
        height: u64,
        target_height: u64,
    }

    #[derive(Deserialize)]
    struct RpcResult {
        #[allow(dead_code)]
        status: String,
        #[serde(flatten)]
        info: SyncInfo,
    }

    #[derive(Deserialize)]
    struct RpcResponse {
        result: Option<RpcResult>,
    }

    let client = http_client();
    let url = format!("{}/json_rpc", rpc_url.trim_end_matches('/'));
    let body = serde_json::json!({
        "jsonrpc": "2.0",
        "id": "0",
        "method": "sync_info"
    });

    match client.post(&url).json(&body).send().await {
        Ok(response) => {
            if let Ok(rpc_resp) = response.json::<RpcResponse>().await {
                if let Some(result) = rpc_resp.result {
                    let target = if result.info.target_height > 0 {
                        result.info.target_height
                    } else {
                        result.info.height
                    };

                    let sync_percent = if target > 0 {
                        (result.info.height as f64 / target as f64 * 100.0).min(100.0)
                    } else {
                        100.0
                    };

                    let is_synced = result.info.height >= target || target == 0;

                    return SyncStatus {
                        node_online: true,
                        is_synced,
                        current_height: result.info.height,
                        target_height: if target > 0 { Some(target) } else { None },
                        sync_percent,
                        status_message: if is_synced {
                            format!("Synced ({})", result.info.height)
                        } else {
                            format!("Syncing {:.1}%", sync_percent)
                        },
                    };
                }
            }
            SyncStatus {
                node_online: true,
                status_message: "Error parsing response".to_string(),
                ..Default::default()
            }
        }
        Err(_) => SyncStatus {
            node_online: false,
            status_message: "Node offline".to_string(),
            ..Default::default()
        },
    }
}

/// Fetch sync status for Tari node
/// Checks if the gRPC port is reachable (basic connectivity check)
pub async fn fetch_tari_sync(grpc_port: u16) -> SyncStatus {
    // For Tari, we do a simple TCP connectivity check to the gRPC port
    // Full gRPC integration would require tonic and proto files
    use tokio::net::TcpStream;
    use tokio::time::timeout;

    let addr = format!("127.0.0.1:{}", grpc_port);

    match timeout(Duration::from_secs(2), TcpStream::connect(&addr)).await {
        Ok(Ok(_)) => SyncStatus {
            node_online: true,
            is_synced: true, // Assume synced if responsive
            current_height: 0,
            target_height: None,
            sync_percent: 100.0,
            status_message: "Node online".to_string(),
        },
        _ => SyncStatus {
            node_online: false,
            status_message: "Node offline".to_string(),
            ..Default::default()
        },
    }
}

/// Fetch sync status for ALEO node
/// Uses REST API to get latest height
pub async fn fetch_aleo_sync(rest_url: &str, network: &str) -> SyncStatus {
    let client = http_client();
    // snarkOS REST API: /{network}/latest/height
    let url = format!("{}/{}/latest/height", rest_url.trim_end_matches('/'), network);

    match client.get(&url).send().await {
        Ok(response) => {
            if let Ok(height_str) = response.text().await {
                if let Ok(height) = height_str.trim().parse::<u64>() {
                    return SyncStatus {
                        node_online: true,
                        is_synced: height > 0,
                        current_height: height,
                        target_height: None,
                        sync_percent: if height > 0 { 100.0 } else { 0.0 },
                        status_message: if height > 0 {
                            format!("Synced ({})", height)
                        } else {
                            "Syncing...".to_string()
                        },
                    };
                }
            }
            SyncStatus {
                node_online: true,
                status_message: "Error parsing height".to_string(),
                ..Default::default()
            }
        }
        Err(_) => SyncStatus {
            node_online: false,
            status_message: "Node offline".to_string(),
            ..Default::default()
        },
    }
}
