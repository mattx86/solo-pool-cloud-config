//! Configuration for the payment processor service

use rust_decimal::Decimal;
use serde::{Deserialize, Serialize};
use std::path::PathBuf;

/// Main configuration structure
#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct Config {
    /// General service settings
    pub service: ServiceConfig,

    /// Database configuration
    pub database: DatabaseConfig,

    /// API server configuration
    pub api: ApiConfig,

    /// Monero (XMR) payment configuration
    #[serde(default)]
    pub xmr: Option<CoinConfig>,

    /// Tari (XTM) payment configuration
    #[serde(default)]
    pub xtm: Option<CoinConfig>,

    /// ALEO payment configuration
    #[serde(default)]
    pub aleo: Option<AleoConfig>,
}

#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct ServiceConfig {
    /// How often to check for new shares (seconds)
    #[serde(default = "default_share_scan_interval")]
    pub share_scan_interval_secs: u64,

    /// How often to process payments (seconds)
    #[serde(default = "default_payment_interval")]
    pub payment_interval_secs: u64,

    /// Log level (trace, debug, info, warn, error)
    #[serde(default = "default_log_level")]
    pub log_level: String,
}

fn default_share_scan_interval() -> u64 {
    60 // 1 minute
}

fn default_payment_interval() -> u64 {
    3600 // 1 hour
}

fn default_log_level() -> String {
    "info".to_string()
}

#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct DatabaseConfig {
    /// Path to SQLite database file
    #[serde(default = "default_db_path")]
    pub path: PathBuf,
}

fn default_db_path() -> PathBuf {
    PathBuf::from("/opt/solopool/payments/data/payments.db")
}

fn default_min_payout() -> Decimal {
    Decimal::from(1)
}

#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct ApiConfig {
    /// Listen address for the API server
    #[serde(default = "default_api_listen")]
    pub listen: String,

    /// API port
    #[serde(default = "default_api_port")]
    pub port: u16,

    /// API authentication token (required for all endpoints except health)
    /// If empty, authentication is disabled
    #[serde(default)]
    pub token: String,
}

fn default_api_listen() -> String {
    "127.0.0.1".to_string()
}

fn default_api_port() -> u16 {
    8090
}

/// Pool type for determining which API implementation to use
#[derive(Debug, Clone, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum PoolType {
    /// monero-pool (for XMR in monero_only mode)
    MoneroPool,
    /// Tari merge mining proxy (for XMR and XTM in merge mode)
    MergeProxy,
    /// Minotari miner (for XTM in tari_only mode)
    MinotariMiner,
}

impl Default for PoolType {
    fn default() -> Self {
        PoolType::MoneroPool
    }
}

/// Configuration for XMR and XTM (similar wallet RPC interface)
#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct CoinConfig {
    /// Whether this coin's payments are enabled
    #[serde(default = "default_enabled")]
    pub enabled: bool,

    /// Pool wallet address (receives block rewards)
    pub pool_wallet_address: String,

    /// Wallet RPC URL
    pub wallet_rpc_url: String,

    /// Wallet RPC username (if auth enabled)
    #[serde(default)]
    pub wallet_rpc_user: Option<String>,

    /// Wallet RPC password (if auth enabled)
    #[serde(default)]
    pub wallet_rpc_password: Option<String>,

    /// Minimum payout threshold (in atomic units)
    /// Any value > 0 triggers a payout
    #[serde(default = "default_min_payout")]
    pub min_payout: Decimal,

    /// Path to pool logs/data for share tracking
    pub pool_data_path: PathBuf,

    /// Pool API URL (if available)
    #[serde(default)]
    pub pool_api_url: Option<String>,

    /// Pool type - determines which API implementation to use
    /// "monero_pool" for monero-pool, "merge_proxy" for Tari merge mining proxy
    #[serde(default)]
    pub pool_type: PoolType,

    /// Mixin/ring size for transactions (XMR)
    #[serde(default = "default_mixin")]
    pub mixin: u32,
}

fn default_enabled() -> bool {
    true
}

fn default_mixin() -> u32 {
    16 // Monero default ring size
}

/// ALEO-specific configuration (different from Monero-style wallets)
#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct AleoConfig {
    /// Whether ALEO payments are enabled
    #[serde(default = "default_enabled")]
    pub enabled: bool,

    /// Pool wallet private key (for signing transactions)
    pub pool_private_key: String,

    /// Pool wallet address (view key / public address)
    pub pool_wallet_address: String,

    /// ALEO node RPC URL
    pub node_rpc_url: String,

    /// Minimum payout threshold (in microcredits)
    /// Any value > 0 triggers a payout
    #[serde(default = "default_min_payout")]
    pub min_payout: Decimal,

    /// Path to pool data for share tracking
    pub pool_data_path: PathBuf,

    /// Pool API URL (if available)
    #[serde(default)]
    pub pool_api_url: Option<String>,
}

impl Config {
    /// Load configuration from file
    pub fn load(path: &str) -> anyhow::Result<Self> {
        let contents = std::fs::read_to_string(path)?;
        let config: Config = toml::from_str(&contents)?;
        Ok(config)
    }

    /// Load configuration with environment variable overrides
    pub fn load_with_env(path: &str) -> anyhow::Result<Self> {
        let mut config = Self::load(path)?;

        // Override with environment variables if set
        if let Ok(val) = std::env::var("PAYMENTS_DB_PATH") {
            config.database.path = PathBuf::from(val);
        }
        if let Ok(val) = std::env::var("PAYMENTS_API_PORT") {
            if let Ok(port) = val.parse() {
                config.api.port = port;
            }
        }
        if let Ok(val) = std::env::var("PAYMENTS_LOG_LEVEL") {
            config.service.log_level = val;
        }

        // XMR overrides
        if let Some(ref mut xmr) = config.xmr {
            if let Ok(val) = std::env::var("XMR_WALLET_RPC_URL") {
                xmr.wallet_rpc_url = val;
            }
            if let Ok(val) = std::env::var("XMR_POOL_WALLET") {
                xmr.pool_wallet_address = val;
            }
        }

        // XTM overrides
        if let Some(ref mut xtm) = config.xtm {
            if let Ok(val) = std::env::var("XTM_WALLET_RPC_URL") {
                xtm.wallet_rpc_url = val;
            }
            if let Ok(val) = std::env::var("XTM_POOL_WALLET") {
                xtm.pool_wallet_address = val;
            }
        }

        // ALEO overrides
        if let Some(ref mut aleo) = config.aleo {
            if let Ok(val) = std::env::var("ALEO_NODE_RPC_URL") {
                aleo.node_rpc_url = val;
            }
            if let Ok(val) = std::env::var("ALEO_POOL_WALLET") {
                aleo.pool_wallet_address = val;
            }
            if let Ok(val) = std::env::var("ALEO_POOL_PRIVATE_KEY") {
                aleo.pool_private_key = val;
            }
        }

        Ok(config)
    }
}

impl Default for Config {
    fn default() -> Self {
        Self {
            service: ServiceConfig {
                share_scan_interval_secs: default_share_scan_interval(),
                payment_interval_secs: default_payment_interval(),
                log_level: default_log_level(),
            },
            database: DatabaseConfig {
                path: default_db_path(),
            },
            api: ApiConfig {
                listen: default_api_listen(),
                port: default_api_port(),
                token: String::new(),
            },
            xmr: None,
            xtm: None,
            aleo: None,
        }
    }
}
