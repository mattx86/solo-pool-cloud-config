//! Tari wallet integration
//!
//! Uses minotari_console_wallet JSON-RPC API for:
//! - Balance queries
//! - Address validation
//! - Transaction creation

use super::{TxStatus, Wallet, WalletError, WalletResult};
use async_trait::async_trait;
use rust_decimal::Decimal;
use serde::{Deserialize, Serialize};

/// Tari wallet client
pub struct TariWallet {
    rpc_url: String,
    client: reqwest::Client,
}

impl TariWallet {
    /// Create a new Tari wallet client
    pub fn new(rpc_url: &str) -> Self {
        Self {
            rpc_url: rpc_url.to_string(),
            client: reqwest::Client::new(),
        }
    }

    /// Make a JSON-RPC call to the wallet
    async fn rpc_call<T: for<'de> Deserialize<'de>>(
        &self,
        method: &str,
        params: serde_json::Value,
    ) -> WalletResult<T> {
        let request = JsonRpcRequest {
            jsonrpc: "2.0".to_string(),
            id: 1,
            method: method.to_string(),
            params,
        };

        let response = self
            .client
            .post(&self.rpc_url)
            .json(&request)
            .send()
            .await
            .map_err(|e| WalletError::ConnectionFailed(e.to_string()))?;

        let rpc_response: JsonRpcResponse<T> = response
            .json()
            .await
            .map_err(|e| WalletError::RpcError(e.to_string()))?;

        if let Some(error) = rpc_response.error {
            return Err(WalletError::RpcError(error.message));
        }

        rpc_response
            .result
            .ok_or_else(|| WalletError::RpcError("No result in response".to_string()))
    }
}

#[async_trait]
impl Wallet for TariWallet {
    async fn get_balance(&self) -> WalletResult<Decimal> {
        let result: GetBalanceResponse = self
            .rpc_call("get_balance", serde_json::json!({}))
            .await?;

        // Tari uses microTari (uT) as atomic units
        // 1 XTM = 1,000,000 uT
        Ok(Decimal::from(result.available_balance))
    }

    async fn get_total_balance(&self) -> WalletResult<Decimal> {
        let result: GetBalanceResponse = self
            .rpc_call("get_balance", serde_json::json!({}))
            .await?;

        // Total = available + pending_incoming
        let total = result.available_balance + result.pending_incoming_balance;
        Ok(Decimal::from(total))
    }

    async fn validate_address(&self, address: &str) -> WalletResult<bool> {
        // Tari addresses are emoji-based or hex-encoded public keys
        // Basic validation: check format
        // Full validation would require calling the node

        // Tari emoji addresses are typically 33 emojis
        // Or hex addresses are 64 characters
        let is_valid = address.len() >= 33 || (address.len() == 64 && address.chars().all(|c| c.is_ascii_hexdigit()));

        Ok(is_valid)
    }

    async fn send_payment(&self, to_address: &str, amount: Decimal) -> WalletResult<String> {
        // Amount in microTari
        let amount_ut: u64 = amount
            .to_string()
            .parse()
            .map_err(|_| WalletError::TransactionFailed("Invalid amount".to_string()))?;

        let params = serde_json::json!({
            "destinations": [{
                "address": to_address,
                "amount": amount_ut,
                "fee_per_gram": 5  // Standard fee per gram
            }],
            "message": "Solo Pool Payment"
        });

        let result: TransferResponse = self.rpc_call("transfer", params).await?;

        Ok(result.transaction_id.to_string())
    }

    async fn send_batch_payment(
        &self,
        payments: &[(String, Decimal)],
    ) -> WalletResult<Vec<(String, String)>> {
        if payments.is_empty() {
            return Ok(Vec::new());
        }

        // Tari wallet RPC supports batch transfers
        let destinations: Vec<serde_json::Value> = payments
            .iter()
            .map(|(address, amount)| {
                let amount_ut: u64 = amount.to_string().parse().unwrap_or(0);
                serde_json::json!({
                    "address": address,
                    "amount": amount_ut,
                    "fee_per_gram": 5
                })
            })
            .collect();

        let params = serde_json::json!({
            "destinations": destinations,
            "message": "Solo Pool Batch Payment"
        });

        let result: TransferResponse = self.rpc_call("transfer", params).await?;

        // All payments in a batch share the same transaction ID
        let results: Vec<(String, String)> = payments
            .iter()
            .map(|(addr, _)| (addr.clone(), result.transaction_id.to_string()))
            .collect();

        Ok(results)
    }

    async fn get_tx_status(&self, tx_hash: &str) -> WalletResult<TxStatus> {
        let tx_id: u64 = tx_hash
            .parse()
            .map_err(|_| WalletError::TransactionNotFound(tx_hash.to_string()))?;

        let params = serde_json::json!({
            "transaction_id": tx_id
        });

        match self
            .rpc_call::<GetTransactionResponse>("get_transaction_info", params)
            .await
        {
            Ok(result) => {
                match result.status.as_str() {
                    "Completed" | "Broadcast" | "MinedUnconfirmed" => {
                        let confirmations = result.confirmations.unwrap_or(0);
                        if confirmations >= self.required_confirmations() {
                            Ok(TxStatus::Confirmed)
                        } else if confirmations > 0 {
                            Ok(TxStatus::Confirming { confirmations })
                        } else {
                            Ok(TxStatus::Pending)
                        }
                    }
                    "MinedConfirmed" => Ok(TxStatus::Confirmed),
                    "Rejected" | "Cancelled" => {
                        Ok(TxStatus::Failed(result.message.unwrap_or_default()))
                    }
                    _ => Ok(TxStatus::Pending),
                }
            }
            Err(WalletError::RpcError(msg)) if msg.contains("not found") => {
                Ok(TxStatus::NotFound)
            }
            Err(e) => Err(e),
        }
    }

    fn required_confirmations(&self) -> u64 {
        3 // Tari typically requires 3 confirmations
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
struct GetBalanceResponse {
    available_balance: u64,
    pending_incoming_balance: u64,
    #[allow(dead_code)]
    pending_outgoing_balance: u64,
}

#[derive(Deserialize)]
struct TransferResponse {
    transaction_id: u64,
    #[serde(default)]
    #[allow(dead_code)]
    is_success: bool,
}

#[derive(Deserialize)]
struct GetTransactionResponse {
    status: String,
    #[serde(default)]
    confirmations: Option<u64>,
    #[serde(default)]
    message: Option<String>,
}
