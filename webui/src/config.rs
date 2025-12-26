use serde::Deserialize;

#[derive(Debug, Clone, Deserialize)]
pub struct Config {
    pub server: ServerConfig,
    pub pools: PoolsConfig,
    /// Authentication configuration
    #[serde(default)]
    pub auth: AuthConfig,
}

#[derive(Debug, Clone, Deserialize)]
pub struct AuthConfig {
    /// Enable authentication (default: true)
    #[serde(default = "default_true")]
    pub enabled: bool,
    /// Path to credentials file
    #[serde(default = "default_credentials_path")]
    pub credentials_file: String,
    /// Session timeout in seconds (default: 24 hours)
    #[serde(default = "default_session_timeout")]
    pub session_timeout_secs: u64,
    /// Cookie name for session
    #[serde(default = "default_cookie_name")]
    pub cookie_name: String,
}

impl Default for AuthConfig {
    fn default() -> Self {
        Self {
            enabled: true,
            credentials_file: default_credentials_path(),
            session_timeout_secs: default_session_timeout(),
            cookie_name: default_cookie_name(),
        }
    }
}

fn default_credentials_path() -> String {
    "/opt/solo-pool/.credentials".to_string()
}

fn default_session_timeout() -> u64 {
    86400 // 24 hours
}

fn default_cookie_name() -> String {
    "solo_pool_session".to_string()
}

#[derive(Debug, Clone, Deserialize)]
pub struct ServerConfig {
    #[serde(default = "default_host")]
    pub host: String,
    #[serde(default = "default_port")]
    pub port: u16,
    #[serde(default = "default_refresh")]
    pub refresh_interval_secs: u64,
    /// Database directory for persistent worker stats
    #[serde(default = "default_db_dir")]
    pub db_dir: String,
    /// HTTPS configuration
    #[serde(default)]
    pub https: HttpsConfig,
    /// Logging configuration
    #[serde(default)]
    pub logging: LogConfig,
    /// Payment processor API URL (for proxying payment requests)
    #[serde(default = "default_payments_api_url")]
    pub payments_api_url: String,
    /// Payment processor API token (for authenticating with payment service)
    #[serde(default)]
    pub payments_api_token: String,
}

fn default_payments_api_url() -> String {
    "http://127.0.0.1:8081".to_string()
}

#[derive(Debug, Clone, Deserialize)]
pub struct LogConfig {
    /// Directory for log files
    #[serde(default = "default_log_dir")]
    pub log_dir: String,
    /// Enable access logging (Apache Combined Log Format)
    #[serde(default = "default_true")]
    pub access_log_enabled: bool,
    /// Enable error logging
    #[serde(default = "default_true")]
    #[allow(dead_code)]
    pub error_log_enabled: bool,
}

impl Default for LogConfig {
    fn default() -> Self {
        Self {
            log_dir: default_log_dir(),
            access_log_enabled: true,
            error_log_enabled: true,
        }
    }
}

#[derive(Debug, Clone, Deserialize)]
pub struct HttpsConfig {
    /// Enable HTTPS server
    #[serde(default = "default_https_enabled")]
    pub enabled: bool,
    /// HTTPS port (default: 8443)
    #[serde(default = "default_https_port")]
    pub port: u16,
    /// Path to TLS certificate file (PEM format)
    #[serde(default = "default_cert_path")]
    pub cert_path: String,
    /// Path to TLS private key file (PEM format)
    #[serde(default = "default_key_path")]
    pub key_path: String,
}

impl Default for HttpsConfig {
    fn default() -> Self {
        Self {
            enabled: default_https_enabled(),
            port: default_https_port(),
            cert_path: default_cert_path(),
            key_path: default_key_path(),
        }
    }
}

fn default_host() -> String {
    "0.0.0.0".to_string()
}

fn default_port() -> u16 {
    8080
}

fn default_refresh() -> u64 {
    10
}

fn default_https_enabled() -> bool {
    true
}

fn default_https_port() -> u16 {
    8443
}

fn default_cert_path() -> String {
    "/opt/solo-pool/webui/certs/server.crt".to_string()
}

fn default_key_path() -> String {
    "/opt/solo-pool/webui/certs/server.key".to_string()
}

fn default_log_dir() -> String {
    "/opt/solo-pool/webui/logs".to_string()
}

fn default_db_dir() -> String {
    "/opt/solo-pool/webui/data".to_string()
}

fn default_true() -> bool {
    true
}

// CKPool uses BTCSOLO mode: miners provide their own wallet address as username
fn default_ckpool_username() -> String {
    "YOUR_WALLET_ADDRESS.worker_name".to_string()
}

fn default_xmr_username() -> String {
    "wallet_address.worker_name".to_string()
}

fn default_xmr_password() -> String {
    "x".to_string()
}

fn default_tari_username() -> String {
    "wallet_address.worker_name".to_string()
}

fn default_aleo_username() -> String {
    "wallet_address.worker_name".to_string()
}

fn default_password() -> String {
    "x".to_string()
}

#[derive(Debug, Clone, Deserialize)]
pub struct PoolsConfig {
    #[serde(default)]
    pub btc: Option<CkPoolConfig>,
    #[serde(default)]
    pub bch: Option<CkPoolConfig>,
    #[serde(default)]
    pub dgb: Option<CkPoolConfig>,
    #[serde(default)]
    pub xmr: Option<MoneroPoolConfig>,
    #[serde(default)]
    pub xtm: Option<TariPoolConfig>,
    #[serde(default)]
    pub xmr_xtm_merge: Option<MergePoolConfig>,
    #[serde(default)]
    pub aleo: Option<AleoPoolConfig>,
}

#[derive(Debug, Clone, Deserialize)]
pub struct CkPoolConfig {
    pub enabled: bool,
    pub name: String,
    pub algorithm: String,
    /// Unix socket directory for CKPool API
    /// Each pool instance must have its own socket directory (e.g., /tmp/ckpool-btc)
    /// CKPool must be started with -s flag pointing to this directory
    pub socket_dir: Option<String>,
    pub stratum_port: u16,
    /// Miner username format (e.g., "wallet_address.worker_name" or "worker_name")
    #[serde(default = "default_ckpool_username")]
    pub username_format: String,
    /// Miner password (typically ignored, use "x")
    #[serde(default = "default_password")]
    pub password: String,
    /// Node RPC URL for sync status (e.g., http://127.0.0.1:8332)
    #[serde(default)]
    pub node_rpc_url: Option<String>,
    /// Node RPC username
    #[serde(default = "default_rpc_user")]
    pub node_rpc_user: String,
    /// Node RPC password
    #[serde(default)]
    pub node_rpc_password: Option<String>,
}

fn default_rpc_user() -> String {
    "rpc".to_string()
}

#[derive(Debug, Clone, Deserialize)]
pub struct MoneroPoolConfig {
    pub enabled: bool,
    pub name: String,
    pub algorithm: String,
    /// monero-pool API URL (e.g., http://127.0.0.1:4243 for stats)
    pub api_url: String,
    pub stratum_port: u16,
    /// Pool wallet address (receives block rewards for PPLNS distribution)
    #[serde(default)]
    pub pool_wallet_address: Option<String>,
    /// Miner username format
    #[serde(default = "default_xmr_username")]
    pub username_format: String,
    /// Miner password
    #[serde(default = "default_xmr_password")]
    pub password: String,
    /// Node RPC URL for sync status (e.g., http://127.0.0.1:18081)
    #[serde(default = "default_monero_rpc")]
    pub node_rpc_url: String,
    /// Node RPC username for authentication
    #[serde(default)]
    pub node_rpc_user: Option<String>,
    /// Node RPC password for authentication
    #[serde(default)]
    pub node_rpc_password: Option<String>,
}

fn default_monero_rpc() -> String {
    "http://127.0.0.1:18081".to_string()
}

#[derive(Debug, Clone, Deserialize)]
pub struct TariPoolConfig {
    pub enabled: bool,
    pub name: String,
    pub algorithm: String,
    /// Minotari miner API URL
    pub api_url: String,
    pub stratum_port: u16,
    /// Pool wallet address (receives block rewards for PPLNS distribution)
    #[serde(default)]
    pub pool_wallet_address: Option<String>,
    /// Miner username format
    #[serde(default = "default_tari_username")]
    pub username_format: String,
    /// Miner password
    #[serde(default = "default_password")]
    pub password: String,
    /// Node gRPC port for sync status
    #[serde(default = "default_tari_grpc_port")]
    pub node_grpc_port: u16,
}

fn default_tari_grpc_port() -> u16 {
    18142
}

#[derive(Debug, Clone, Deserialize)]
pub struct MergePoolConfig {
    pub enabled: bool,
    pub name: String,
    pub algorithm: String,
    /// Merge mining proxy API URL (if available)
    #[serde(default)]
    pub api_url: Option<String>,
    pub stratum_port: u16,
    /// XMR pool wallet address (receives XMR block rewards)
    #[serde(default)]
    pub xmr_pool_wallet_address: Option<String>,
    /// XTM pool wallet address (receives XTM block rewards)
    #[serde(default)]
    pub xtm_pool_wallet_address: Option<String>,
    /// Miner username format
    #[serde(default = "default_xmr_username")]
    pub username_format: String,
    /// Miner password
    #[serde(default = "default_xmr_password")]
    pub password: String,
    /// Monero node RPC URL for sync status
    #[serde(default = "default_monero_rpc")]
    pub xmr_node_rpc_url: String,
    /// Monero node RPC username for authentication
    #[serde(default)]
    pub xmr_node_rpc_user: Option<String>,
    /// Monero node RPC password for authentication
    #[serde(default)]
    pub xmr_node_rpc_password: Option<String>,
    /// Tari node gRPC port for sync status
    #[serde(default = "default_tari_grpc_port")]
    pub xtm_node_grpc_port: u16,
}

#[derive(Debug, Clone, Deserialize)]
pub struct AleoPoolConfig {
    pub enabled: bool,
    pub name: String,
    pub algorithm: String,
    pub api_url: String,
    pub stratum_port: u16,
    /// Pool wallet address (receives block rewards for PPLNS distribution)
    #[serde(default)]
    pub pool_wallet_address: Option<String>,
    /// Miner username format
    #[serde(default = "default_aleo_username")]
    pub username_format: String,
    /// Miner password
    #[serde(default = "default_password")]
    pub password: String,
    /// Node REST URL for sync status (e.g., http://127.0.0.1:3030)
    #[serde(default = "default_aleo_rest")]
    pub node_rest_url: String,
    /// Node RPC username for authentication
    #[serde(default)]
    pub node_rpc_user: Option<String>,
    /// Node RPC password for authentication
    #[serde(default)]
    pub node_rpc_password: Option<String>,
    /// Network name for API calls (mainnet or testnet)
    #[serde(default = "default_aleo_network")]
    pub network: String,
}

fn default_aleo_rest() -> String {
    "http://127.0.0.1:3030".to_string()
}

fn default_aleo_network() -> String {
    "mainnet".to_string()
}

impl Config {
    pub fn load() -> anyhow::Result<Self> {
        // Try to load from config file, fall back to defaults
        let config_path = std::env::var("CONFIG_PATH")
            .unwrap_or_else(|_| "/opt/solo-pool/webui/config/config.toml".to_string());

        if std::path::Path::new(&config_path).exists() {
            let content = std::fs::read_to_string(&config_path)?;
            let config: Config = toml::from_str(&content)?;
            Ok(config)
        } else {
            tracing::warn!("Config file not found at {}, using defaults", config_path);
            Ok(Self::default())
        }
    }
}

impl Default for Config {
    fn default() -> Self {
        Self {
            server: ServerConfig {
                host: default_host(),
                port: default_port(),
                refresh_interval_secs: default_refresh(),
                db_dir: default_db_dir(),
                https: HttpsConfig::default(),
                logging: LogConfig::default(),
                payments_api_url: default_payments_api_url(),
                payments_api_token: String::new(),
            },
            auth: AuthConfig::default(),
            pools: PoolsConfig {
                btc: Some(CkPoolConfig {
                    enabled: true,
                    name: "Bitcoin".to_string(),
                    algorithm: "SHA256".to_string(),
                    socket_dir: Some("/tmp/ckpool-btc".to_string()),
                    stratum_port: 3333,
                    username_format: "YOUR_BTC_ADDRESS.worker_name".to_string(),
                    password: "x".to_string(),
                    node_rpc_url: Some("http://127.0.0.1:8332".to_string()),
                    node_rpc_user: default_rpc_user(),
                    node_rpc_password: None,
                }),
                bch: Some(CkPoolConfig {
                    enabled: true,
                    name: "Bitcoin Cash".to_string(),
                    algorithm: "SHA256".to_string(),
                    socket_dir: Some("/tmp/ckpool-bch".to_string()),
                    stratum_port: 3334,
                    username_format: "YOUR_BCH_ADDRESS.worker_name".to_string(),
                    password: "x".to_string(),
                    node_rpc_url: Some("http://127.0.0.1:8334".to_string()),
                    node_rpc_user: default_rpc_user(),
                    node_rpc_password: None,
                }),
                dgb: Some(CkPoolConfig {
                    enabled: true,
                    name: "DigiByte".to_string(),
                    algorithm: "SHA256".to_string(),
                    socket_dir: Some("/tmp/ckpool-dgb".to_string()),
                    stratum_port: 3335,
                    username_format: "YOUR_DGB_ADDRESS.worker_name".to_string(),
                    password: "x".to_string(),
                    node_rpc_url: Some("http://127.0.0.1:14022".to_string()),
                    node_rpc_user: default_rpc_user(),
                    node_rpc_password: None,
                }),
                xmr: Some(MoneroPoolConfig {
                    enabled: false, // Disabled when using merge mode
                    name: "Monero".to_string(),
                    algorithm: "RandomX".to_string(),
                    api_url: "http://127.0.0.1:3336".to_string(),
                    stratum_port: 3336,
                    pool_wallet_address: None,
                    username_format: "YOUR_XMR_ADDRESS.worker_name".to_string(),
                    password: "x".to_string(),
                    node_rpc_url: default_monero_rpc(),
                }),
                xtm: Some(TariPoolConfig {
                    enabled: false, // Disabled when using merge mode
                    name: "Tari".to_string(),
                    algorithm: "RandomX".to_string(),
                    api_url: "http://127.0.0.1:3337".to_string(),
                    stratum_port: 3337,
                    pool_wallet_address: None,
                    username_format: "YOUR_XTM_ADDRESS.worker_name".to_string(),
                    password: "x".to_string(),
                    node_grpc_port: default_tari_grpc_port(),
                }),
                xmr_xtm_merge: Some(MergePoolConfig {
                    enabled: true, // Default: merge mining mode
                    name: "Monero + Tari".to_string(),
                    algorithm: "RandomX (Merge)".to_string(),
                    api_url: Some("http://127.0.0.1:3338".to_string()),
                    stratum_port: 3338,
                    xmr_pool_wallet_address: None,
                    xtm_pool_wallet_address: None,
                    username_format: "YOUR_XMR_ADDRESS.worker_name".to_string(),
                    password: "x".to_string(),
                    xmr_node_rpc_url: default_monero_rpc(),
                    xtm_node_grpc_port: default_tari_grpc_port(),
                }),
                aleo: Some(AleoPoolConfig {
                    enabled: true,
                    name: "Aleo".to_string(),
                    algorithm: "zkSNARK".to_string(),
                    api_url: "http://127.0.0.1:3339".to_string(),
                    stratum_port: 3339,
                    pool_wallet_address: None,
                    username_format: "YOUR_ALEO_ADDRESS.worker_name".to_string(),
                    password: "x".to_string(),
                    node_rest_url: default_aleo_rest(),
                    network: default_aleo_network(),
                }),
            },
        }
    }
}
