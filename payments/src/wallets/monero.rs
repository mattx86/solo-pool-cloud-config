//! Monero wallet RPC integration
//!
//! Uses monero-wallet-rpc JSON-RPC API for:
//! - Balance queries
//! - Address validation
//! - Transaction creation

use super::{TxStatus, Wallet, WalletError, WalletResult};
use async_trait::async_trait;
use rust_decimal::Decimal;
use serde::{Deserialize, Serialize};
use std::str::FromStr;

/// Monero wallet client
pub struct MoneroWallet {
    rpc_url: String,
    client: reqwest::Client,
    mixin: u32,
}

impl MoneroWallet {
    /// Create a new Monero wallet client
    pub fn new(rpc_url: &str, mixin: u32) -> Self {
        Self {
            rpc_url: rpc_url.to_string(),
            client: reqwest::Client::new(),
            mixin,
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
            id: "0".to_string(),
            method: method.to_string(),
            params,
        };

        let response = self
            .client
            .post(&format!("{}/json_rpc", self.rpc_url))
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
impl Wallet for MoneroWallet {
    async fn get_balance(&self) -> WalletResult<Decimal> {
        let result: GetBalanceResponse = self
            .rpc_call("get_balance", serde_json::json!({"account_index": 0}))
            .await?;

        // Convert from atomic units (piconero) to XMR
        // 1 XMR = 1e12 piconero
        let balance_atomic = Decimal::from(result.unlocked_balance);
        Ok(balance_atomic)
    }

    async fn get_total_balance(&self) -> WalletResult<Decimal> {
        let result: GetBalanceResponse = self
            .rpc_call("get_balance", serde_json::json!({"account_index": 0}))
            .await?;

        let balance_atomic = Decimal::from(result.balance);
        Ok(balance_atomic)
    }

    async fn validate_address(&self, address: &str) -> WalletResult<bool> {
        let result: ValidateAddressResponse = self
            .rpc_call(
                "validate_address",
                serde_json::json!({"address": address}),
            )
            .await?;

        Ok(result.valid)
    }

    async fn send_payment(&self, to_address: &str, amount: Decimal) -> WalletResult<String> {
        // Validate address first
        if !self.validate_address(to_address).await? {
            return Err(WalletError::InvalidAddress(to_address.to_string()));
        }

        // Amount should be in atomic units (piconero)
        let amount_atomic: u64 = amount
            .to_string()
            .parse()
            .map_err(|_| WalletError::TransactionFailed("Invalid amount".to_string()))?;

        let params = serde_json::json!({
            "destinations": [{
                "address": to_address,
                "amount": amount_atomic
            }],
            "priority": 1,
            "ring_size": self.mixin + 1,
            "get_tx_key": true
        });

        let result: TransferResponse = self.rpc_call("transfer", params).await?;

        Ok(result.tx_hash)
    }

    async fn send_batch_payment(
        &self,
        payments: &[(String, Decimal)],
    ) -> WalletResult<Vec<(String, String)>> {
        if payments.is_empty() {
            return Ok(Vec::new());
        }

        // Validate all addresses first
        for (address, _) in payments {
            if !self.validate_address(address).await? {
                return Err(WalletError::InvalidAddress(address.clone()));
            }
        }

        // Build destinations
        let destinations: Vec<serde_json::Value> = payments
            .iter()
            .map(|(address, amount)| {
                let amount_atomic: u64 = amount
                    .to_string()
                    .parse()
                    .unwrap_or(0);
                serde_json::json!({
                    "address": address,
                    "amount": amount_atomic
                })
            })
            .collect();

        let params = serde_json::json!({
            "destinations": destinations,
            "priority": 1,
            "ring_size": self.mixin + 1,
            "get_tx_key": true
        });

        let result: TransferResponse = self.rpc_call("transfer", params).await?;

        // All payments in a batch have the same tx_hash
        let results: Vec<(String, String)> = payments
            .iter()
            .map(|(addr, _)| (addr.clone(), result.tx_hash.clone()))
            .collect();

        Ok(results)
    }

    async fn get_tx_status(&self, tx_hash: &str) -> WalletResult<TxStatus> {
        let params = serde_json::json!({
            "txid": tx_hash
        });

        match self
            .rpc_call::<GetTransferByTxidResponse>("get_transfer_by_txid", params)
            .await
        {
            Ok(result) => {
                let confirmations = result.transfer.confirmations.unwrap_or(0);

                if confirmations >= self.required_confirmations() {
                    Ok(TxStatus::Confirmed)
                } else if confirmations > 0 {
                    Ok(TxStatus::Confirming { confirmations })
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
        10 // Monero standard confirmation count
    }
}

// JSON-RPC types

#[derive(Serialize)]
struct JsonRpcRequest {
    jsonrpc: String,
    id: String,
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
    balance: u64,
    unlocked_balance: u64,
}

#[derive(Deserialize)]
struct ValidateAddressResponse {
    valid: bool,
}

#[derive(Deserialize)]
struct TransferResponse {
    tx_hash: String,
    #[serde(default)]
    tx_key: Option<String>,
    #[serde(default)]
    fee: Option<u64>,
}

#[derive(Deserialize)]
struct GetTransferByTxidResponse {
    transfer: TransferInfo,
}

#[derive(Deserialize)]
struct TransferInfo {
    #[serde(default)]
    confirmations: Option<u64>,
    #[serde(default)]
    height: Option<u64>,
}
