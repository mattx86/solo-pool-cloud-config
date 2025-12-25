#!/bin/bash
# =============================================================================
# 16-install-webui.sh
# Install Solo Pool Web UI
#
# This installs a Rust-based web dashboard that displays:
# - Per-algorithm pool stats (hashrate, blocks found)
# - Individual worker statistics
# - Connection status for each pool
#
# Connects to: CKPool (BTC/BCH/DGB), monero-pool (XMR), Tari, ALEO Pool Server
# =============================================================================

set -e

# Source configuration
INSTALL_DIR="${INSTALL_DIR:-/opt/solo-pool/install}"
source ${INSTALL_DIR}/config.sh

# Validate config was loaded successfully
if [ "${CONFIG_LOADED:-}" != "true" ]; then
    echo "ERROR: Failed to load configuration from config.sh" >&2
    exit 1
fi

# Check if WebUI is enabled
if [ "${ENABLE_WEBUI}" != "true" ]; then
    log "WebUI is disabled (ENABLE_WEBUI=${ENABLE_WEBUI}), skipping installation"
    exit 0
fi

log "Installing Solo Pool Web UI..."

# WebUI directory - use config variable with fallback
WEBUI_DIR="${WEBUI_DIR:-${BASE_DIR}/webui}"

# Generate payments API token (used by both webui and payments service)
PAYMENTS_API_TOKEN_FILE="${BASE_DIR}/.payments_api_token"
PAYMENTS_API_TOKEN=$(openssl rand -hex 32)
echo "${PAYMENTS_API_TOKEN}" > "${PAYMENTS_API_TOKEN_FILE}"
chmod 600 "${PAYMENTS_API_TOKEN_FILE}"
chown ${POOL_USER}:${POOL_USER} "${PAYMENTS_API_TOKEN_FILE}"
log "  Generated payments API token: ${PAYMENTS_API_TOKEN_FILE}"

# Use config variables with defaults
WEBUI_HTTP_ENABLED="${WEBUI_HTTP_ENABLED:-true}"
WEBUI_HTTP_PORT="${WEBUI_HTTP_PORT:-8080}"
WEBUI_HTTPS_ENABLED="${WEBUI_HTTPS_ENABLED:-true}"
WEBUI_HTTPS_PORT="${WEBUI_HTTPS_PORT:-8443}"
WEBUI_USER="${WEBUI_USER:-admin}"

# Credentials file location
CREDENTIALS_FILE="${BASE_DIR}/.credentials"

# =============================================================================
# 1. VERIFY BUILD DEPENDENCIES
# =============================================================================
log "1. Verifying build dependencies..."

# Build dependencies (Rust, pkg-config, libssl-dev, apg) are installed
# by 05-install-dependencies.sh

# Explicitly add cargo to PATH (don't rely on $HOME which may not be /root in cloud-init)
export PATH="/root/.cargo/bin:$PATH"

# Source Rust environment
if [ -f "/root/.cargo/env" ]; then
    source /root/.cargo/env
fi

# Verify cargo is actually available
if ! command -v cargo &> /dev/null; then
    log_error "cargo command not found. Rust should have been installed by 05-install-dependencies.sh"
    exit 1
fi

log "  Build dependencies ready"

# =============================================================================
# 2. DOWNLOAD WEBUI SOURCE FROM GITHUB
# =============================================================================
log "2. Downloading WebUI source from GitHub..."

# Base URL for raw files (derived from SCRIPTS_BASE_URL)
WEBUI_BASE_URL="${SCRIPTS_BASE_URL%/install}/webui"

# Create directory structure
mkdir -p ${WEBUI_DIR}/src/api
mkdir -p ${WEBUI_DIR}/src/static/css
mkdir -p ${WEBUI_DIR}/src/static/js

# Download source files
DOWNLOAD_ERRORS=0
download_file() {
    local url="$1"
    local dest="$2"
    log "  Downloading $(basename ${dest})..."
    if ! wget -q "${url}" -O "${dest}"; then
        log_error "Failed to download: ${url}"
        ((DOWNLOAD_ERRORS++))
        return 1
    fi
}

# Root files
download_file "${WEBUI_BASE_URL}/Cargo.toml" "${WEBUI_DIR}/Cargo.toml"
download_file "${WEBUI_BASE_URL}/config.toml.example" "${WEBUI_DIR}/config.toml.example"

# Source files
download_file "${WEBUI_BASE_URL}/src/main.rs" "${WEBUI_DIR}/src/main.rs"
download_file "${WEBUI_BASE_URL}/src/config.rs" "${WEBUI_DIR}/src/config.rs"
download_file "${WEBUI_BASE_URL}/src/models.rs" "${WEBUI_DIR}/src/models.rs"
download_file "${WEBUI_BASE_URL}/src/access_log.rs" "${WEBUI_DIR}/src/access_log.rs"
download_file "${WEBUI_BASE_URL}/src/db.rs" "${WEBUI_DIR}/src/db.rs"
download_file "${WEBUI_BASE_URL}/src/auth.rs" "${WEBUI_DIR}/src/auth.rs"

# API modules
download_file "${WEBUI_BASE_URL}/src/api/mod.rs" "${WEBUI_DIR}/src/api/mod.rs"
download_file "${WEBUI_BASE_URL}/src/api/ckpool.rs" "${WEBUI_DIR}/src/api/ckpool.rs"
download_file "${WEBUI_BASE_URL}/src/api/aleo.rs" "${WEBUI_DIR}/src/api/aleo.rs"
download_file "${WEBUI_BASE_URL}/src/api/monero_pool.rs" "${WEBUI_DIR}/src/api/monero_pool.rs"
download_file "${WEBUI_BASE_URL}/src/api/tari.rs" "${WEBUI_DIR}/src/api/tari.rs"

# Static files (embedded into binary at compile time)
download_file "${WEBUI_BASE_URL}/src/static/index.html" "${WEBUI_DIR}/src/static/index.html"
download_file "${WEBUI_BASE_URL}/src/static/login.html" "${WEBUI_DIR}/src/static/login.html"
download_file "${WEBUI_BASE_URL}/src/static/css/style.css" "${WEBUI_DIR}/src/static/css/style.css"
download_file "${WEBUI_BASE_URL}/src/static/css/login.css" "${WEBUI_DIR}/src/static/css/login.css"
download_file "${WEBUI_BASE_URL}/src/static/js/app.js" "${WEBUI_DIR}/src/static/js/app.js"

# Check for download errors
if [ ${DOWNLOAD_ERRORS} -gt 0 ]; then
    log_error "Failed to download ${DOWNLOAD_ERRORS} file(s). Check SCRIPTS_BASE_URL in config."
    exit 1
fi

log "  Source downloaded"

# =============================================================================
# 3. VERIFY SOURCE
# =============================================================================
log "3. Verifying source code..."

if [ ! -d "${WEBUI_DIR}" ]; then
    log_error "WebUI source not found at ${WEBUI_DIR}"
    exit 1
fi

if [ ! -f "${WEBUI_DIR}/Cargo.toml" ]; then
    log_error "Invalid WebUI source - Cargo.toml not found"
    exit 1
fi

log "  Source verified at ${WEBUI_DIR}"

# =============================================================================
# 4. BUILD WEBUI FROM SOURCE
# =============================================================================
log "4. Building Solo Pool WebUI..."
log "  This may take 2-5 minutes depending on system..."

cd ${WEBUI_DIR}

# Clean any previous build artifacts
if [ -d "target" ]; then
    log "  Cleaning previous build..."
    cargo clean 2>/dev/null || true
fi

# Build release binary with optimizations
log "  Compiling release binary..."
CARGO_BUILD_START=$(date +%s)

# Use release profile for smaller, faster binary
run_cmd cargo build --release -j $(nproc)

CARGO_BUILD_END=$(date +%s)
CARGO_BUILD_TIME=$((CARGO_BUILD_END - CARGO_BUILD_START))
log "  Build completed in ${CARGO_BUILD_TIME} seconds"

# Verify binary was created
if [ ! -f "target/release/solo-pool-webui" ]; then
    log_error "Build failed - binary not found"
    exit 1
fi

# Get binary size for logging
BINARY_SIZE=$(du -h target/release/solo-pool-webui | cut -f1)
log "  Binary size: ${BINARY_SIZE}"

# =============================================================================
# 5. INSTALL WEBUI
# =============================================================================
log "5. Installing WebUI..."

# Create standardized directory structure
mkdir -p ${WEBUI_DIR}/bin
mkdir -p ${WEBUI_DIR}/config
mkdir -p ${WEBUI_DIR}/data
mkdir -p ${WEBUI_DIR}/logs
mkdir -p ${WEBUI_DIR}/certs

# Move binary to bin/
cp target/release/solo-pool-webui ${WEBUI_DIR}/bin/

# Strip debug symbols to reduce binary size (optional but recommended)
if command -v strip &> /dev/null; then
    strip ${WEBUI_DIR}/bin/solo-pool-webui 2>/dev/null || true
    STRIPPED_SIZE=$(du -h ${WEBUI_DIR}/bin/solo-pool-webui | cut -f1)
    log "  Binary stripped: ${STRIPPED_SIZE}"
fi

log "  WebUI installed to ${WEBUI_DIR}"

# =============================================================================
# 6. CLEANUP BUILD ARTIFACTS
# =============================================================================
log "6. Cleaning up build artifacts..."

# Remove target directory (can be several GB)
cd ${WEBUI_DIR}
if [ -d "target" ]; then
    TARGET_SIZE=$(du -sh target 2>/dev/null | cut -f1)
    log "  Removing build cache (${TARGET_SIZE})..."
    rm -rf target
fi

# Clean cargo registry cache for this project's dependencies
# Note: We keep the global cargo cache as other Rust projects may use it
log "  Build artifacts cleaned"

# Record disk space saved
log "  Disk space recovered from build cleanup"

# =============================================================================
# 7. GENERATE TLS CERTIFICATE (if HTTPS enabled)
# =============================================================================
CERT_DIR="${WEBUI_DIR}/certs"
CERT_FILE="${CERT_DIR}/server.crt"
KEY_FILE="${CERT_DIR}/server.key"

if [ "${WEBUI_HTTPS_ENABLED}" = "true" ]; then
    log "7. Generating self-signed TLS certificate..."

    # Get server IP addresses for certificate
    PUBLIC_IP=$(curl -s --connect-timeout 3 https://ifconfig.me 2>/dev/null || echo "")
    LOCAL_IP=$(hostname -I 2>/dev/null | awk '{print $1}' || echo "")

    # Build SAN list
    SAN_LIST="DNS:localhost,IP:127.0.0.1"
    [ -n "${LOCAL_IP}" ] && SAN_LIST="${SAN_LIST},IP:${LOCAL_IP}"
    [ -n "${PUBLIC_IP}" ] && [ "${PUBLIC_IP}" != "${LOCAL_IP}" ] && SAN_LIST="${SAN_LIST},IP:${PUBLIC_IP}"

    log "  Certificate SANs: ${SAN_LIST}"

    # Generate 10-year self-signed certificate
    openssl req -x509 -nodes -days 3650 \
        -newkey rsa:2048 \
        -keyout ${KEY_FILE} \
        -out ${CERT_FILE} \
        -subj "/C=US/ST=State/L=City/O=Solo Pool/OU=Mining/CN=solo-pool" \
        -addext "subjectAltName=${SAN_LIST}" \
        2>/dev/null

    # Set secure permissions on key file
    chmod 600 ${KEY_FILE}
    chmod 644 ${CERT_FILE}

    log "  TLS certificate generated (valid for 10 years)"
    log "  Certificate: ${CERT_FILE}"
    log "  Private key: ${KEY_FILE}"
else
    log "7. Skipping TLS certificate (HTTPS disabled)"
fi

# =============================================================================
# 8. GENERATE WEBUI CREDENTIALS
# =============================================================================
log "8. Generating WebUI credentials..."

# Generate password using apg (pronounceable, 16 characters)
WEBUI_PASS=$(apg -a 0 -M NCL -n 1 -m 16 -x 16 2>/dev/null || openssl rand -base64 16 | tr -dc 'a-zA-Z0-9' | head -c16)

# Write credentials file as bash-style variables
cat > ${CREDENTIALS_FILE} << EOF
# Solo Pool WebUI Credentials
# Auto-generated by install script - DO NOT SHARE
# Generated: $(date -u +"%Y-%m-%d %H:%M:%S UTC")

SOLO_POOL_WEBUI_USER="${WEBUI_USER}"
SOLO_POOL_WEBUI_PASS="${WEBUI_PASS}"
EOF

# Secure the credentials file
chmod 600 ${CREDENTIALS_FILE}
chown ${POOL_USER}:${POOL_USER} ${CREDENTIALS_FILE}

log "  Credentials generated"
log "  Username: ${WEBUI_USER}"
log "  Password: ${WEBUI_PASS}"
log "  Stored in: ${CREDENTIALS_FILE}"

# =============================================================================
# 9. CONFIGURE WEBUI
# =============================================================================
log "9. Configuring WebUI..."

# Generate config based on enabled pools and settings
cat > ${WEBUI_DIR}/config/config.toml << EOF
# Solo Pool WebUI Configuration
# Auto-generated by install script

[server]
host = "0.0.0.0"
port = ${WEBUI_HTTP_PORT}
refresh_interval_secs = ${WEBUI_REFRESH_INTERVAL:-15}
db_dir = "${WEBUI_DIR}/data"

[server.https]
enabled = ${WEBUI_HTTPS_ENABLED}
port = ${WEBUI_HTTPS_PORT}
cert_path = "${CERT_FILE}"
key_path = "${KEY_FILE}"

[server.logging]
log_dir = "${WEBUI_DIR}/logs"
access_log_enabled = true
error_log_enabled = true

# Payment processor API (for proxying payment requests)
payments_api_url = "http://127.0.0.1:${PAYMENTS_API_PORT:-8081}"
payments_api_token = "${PAYMENTS_API_TOKEN}"

[auth]
enabled = true
credentials_file = "${CREDENTIALS_FILE}"
session_timeout_secs = 86400
cookie_name = "solo_pool_session"
EOF

# Log HTTP/HTTPS configuration
if [ "${WEBUI_HTTP_ENABLED}" = "true" ]; then
    log "  HTTP enabled on port ${WEBUI_HTTP_PORT}"
fi
if [ "${WEBUI_HTTPS_ENABLED}" = "true" ]; then
    log "  HTTPS enabled on port ${WEBUI_HTTPS_PORT}"
fi

# Add Bitcoin pool if enabled
if [ "${ENABLE_BITCOIN_POOL}" = "true" ]; then
    cat >> ${WEBUI_DIR}/config/config.toml << EOF

[pools.btc]
enabled = true
name = "Bitcoin"
algorithm = "SHA-256"
socket_dir = "${BTC_CKPOOL_SOCKET_DIR:-/tmp/ckpool-btc}"
stratum_port = ${BTC_STRATUM_PORT:-3333}
username_format = "YOUR_BTC_ADDRESS.worker_name"
password = "x"
EOF
    log "  Bitcoin pool enabled"
fi

# Add BCH pool if enabled
if [ "${ENABLE_BCH_POOL}" = "true" ]; then
    cat >> ${WEBUI_DIR}/config/config.toml << EOF

[pools.bch]
enabled = true
name = "Bitcoin Cash"
algorithm = "SHA-256"
socket_dir = "${BCH_CKPOOL_SOCKET_DIR:-/tmp/ckpool-bch}"
stratum_port = ${BCH_STRATUM_PORT:-3334}
username_format = "YOUR_BCH_ADDRESS.worker_name"
password = "x"
EOF
    log "  Bitcoin Cash pool enabled"
fi

# Add DigiByte pool if enabled
if [ "${ENABLE_DGB_POOL}" = "true" ]; then
    cat >> ${WEBUI_DIR}/config/config.toml << EOF

[pools.dgb]
enabled = true
name = "DigiByte"
algorithm = "SHA-256"
socket_dir = "${DGB_CKPOOL_SOCKET_DIR:-/tmp/ckpool-dgb}"
stratum_port = ${DGB_STRATUM_PORT:-3335}
username_format = "YOUR_DGB_ADDRESS.worker_name"
password = "x"
EOF
    log "  DigiByte pool enabled"
fi

# Add Monero/Tari pools based on mode
if [ "${ENABLE_MONERO_TARI_POOL}" = "monero_only" ]; then
        # Read XMR pool wallet address if available
        XMR_POOL_ADDR=""
        if [ -f "${MONERO_DIR}/wallet/keys/pool-wallet.address" ]; then
            XMR_POOL_ADDR=$(cat "${MONERO_DIR}/wallet/keys/pool-wallet.address" 2>/dev/null | tr -d '\n' || echo "")
        fi

        cat >> ${WEBUI_DIR}/config/config.toml << EOF

[pools.xmr]
enabled = true
name = "Monero"
algorithm = "RandomX"
api_url = "http://127.0.0.1:${MONERO_POOL_API_PORT:-4243}"
stratum_port = ${XMR_STRATUM_PORT:-3336}
EOF
        # Add pool wallet address if available
        if [ -n "${XMR_POOL_ADDR}" ]; then
            echo "pool_wallet_address = \"${XMR_POOL_ADDR}\"" >> ${WEBUI_DIR}/config/config.toml
        fi
        cat >> ${WEBUI_DIR}/config/config.toml << EOF
username_format = "YOUR_XMR_ADDRESS.worker_name"
password = "x"
EOF
        log "  Monero monero-pool enabled"
        [ -n "${XMR_POOL_ADDR}" ] && log "  XMR pool wallet: ${XMR_POOL_ADDR:0:20}..."

elif [ "${ENABLE_MONERO_TARI_POOL}" = "tari_only" ]; then
        # Read XTM pool wallet address if available
        XTM_POOL_ADDR=""
        if [ -f "${TARI_DIR}/wallet/keys/pool-wallet.address" ]; then
            XTM_POOL_ADDR=$(cat "${TARI_DIR}/wallet/keys/pool-wallet.address" 2>/dev/null | tr -d '\n' || echo "")
        fi

        cat >> ${WEBUI_DIR}/config/config.toml << EOF

[pools.xtm]
enabled = true
name = "Tari"
algorithm = "RandomX"
api_url = "http://127.0.0.1:${XTM_STRATUM_PORT:-3337}"
stratum_port = ${XTM_STRATUM_PORT:-3337}
EOF
        # Add pool wallet address if available
        if [ -n "${XTM_POOL_ADDR}" ]; then
            echo "pool_wallet_address = \"${XTM_POOL_ADDR}\"" >> ${WEBUI_DIR}/config/config.toml
        fi
        cat >> ${WEBUI_DIR}/config/config.toml << EOF
username_format = "YOUR_XTM_ADDRESS.worker_name"
password = "x"
EOF
        log "  Tari solo mining enabled"
        [ -n "${XTM_POOL_ADDR}" ] && log "  XTM pool wallet: ${XTM_POOL_ADDR:0:20}..."

elif [ "${ENABLE_MONERO_TARI_POOL}" = "merge" ] || [ "${ENABLE_MONERO_TARI_POOL}" = "merged" ]; then
        # Read both XMR and XTM pool wallet addresses for merge mining
        XMR_POOL_ADDR=""
        XTM_POOL_ADDR=""
        if [ -f "${MONERO_DIR}/wallet/keys/pool-wallet.address" ]; then
            XMR_POOL_ADDR=$(cat "${MONERO_DIR}/wallet/keys/pool-wallet.address" 2>/dev/null | tr -d '\n' || echo "")
        fi
        if [ -f "${TARI_DIR}/wallet/keys/pool-wallet.address" ]; then
            XTM_POOL_ADDR=$(cat "${TARI_DIR}/wallet/keys/pool-wallet.address" 2>/dev/null | tr -d '\n' || echo "")
        fi

        cat >> ${WEBUI_DIR}/config/config.toml << EOF

[pools.xmr_xtm_merge]
enabled = true
name = "XMR+XTM Merge Mining"
algorithm = "RandomX"
api_url = "http://127.0.0.1:${XMR_XTM_MERGE_STRATUM_PORT:-3338}"
stratum_port = ${XMR_XTM_MERGE_STRATUM_PORT:-3338}
EOF
        # Add pool wallet addresses if available
        if [ -n "${XMR_POOL_ADDR}" ]; then
            echo "xmr_pool_wallet_address = \"${XMR_POOL_ADDR}\"" >> ${WEBUI_DIR}/config/config.toml
        fi
        if [ -n "${XTM_POOL_ADDR}" ]; then
            echo "xtm_pool_wallet_address = \"${XTM_POOL_ADDR}\"" >> ${WEBUI_DIR}/config/config.toml
        fi
        cat >> ${WEBUI_DIR}/config/config.toml << EOF
username_format = "YOUR_XMR_ADDRESS.worker_name"
password = "x"
EOF
        log "  XMR+XTM merge mining enabled"
        [ -n "${XMR_POOL_ADDR}" ] && log "  XMR pool wallet: ${XMR_POOL_ADDR:0:20}..."
        [ -n "${XTM_POOL_ADDR}" ] && log "  XTM pool wallet: ${XTM_POOL_ADDR:0:20}..."
fi

# Add ALEO pool if enabled
if [ "${ENABLE_ALEO_POOL}" = "true" ]; then
    # Read ALEO pool wallet address if available
    ALEO_POOL_ADDR=""
    if [ -f "${ALEO_DIR}/wallet/keys/pool-wallet.address" ]; then
        ALEO_POOL_ADDR=$(cat "${ALEO_DIR}/wallet/keys/pool-wallet.address" 2>/dev/null | tr -d '\n' || echo "")
    fi

    cat >> ${WEBUI_DIR}/config/config.toml << EOF

[pools.aleo]
enabled = true
name = "Aleo"
algorithm = "AleoBFT"
api_url = "http://127.0.0.1:${ALEO_STRATUM_PORT:-3339}"
stratum_port = ${ALEO_STRATUM_PORT:-3339}
EOF
    # Add pool wallet address if available
    if [ -n "${ALEO_POOL_ADDR}" ]; then
        echo "pool_wallet_address = \"${ALEO_POOL_ADDR}\"" >> ${WEBUI_DIR}/config/config.toml
    fi
    cat >> ${WEBUI_DIR}/config/config.toml << EOF
username_format = "YOUR_ALEO_ADDRESS.worker_name"
password = "x"
EOF
    log "  ALEO pool enabled"
    [ -n "${ALEO_POOL_ADDR}" ] && log "  ALEO pool wallet: ${ALEO_POOL_ADDR:0:20}..."
fi

log "  Configuration generated"

# =============================================================================
# 10. SET PERMISSIONS
# =============================================================================
# Note: Systemd service is created by 20-configure-services.sh using template
log "10. Setting permissions..."

chown -R ${POOL_USER}:${POOL_USER} ${WEBUI_DIR}
chmod 755 ${WEBUI_DIR}/bin/solo-pool-webui
chmod 644 ${WEBUI_DIR}/config/config.toml
# Ensure logs directory is writable
chmod 755 ${WEBUI_DIR}/logs
# Ensure data directory is writable (SQLite database)
chmod 755 ${WEBUI_DIR}/data
# Ensure certs directory and files have proper permissions
chmod 755 ${WEBUI_DIR}/certs

log "  Permissions set"

# =============================================================================
# 11. CONFIGURE FIREWALL
# =============================================================================
log "11. Configuring firewall..."

if [ "${WEBUI_HTTP_ENABLED}" = "true" ]; then
    ufw allow ${WEBUI_HTTP_PORT}/tcp comment "Solo Pool WebUI HTTP" >/dev/null 2>&1
    log "  Firewall rule added for HTTP port ${WEBUI_HTTP_PORT}"
fi

if [ "${WEBUI_HTTPS_ENABLED}" = "true" ]; then
    ufw allow ${WEBUI_HTTPS_PORT}/tcp comment "Solo Pool WebUI HTTPS" >/dev/null 2>&1
    log "  Firewall rule added for HTTPS port ${WEBUI_HTTPS_PORT}"
fi

# =============================================================================
# 12. CLEANUP WEBUI-ONLY BUILD DEPENDENCIES
# =============================================================================
log "12. Cleaning up build-only dependencies..."

# Note: We do NOT remove Rust here because:
# - ALEO (snarkOS, aleo-pool-server) requires Rust
# - Tari components require Rust
# - Future updates may need to rebuild
#
# If you want to remove Rust after ALL builds are complete, run:
#   rustup self uninstall
#
# The cargo cache can be cleaned with:
#   rm -rf ~/.cargo/registry/cache
#   rm -rf ~/.cargo/git/db

# Clean apt cache
apt-get clean >/dev/null 2>&1

log "  Cleanup complete"
log "  Note: Rust toolchain retained for other components"

# =============================================================================
# 13. CREATE SETUP NOTES
# =============================================================================
log "13. Creating setup notes..."

cat > ${WEBUI_DIR}/SETUP_NOTES.txt << EOF
Solo Pool Web UI Setup Notes
============================

The web dashboard is installed and configured.

AUTHENTICATION:
  Username: ${WEBUI_USER}
  Password: (see ${CREDENTIALS_FILE})

  To view your password:
    sudo cat ${CREDENTIALS_FILE}

ACCESS:
EOF

if [ "${WEBUI_HTTP_ENABLED}" = "true" ]; then
    echo "  HTTP:  http://YOUR_SERVER_IP:${WEBUI_HTTP_PORT}" >> ${WEBUI_DIR}/SETUP_NOTES.txt
fi
if [ "${WEBUI_HTTPS_ENABLED}" = "true" ]; then
    echo "  HTTPS: https://YOUR_SERVER_IP:${WEBUI_HTTPS_PORT}" >> ${WEBUI_DIR}/SETUP_NOTES.txt
    echo "  Note: Self-signed certificate - browser will show security warning" >> ${WEBUI_DIR}/SETUP_NOTES.txt
fi

cat >> ${WEBUI_DIR}/SETUP_NOTES.txt << EOF

DIRECTORIES:
  Runtime:  ${WEBUI_DIR}
  Binary:   ${WEBUI_DIR}/bin/solo-pool-webui (static files embedded)
  Config:   ${WEBUI_DIR}/config/config.toml
  Database: ${WEBUI_DIR}/data/stats.db (worker statistics)
  Logs:     ${WEBUI_DIR}/logs/

SYSTEMD SERVICE:
  Start:   sudo systemctl start solo-pool-webui
  Stop:    sudo systemctl stop solo-pool-webui
  Status:  sudo systemctl status solo-pool-webui
  Logs:    journalctl -u solo-pool-webui -f

CONFIGURATION:
  Edit ${WEBUI_DIR}/config/config.toml to change settings.
  Restart the service after changes.

API ENDPOINTS:
  Authentication:
  POST   /api/auth/login              - Login (username, password)
  POST   /api/auth/logout             - Logout
  GET    /api/auth/check              - Check authentication status

  Pool Stats:
  GET    /api/stats                   - All pool statistics (requires auth)
  GET    /api/stats/btc               - Bitcoin pool stats
  GET    /api/stats/bch               - Bitcoin Cash pool stats
  GET    /api/stats/dgb               - DigiByte pool stats
  GET    /api/stats/xmr               - Monero pool stats
  GET    /api/stats/xtm               - Tari solo mining stats
  GET    /api/stats/merge             - XMR+XTM merge mining stats
  GET    /api/stats/aleo              - ALEO pool stats
  DELETE /api/workers/:pool/:worker   - Delete worker from database

  Payment Processor (proxied):
  GET    /api/payments/stats              - All payment stats
  GET    /api/payments/stats/:coin        - Payment stats for specific coin
  GET    /api/payments/coin/:coin         - Recent payments for a coin
  GET    /api/payments/miner/:coin/:addr  - Miner balance and payment history

  Other:
  GET    /api/health                  - Health check (no auth)

LOGS:
  Access log: ${WEBUI_DIR}/logs/access.log (Apache Combined Log Format)
  Error log:  ${WEBUI_DIR}/logs/error.log

REBUILDING:
  If you need to rebuild the WebUI:
    cd ${WEBUI_DIR}
    source ~/.cargo/env
    cargo build --release
    cp target/release/solo-pool-webui bin/
    rm -rf target
    systemctl restart solo-pool-webui
EOF

# =============================================================================
# COMPLETE
# =============================================================================
log_success "Solo Pool WebUI installed successfully"
log ""
log "  AUTHENTICATION:"
log "    Username: ${WEBUI_USER}"
log "    Password: ${WEBUI_PASS}"
log "    Credentials file: ${CREDENTIALS_FILE}"
log ""
if [ "${WEBUI_HTTP_ENABLED}" = "true" ]; then
    log "  HTTP:  http://YOUR_SERVER_IP:${WEBUI_HTTP_PORT}"
fi
if [ "${WEBUI_HTTPS_ENABLED}" = "true" ]; then
    log "  HTTPS: https://YOUR_SERVER_IP:${WEBUI_HTTPS_PORT}"
fi
log ""
log "  Binary: ${WEBUI_DIR}/bin/solo-pool-webui"
log "  Config: ${WEBUI_DIR}/config/config.toml"
log "  Logs:   ${WEBUI_DIR}/logs/"
log ""
log "  Start the dashboard:"
log "    sudo systemctl start solo-pool-webui"
log ""
log "  View service logs:"
log "    journalctl -u solo-pool-webui -f"
log ""
log "  View access/error logs:"
log "    tail -f ${WEBUI_DIR}/logs/access.log"
log "    tail -f ${WEBUI_DIR}/logs/error.log"
