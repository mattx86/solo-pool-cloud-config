//! ALEO wallet integration
//!
//! Uses snarkOS RPC API for:
//! - Balance queries
//! - Transaction creation and broadcast
//!
//! Note: ALEO uses a different model - transactions are created and signed
//! locally, then broadcast to the network.

use super::{TxStatus, Wallet, WalletError, WalletResult};
use async_trait::async_trait;
use rust_decimal::Decimal;
use serde::{Deserialize, Serialize};

/// ALEO wallet client
pub struct AleoWallet {
    node_rpc_url: String,
    pool_address: String,
    pool_private_key: String,
    client: reqwest::Client,
}

impl AleoWallet {
    /// Create a new ALEO wallet client
    pub fn new(node_rpc_url: &str, pool_address: &str, pool_private_key: &str) -> Self {
        Self {
            node_rpc_url: node_rpc_url.to_string(),
            pool_address: pool_address.to_string(),
            pool_private_key: pool_private_key.to_string(),
            client: reqwest::Client::new(),
        }
    }

    /// Make a JSON-RPC call to the node
    async fn rpc_call<T: for<'de> Deserialize<'de>>(
        &self,
        method: &str,
        params: Vec<serde_json::Value>,
    ) -> WalletResult<T> {
        let request = JsonRpcRequest {
            jsonrpc: "2.0".to_string(),
            id: "1".to_string(),
            method: method.to_string(),
            params,
        };

        let response = self
            .client
            .post(&self.node_rpc_url)
            .json(&request)
            .send()
            .await
            .map_err(|e| WalletError::ConnectionFailed(e.to_string()))?;

        let rpc_response: JsonRpcResponse<T> = response
            .json()
            .await
            .map_err(|e| WalletError::RpcError(e.to_string()))?;

        if let Some(error) = rpc_response.error {
            return Err(WalletError::RpcError(format!(
                "{}: {}",
                error.code, error.message
            )));
        }

        rpc_response
            .result
            .ok_or_else(|| WalletError::RpcError("No result in response".to_string()))
    }

    /// Get the latest block height
    async fn get_latest_height(&self) -> WalletResult<u64> {
        let result: u64 = self
            .rpc_call("latestHeight", vec![])
            .await?;
        Ok(result)
    }
}

#[async_trait]
impl Wallet for AleoWallet {
    async fn get_balance(&self) -> WalletResult<Decimal> {
        // Query the mapping for credits.aleo/account[address]
        let params = vec![
            serde_json::json!("credits.aleo"),
            serde_json::json!("account"),
            serde_json::json!(self.pool_address),
        ];

        match self.rpc_call::<serde_json::Value>("getMappingValue", params).await {
            Ok(value) => {
                // Parse the credits value (in microcredits)
                // Format is typically: "123456u64"
                let value_str = value.as_str().unwrap_or("0u64");
                let microcredits: u64 = value_str
                    .trim_end_matches("u64")
                    .parse()
                    .unwrap_or(0);
                Ok(Decimal::from(microcredits))
            }
            Err(_) => {
                // Account not found means zero balance
                Ok(Decimal::from(0))
            }
        }
    }

    async fn get_total_balance(&self) -> WalletResult<Decimal> {
        // For ALEO, total balance = available balance (no locking mechanism like in Monero)
        self.get_balance().await
    }

    async fn validate_address(&self, address: &str) -> WalletResult<bool> {
        // ALEO addresses start with "aleo1" and are 63 characters total
        // They use bech32m encoding
        let is_valid = address.starts_with("aleo1") && address.len() == 63;
        Ok(is_valid)
    }

    async fn send_payment(&self, to_address: &str, amount: Decimal) -> WalletResult<String> {
        if !self.validate_address(to_address).await? {
            return Err(WalletError::InvalidAddress(to_address.to_string()));
        }

        // Amount in microcredits
        let amount_microcredits: u64 = amount
            .to_string()
            .parse()
            .map_err(|_| WalletError::TransactionFailed("Invalid amount".to_string()))?;

        // Build and broadcast a credits.aleo/transfer_public transaction
        // Note: In production, this would use the Aleo SDK to build and sign the transaction
        // For now, we use the node's transaction broadcast capability

        // This is a simplified version - in production you'd use aleo-rust SDK
        let program_id = "credits.aleo";
        let function_name = "transfer_public";
        let inputs = vec![
            self.pool_address.clone(),
            to_address.to_string(),
            format!("{}u64", amount_microcredits),
        ];

        let params = vec![
            serde_json::json!(self.pool_private_key),
            serde_json::json!(program_id),
            serde_json::json!(function_name),
            serde_json::json!(inputs),
            serde_json::json!(null), // fee record (null for public fee)
            serde_json::json!(10000u64), // base fee in microcredits
            serde_json::json!(null), // priority fee
        ];

        // Execute the transaction
        let result: TransactionResponse = self
            .rpc_call("developerExecute", params)
            .await
            .map_err(|e| WalletError::TransactionFailed(e.to_string()))?;

        Ok(result.transaction_id)
    }

    async fn send_batch_payment(
        &self,
        payments: &[(String, Decimal)],
    ) -> WalletResult<Vec<(String, String)>> {
        // ALEO doesn't support batch payments in a single transaction
        // We need to send individual transactions
        let mut results = Vec::new();

        for (address, amount) in payments {
            match self.send_payment(address, *amount).await {
                Ok(tx_hash) => {
                    results.push((address.clone(), tx_hash));
                }
                Err(e) => {
                    tracing::error!("Failed to send payment to {}: {}", address, e);
                    // Continue with other payments even if one fails
                }
            }

            // Small delay between transactions to avoid rate limiting
            tokio::time::sleep(tokio::time::Duration::from_millis(500)).await;
        }

        Ok(results)
    }

    async fn get_tx_status(&self, tx_hash: &str) -> WalletResult<TxStatus> {
        // Query the transaction
        let params = vec![serde_json::json!(tx_hash)];

        match self
            .rpc_call::<serde_json::Value>("getTransaction", params)
            .await
        {
            Ok(tx) => {
                // If we got the transaction, check if it's in a block
                if let Some(block_height) = tx.get("block_height").and_then(|v| v.as_u64()) {
                    // Get current height to calculate confirmations
                    let current_height = self.get_latest_height().await.unwrap_or(0);
                    let confirmations = current_height.saturating_sub(block_height);

                    if confirmations >= self.required_confirmations() {
                        Ok(TxStatus::Confirmed)
                    } else {
                        Ok(TxStatus::Confirming { confirmations })
                    }
                } else {
                    Ok(TxStatus::Pending)
                }
            }
            Err(WalletError::RpcError(msg)) if msg.contains("not found") => {
                Ok(TxStatus::NotFound)
            }
            Err(e) => Err(e),
        }
    }

    fn required_confirmations(&self) -> u64 {
        1 // ALEO has fast finality
    }
}

// JSON-RPC types

#[derive(Serialize)]
struct JsonRpcRequest {
    jsonrpc: String,
    id: String,
    method: String,
    params: Vec<serde_json::Value>,
}

#[derive(Deserialize)]
struct JsonRpcResponse<T> {
    result: Option<T>,
    error: Option<RpcError>,
}

#[derive(Deserialize)]
struct RpcError {
    code: i64,
    message: String,
}

#[derive(Deserialize)]
struct TransactionResponse {
    #[serde(alias = "id")]
    transaction_id: String,
}
