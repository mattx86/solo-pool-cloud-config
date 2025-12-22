use serde::Deserialize;

#[derive(Debug, Clone, Deserialize)]
pub struct Config {
    pub server: ServerConfig,
    pub pools: PoolsConfig,
}

#[derive(Debug, Clone, Deserialize)]
pub struct ServerConfig {
    #[serde(default = "default_host")]
    pub host: String,
    #[serde(default = "default_port")]
    pub port: u16,
    #[serde(default = "default_refresh")]
    pub refresh_interval_secs: u64,
    /// HTTPS configuration
    #[serde(default)]
    pub https: HttpsConfig,
    /// Logging configuration
    #[serde(default)]
    pub logging: LogConfig,
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

fn default_true() -> bool {
    true
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
}

#[derive(Debug, Clone, Deserialize)]
pub struct MoneroPoolConfig {
    pub enabled: bool,
    pub name: String,
    pub algorithm: String,
    /// P2Pool API URL (e.g., http://127.0.0.1:3336 for stratum port)
    pub api_url: String,
    pub stratum_port: u16,
}

#[derive(Debug, Clone, Deserialize)]
pub struct TariPoolConfig {
    pub enabled: bool,
    pub name: String,
    pub algorithm: String,
    /// Minotari miner API URL
    pub api_url: String,
    pub stratum_port: u16,
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
}

#[derive(Debug, Clone, Deserialize)]
pub struct AleoPoolConfig {
    pub enabled: bool,
    pub name: String,
    pub algorithm: String,
    pub api_url: String,
    pub stratum_port: u16,
}

impl Config {
    pub fn load() -> anyhow::Result<Self> {
        // Try to load from config file, fall back to defaults
        let config_path = std::env::var("CONFIG_PATH")
            .unwrap_or_else(|_| "/opt/solo-pool/webui/config.toml".to_string());

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
                https: HttpsConfig::default(),
                logging: LogConfig::default(),
            },
            pools: PoolsConfig {
                btc: Some(CkPoolConfig {
                    enabled: true,
                    name: "Bitcoin".to_string(),
                    algorithm: "SHA256".to_string(),
                    socket_dir: Some("/tmp/ckpool-btc".to_string()),
                    stratum_port: 3333,
                }),
                bch: Some(CkPoolConfig {
                    enabled: true,
                    name: "Bitcoin Cash".to_string(),
                    algorithm: "SHA256".to_string(),
                    socket_dir: Some("/tmp/ckpool-bch".to_string()),
                    stratum_port: 3334,
                }),
                dgb: Some(CkPoolConfig {
                    enabled: true,
                    name: "DigiByte".to_string(),
                    algorithm: "SHA256".to_string(),
                    socket_dir: Some("/tmp/ckpool-dgb".to_string()),
                    stratum_port: 3335,
                }),
                xmr: Some(MoneroPoolConfig {
                    enabled: false, // Disabled when using merge mode
                    name: "Monero".to_string(),
                    algorithm: "RandomX".to_string(),
                    api_url: "http://127.0.0.1:3336".to_string(),
                    stratum_port: 3336,
                }),
                xtm: Some(TariPoolConfig {
                    enabled: false, // Disabled when using merge mode
                    name: "Tari".to_string(),
                    algorithm: "RandomX".to_string(),
                    api_url: "http://127.0.0.1:3337".to_string(),
                    stratum_port: 3337,
                }),
                xmr_xtm_merge: Some(MergePoolConfig {
                    enabled: true, // Default: merge mining mode
                    name: "Monero + Tari".to_string(),
                    algorithm: "RandomX (Merge)".to_string(),
                    api_url: Some("http://127.0.0.1:3338".to_string()),
                    stratum_port: 3338,
                }),
                aleo: Some(AleoPoolConfig {
                    enabled: true,
                    name: "Aleo".to_string(),
                    algorithm: "zkSNARK".to_string(),
                    api_url: "http://127.0.0.1:3339".to_string(),
                    stratum_port: 3339,
                }),
            },
        }
    }
}
