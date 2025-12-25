#!/bin/bash
# =============================================================================
# 17-install-payments.sh
# Install Solo Pool Payment Processor
#
# This service handles:
# - Tracking miner shares from pool APIs
# - Distributing block rewards proportionally to miners
# - Processing payments to miner wallet addresses
#
# Supported coins: XMR, XTM, ALEO
# (BTC/BCH/DGB use CKPool BTCSOLO mode - direct coinbase payouts)
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

# Check if payment processor is needed (only for XMR, XTM, ALEO)
NEED_PAYMENTS="false"
case "${ENABLE_MONERO_TARI_POOL}" in
    merge|merged|monero_only|tari_only) NEED_PAYMENTS="true" ;;
esac
[ "${ENABLE_ALEO_POOL}" = "true" ] && NEED_PAYMENTS="true"

if [ "${NEED_PAYMENTS}" != "true" ]; then
    log "Payment processor not needed (no XMR/XTM/ALEO pools enabled), skipping..."
    exit 0
fi

log "Installing Solo Pool Payment Processor..."

# Payments directory (use global config or default)
PAYMENTS_DIR="${PAYMENTS_DIR:-${BASE_DIR}/payments}"

# =============================================================================
# 1. INSTALL BUILD DEPENDENCIES
# =============================================================================
log "1. Installing build dependencies..."

# Check if Rust is installed
if [ -f "/root/.cargo/env" ]; then
    source /root/.cargo/env
    log "  Rust toolchain already installed"
else
    log "  Installing Rust toolchain..."
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable
    source /root/.cargo/env
    log "  Rust installed"
fi

# Install additional build dependencies if needed
REQUIRED_PKGS=""

if ! command -v pkg-config &> /dev/null; then
    REQUIRED_PKGS="${REQUIRED_PKGS} pkg-config"
fi

if [ ! -f "/usr/include/openssl/ssl.h" ]; then
    REQUIRED_PKGS="${REQUIRED_PKGS} libssl-dev"
fi

if [ -n "${REQUIRED_PKGS}" ]; then
    log "  Installing additional build packages: ${REQUIRED_PKGS}"
    apt-get update -qq
    apt-get install -y ${REQUIRED_PKGS}
fi

log "  Build dependencies ready"

# =============================================================================
# 2. DOWNLOAD PAYMENT PROCESSOR SOURCE FROM GITHUB
# =============================================================================
log "2. Downloading Payment Processor source from GitHub..."

# Base URL for raw files
PAYMENTS_BASE_URL="${SCRIPTS_BASE_URL%/install}/payments"

# Create standardized directory structure
mkdir -p ${PAYMENTS_DIR}/bin
mkdir -p ${PAYMENTS_DIR}/config
mkdir -p ${PAYMENTS_DIR}/data
mkdir -p ${PAYMENTS_DIR}/logs
mkdir -p ${PAYMENTS_DIR}/src/{wallets,pools}

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
download_file "${PAYMENTS_BASE_URL}/Cargo.toml" "${PAYMENTS_DIR}/Cargo.toml"
download_file "${PAYMENTS_BASE_URL}/config.toml.example" "${PAYMENTS_DIR}/config.toml.example"

# Source files
download_file "${PAYMENTS_BASE_URL}/src/main.rs" "${PAYMENTS_DIR}/src/main.rs"
download_file "${PAYMENTS_BASE_URL}/src/config.rs" "${PAYMENTS_DIR}/src/config.rs"
download_file "${PAYMENTS_BASE_URL}/src/db.rs" "${PAYMENTS_DIR}/src/db.rs"
download_file "${PAYMENTS_BASE_URL}/src/processor.rs" "${PAYMENTS_DIR}/src/processor.rs"
download_file "${PAYMENTS_BASE_URL}/src/api.rs" "${PAYMENTS_DIR}/src/api.rs"

# Wallet modules
download_file "${PAYMENTS_BASE_URL}/src/wallets/mod.rs" "${PAYMENTS_DIR}/src/wallets/mod.rs"
download_file "${PAYMENTS_BASE_URL}/src/wallets/monero.rs" "${PAYMENTS_DIR}/src/wallets/monero.rs"
download_file "${PAYMENTS_BASE_URL}/src/wallets/tari.rs" "${PAYMENTS_DIR}/src/wallets/tari.rs"
download_file "${PAYMENTS_BASE_URL}/src/wallets/aleo.rs" "${PAYMENTS_DIR}/src/wallets/aleo.rs"

# Pool API modules
download_file "${PAYMENTS_BASE_URL}/src/pools/mod.rs" "${PAYMENTS_DIR}/src/pools/mod.rs"
download_file "${PAYMENTS_BASE_URL}/src/pools/monero_pool.rs" "${PAYMENTS_DIR}/src/pools/monero_pool.rs"
download_file "${PAYMENTS_BASE_URL}/src/pools/tari.rs" "${PAYMENTS_DIR}/src/pools/tari.rs"
download_file "${PAYMENTS_BASE_URL}/src/pools/aleo.rs" "${PAYMENTS_DIR}/src/pools/aleo.rs"

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

if [ ! -f "${PAYMENTS_DIR}/Cargo.toml" ]; then
    log_error "Invalid Payment Processor source - Cargo.toml not found"
    exit 1
fi

log "  Source verified at ${PAYMENTS_DIR}"

# =============================================================================
# 4. BUILD PAYMENT PROCESSOR FROM SOURCE
# =============================================================================
log "4. Building Solo Pool Payment Processor..."
log "  This may take 2-5 minutes depending on system..."

cd ${PAYMENTS_DIR}

# Clean any previous build artifacts
if [ -d "target" ]; then
    log "  Cleaning previous build..."
    cargo clean 2>/dev/null || true
fi

# Build release binary
log "  Compiling release binary..."
CARGO_BUILD_START=$(date +%s)

run_cmd cargo build --release

CARGO_BUILD_END=$(date +%s)
CARGO_BUILD_TIME=$((CARGO_BUILD_END - CARGO_BUILD_START))
log "  Build completed in ${CARGO_BUILD_TIME} seconds"

# Verify binary was created
if [ ! -f "target/release/solo-pool-payments" ]; then
    log_error "Build failed - binary not found"
    exit 1
fi

BINARY_SIZE=$(du -h target/release/solo-pool-payments | cut -f1)
log "  Binary size: ${BINARY_SIZE}"

# =============================================================================
# 5. INSTALL PAYMENT PROCESSOR
# =============================================================================
log "5. Installing Payment Processor..."

# Move binary to bin/
cp target/release/solo-pool-payments ${PAYMENTS_DIR}/bin/

# Strip debug symbols
if command -v strip &> /dev/null; then
    strip ${PAYMENTS_DIR}/bin/solo-pool-payments 2>/dev/null || true
    STRIPPED_SIZE=$(du -h ${PAYMENTS_DIR}/bin/solo-pool-payments | cut -f1)
    log "  Binary stripped: ${STRIPPED_SIZE}"
fi

log "  Payment Processor installed to ${PAYMENTS_DIR}"

# =============================================================================
# 6. CLEANUP BUILD ARTIFACTS
# =============================================================================
log "6. Cleaning up build artifacts..."

cd ${PAYMENTS_DIR}
if [ -d "target" ]; then
    TARGET_SIZE=$(du -sh target 2>/dev/null | cut -f1)
    log "  Removing build cache (${TARGET_SIZE})..."
    rm -rf target
fi

# Remove source files (binary is standalone)
rm -rf src Cargo.toml Cargo.lock config.toml.example 2>/dev/null || true

log "  Build artifacts cleaned"

# =============================================================================
# 7. CONFIGURE PAYMENT PROCESSOR
# =============================================================================
log "7. Configuring Payment Processor..."

cat > ${PAYMENTS_DIR}/config/config.toml << EOF
# Solo Pool Payment Processor Configuration
# Auto-generated by install script

[service]
share_scan_interval_secs = 60
payment_interval_secs = 3600
log_level = "info"

[database]
path = "${PAYMENTS_DIR}/data/payments.db"

[api]
listen = "127.0.0.1"
port = ${PAYMENTS_API_PORT:-8081}
EOF

# Read API token (generated by webui install script)
PAYMENTS_API_TOKEN_FILE="${BASE_DIR}/.payments_api_token"
if [ -f "${PAYMENTS_API_TOKEN_FILE}" ]; then
    PAYMENTS_API_TOKEN=$(cat "${PAYMENTS_API_TOKEN_FILE}")
    log "  Using API token from ${PAYMENTS_API_TOKEN_FILE}"
else
    # Generate if not exists (webui not installed)
    PAYMENTS_API_TOKEN=$(openssl rand -hex 32)
    echo "${PAYMENTS_API_TOKEN}" > "${PAYMENTS_API_TOKEN_FILE}"
    chmod 600 "${PAYMENTS_API_TOKEN_FILE}"
    chown ${POOL_USER}:${POOL_USER} "${PAYMENTS_API_TOKEN_FILE}"
    log "  Generated API token: ${PAYMENTS_API_TOKEN_FILE}"
fi

# Add API token to payments config
cat >> ${PAYMENTS_DIR}/config/config.toml << EOF
token = "${PAYMENTS_API_TOKEN}"
EOF

# Add XMR configuration based on mode
# - monero_only: XMR via monero-pool API (MONERO_POOL_API_PORT)
# - merge/merged: XMR via merge mining proxy API (MERGE_PROXY_API_PORT)
# - tari_only: No XMR
if [ "${ENABLE_MONERO_TARI_POOL}" = "monero_only" ] || [ "${ENABLE_MONERO_TARI_POOL}" = "merge" ] || [ "${ENABLE_MONERO_TARI_POOL}" = "merged" ]; then
    if [ "${ENABLE_MONERO_TARI_POOL}" = "monero_only" ]; then
        # monero-pool mode - use monero-pool API
        XMR_POOL_API_URL="http://127.0.0.1:${MONERO_POOL_API_PORT}"
        XMR_POOL_DATA="${XMR_MONERO_POOL_DIR:-${POOL_DIR}/xmr-monero-pool}/data"
        XMR_POOL_TYPE="monero_pool"
    else
        # Merge mode - use merge mining proxy API
        XMR_POOL_API_URL="http://127.0.0.1:${MERGE_PROXY_API_PORT}"
        XMR_POOL_DATA="${XMR_XTM_MERGE_DIR:-${POOL_DIR}/xmr-xtm-minotari-merge-proxy}/data"
        XMR_POOL_TYPE="merge_proxy"
    fi

    # Read pool wallet address from generated wallet file
    XMR_POOL_WALLET_ADDRESS_FILE="${MONERO_DIR}/wallet/keys/pool-wallet.address"
    if [ -f "${XMR_POOL_WALLET_ADDRESS_FILE}" ] && [ -s "${XMR_POOL_WALLET_ADDRESS_FILE}" ]; then
        XMR_POOL_WALLET_ADDRESS=$(cat "${XMR_POOL_WALLET_ADDRESS_FILE}")
        log "  Using generated XMR pool wallet: ${XMR_POOL_WALLET_ADDRESS:0:20}..."
    else
        log_error "XMR pool wallet not found: ${XMR_POOL_WALLET_ADDRESS_FILE}"
        log_error "This file should have been created by 13-install-monero.sh"
        exit 1
    fi

    cat >> ${PAYMENTS_DIR}/config/config.toml << EOF

[xmr]
enabled = true
# Pool wallet address (generated during installation)
pool_wallet_address = "${XMR_POOL_WALLET_ADDRESS}"
wallet_rpc_url = "http://127.0.0.1:${MONERO_WALLET_RPC_PORT}/json_rpc"
pool_api_url = "${XMR_POOL_API_URL}"
pool_data_path = "${XMR_POOL_DATA}"
pool_type = "${XMR_POOL_TYPE}"
min_payout = "1"
mixin = 16
EOF
    log "  XMR payment config added (mode: ${ENABLE_MONERO_TARI_POOL}, pool_type: ${XMR_POOL_TYPE})"
fi

# Add XTM configuration based on mode
# - merge/merged: XTM via merge mining proxy API (MERGE_PROXY_API_PORT)
# - tari_only: XTM via minotari_miner API (TARI_MINER_API_PORT)
# - monero_only: No XTM
if [ "${ENABLE_MONERO_TARI_POOL}" = "merge" ] || [ "${ENABLE_MONERO_TARI_POOL}" = "merged" ] || [ "${ENABLE_MONERO_TARI_POOL}" = "tari_only" ]; then
    # Read pool wallet address from generated wallet file
    XTM_POOL_WALLET_ADDRESS_FILE="${TARI_DIR}/wallet/keys/pool-wallet.address"
    if [ -f "${XTM_POOL_WALLET_ADDRESS_FILE}" ] && [ -s "${XTM_POOL_WALLET_ADDRESS_FILE}" ]; then
        XTM_POOL_WALLET_ADDRESS=$(cat "${XTM_POOL_WALLET_ADDRESS_FILE}")
        log "  Using generated XTM pool wallet: ${XTM_POOL_WALLET_ADDRESS:0:20}..."
    else
        log_error "XTM pool wallet not found: ${XTM_POOL_WALLET_ADDRESS_FILE}"
        log_error "This file should have been created by 14-install-tari.sh"
        exit 1
    fi

    if [ "${ENABLE_MONERO_TARI_POOL}" = "merge" ] || [ "${ENABLE_MONERO_TARI_POOL}" = "merged" ]; then
        cat >> ${PAYMENTS_DIR}/config/config.toml << EOF

[xtm]
enabled = true
# Pool wallet address (from ${TARI_DIR}/wallet/keys/pool-wallet.address)
pool_wallet_address = "${XTM_POOL_WALLET_ADDRESS}"
wallet_rpc_url = "http://127.0.0.1:${TARI_WALLET_GRPC_PORT}"
pool_api_url = "http://127.0.0.1:${MERGE_PROXY_API_PORT}"
pool_data_path = "${XMR_XTM_MERGE_DIR:-${POOL_DIR}/xmr-xtm-minotari-merge-proxy}/data"
pool_type = "merge_proxy"
min_payout = "1"
EOF
        log "  XTM payment config added (merge mining mode)"
    elif [ "${ENABLE_MONERO_TARI_POOL}" = "tari_only" ]; then
        cat >> ${PAYMENTS_DIR}/config/config.toml << EOF

[xtm]
enabled = true
# Pool wallet address (from ${TARI_DIR}/wallet/keys/pool-wallet.address)
pool_wallet_address = "${XTM_POOL_WALLET_ADDRESS}"
wallet_rpc_url = "http://127.0.0.1:${TARI_WALLET_GRPC_PORT}"
pool_api_url = "http://127.0.0.1:${TARI_MINER_API_PORT}"
pool_data_path = "${XTM_MINER_DIR:-${POOL_DIR}/xtm-minotari-miner}/data"
pool_type = "minotari_miner"
min_payout = "1"
EOF
        log "  XTM payment config added (tari_only mode via minotari_miner)"
    fi
fi

# Add ALEO configuration if enabled
if [ "${ENABLE_ALEO_POOL}" = "true" ]; then
    # Read pool wallet address and private key from generated wallet files
    ALEO_POOL_WALLET_ADDRESS_FILE="${ALEO_DIR}/wallet/keys/pool-wallet.address"
    ALEO_POOL_PRIVATE_KEY_FILE="${ALEO_DIR}/wallet/keys/pool-wallet.privatekey"

    if [ -f "${ALEO_POOL_WALLET_ADDRESS_FILE}" ] && [ -s "${ALEO_POOL_WALLET_ADDRESS_FILE}" ]; then
        ALEO_POOL_WALLET_ADDRESS=$(cat "${ALEO_POOL_WALLET_ADDRESS_FILE}")
        log "  Using generated ALEO pool wallet: ${ALEO_POOL_WALLET_ADDRESS:0:30}..."
    else
        log_error "ALEO pool wallet not found: ${ALEO_POOL_WALLET_ADDRESS_FILE}"
        log_error "This file should have been created by 15-install-aleo.sh"
        exit 1
    fi

    if [ -f "${ALEO_POOL_PRIVATE_KEY_FILE}" ] && [ -s "${ALEO_POOL_PRIVATE_KEY_FILE}" ]; then
        ALEO_POOL_PRIVATE_KEY=$(cat "${ALEO_POOL_PRIVATE_KEY_FILE}")
        log "  Using generated ALEO private key"
    else
        log_error "ALEO private key not found: ${ALEO_POOL_PRIVATE_KEY_FILE}"
        log_error "This file should have been created by 15-install-aleo.sh"
        exit 1
    fi

    cat >> ${PAYMENTS_DIR}/config/config.toml << EOF

[aleo]
enabled = true
# Pool wallet address (generated during installation)
pool_wallet_address = "${ALEO_POOL_WALLET_ADDRESS}"
# Pool private key (from ${ALEO_DIR}/wallet/keys/pool-wallet.privatekey)
pool_private_key = "${ALEO_POOL_PRIVATE_KEY}"
node_rpc_url = "http://127.0.0.1:${ALEO_RPC_PORT}"
pool_api_url = "http://127.0.0.1:${ALEO_POOL_API_PORT}"
pool_data_path = "${ALEO_POOL_DIR:-${POOL_DIR}/aleo-pool-server}/data"
min_payout = "1"
EOF
    log "  ALEO payment config added"
fi

log "  Configuration generated"

# =============================================================================
# 8. SET PERMISSIONS
# =============================================================================
# Note: Systemd service is created by 20-configure-services.sh using template
log "8. Setting permissions..."

chown -R ${POOL_USER}:${POOL_USER} ${PAYMENTS_DIR}
chmod 755 ${PAYMENTS_DIR}/bin/solo-pool-payments
chmod 600 ${PAYMENTS_DIR}/config/config.toml
chmod 755 ${PAYMENTS_DIR}/logs
chmod 755 ${PAYMENTS_DIR}/data

log "  Permissions set"

# =============================================================================
# 9. CREATE SETUP NOTES
# =============================================================================
log "9. Creating setup notes..."

cat > ${PAYMENTS_DIR}/SETUP_NOTES.txt << EOF
Solo Pool Payment Processor Setup Notes
=======================================

The payment processor tracks miner shares and distributes block rewards
proportionally to miners' wallet addresses.

SUPPORTED COINS:
  - XMR (Monero) via monero-pool
  - XTM (Tari) via merge mining proxy
  - ALEO via pool server

Note: BTC/BCH/DGB use CKPool BTCSOLO mode where rewards go directly
to the miner's wallet address (specified in stratum username).

DIRECTORIES:
  Binary:   ${PAYMENTS_DIR}/bin/solo-pool-payments
  Config:   ${PAYMENTS_DIR}/config/config.toml
  Database: ${PAYMENTS_DIR}/data/
  Logs:     ${PAYMENTS_DIR}/logs/

SYSTEMD SERVICE:
  Start:   sudo systemctl start solo-pool-payments
  Stop:    sudo systemctl stop solo-pool-payments
  Status:  sudo systemctl status solo-pool-payments
  Logs:    journalctl -u solo-pool-payments -f

CONFIGURATION:
  Edit ${PAYMENTS_DIR}/config/config.toml to:
  - Verify wallet addresses (auto-generated during install)
  - Adjust minimum payout thresholds

API AUTHENTICATION:
  The API is protected by bearer token authentication.
  Token file: ${BASE_DIR}/.payments_api_token

  All endpoints except /api/health require the Authorization header:
    curl -H "Authorization: Bearer \$(cat ${BASE_DIR}/.payments_api_token)" \\
         http://127.0.0.1:${PAYMENTS_API_PORT:-8081}/api/stats

  The WebUI proxies authenticated requests to this API automatically.

API ENDPOINTS:
  GET /api/health                    - Health check (no auth required)
  GET /api/stats                     - All payment stats
  GET /api/stats/:coin               - Stats for specific coin
  GET /api/miner/:coin/:address      - Miner balance and history
  GET /api/payments/:coin            - Recent payments
  GET /api/payments/:coin/:address   - Miner payment history

POOL WALLETS (AUTO-GENERATED):
  All pool wallets are automatically generated during installation.
  - XMR: ${MONERO_DIR}/wallet/keys/
  - XTM: ${TARI_DIR}/wallet/keys/
  - ALEO: ${ALEO_DIR}/wallet/keys/

*** BACKUP ALL WALLET KEYS IMMEDIATELY! ***
EOF

# =============================================================================
# COMPLETE
# =============================================================================
log_success "Solo Pool Payment Processor installed successfully"
log ""
log "  Binary:   ${PAYMENTS_DIR}/bin/solo-pool-payments"
log "  Config:   ${PAYMENTS_DIR}/config/config.toml"
log "  Database: ${PAYMENTS_DIR}/data/"
log "  Logs:     ${PAYMENTS_DIR}/logs/"
log ""
log "  Start the service:"
log "    sudo systemctl start solo-pool-payments"
log ""
log "  View service logs:"
log "    journalctl -u solo-pool-payments -f"
log ""
log "  *** BACKUP ALL POOL WALLET KEYS IMMEDIATELY! ***"
log ""
