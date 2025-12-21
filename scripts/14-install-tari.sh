#!/bin/bash
# =============================================================================
# 14-install-tari.sh
# Install Tari Node and Mining Software
#
# This installs:
# - minotari_node (Tari full node)
# - minotari_miner (solo Tari mining)
# - minotari_merge_mining_proxy (Monero+Tari merge mining)
# - minotari_console_wallet (wallet for receiving rewards)
#
# Mode selection:
# - "merge": Uses minotari_merge_mining_proxy with monerod
# - "tari_only": Uses minotari_miner directly
# - "monero_only": Skips Tari entirely (handled in 13-install-monero.sh)
# =============================================================================

set -e

# Source configuration
source /opt/solo-pool/config.sh

# Check if Tari pool is enabled
if [ "${ENABLE_TARI_POOL}" != "true" ]; then
    log "Tari pool is disabled, skipping..."
    exit 0
fi

# Check mode - skip if monero_only
if [ "${MONERO_TARI_MODE}" = "monero_only" ]; then
    log "Monero-only mode, skipping Tari installation..."
    exit 0
fi

log "Installing Tari node and mining software..."

# =============================================================================
# 1. DOWNLOAD TARI BINARIES
# =============================================================================
log "1. Downloading Tari binaries..."

cd /tmp

# Get latest release from GitHub
log "  Fetching latest Tari release..."
TARI_RELEASE_URL=$(curl -s https://api.github.com/repos/tari-project/tari/releases/latest | \
    jq -r '.assets[] | select(.name | contains("linux-x86_64")) | select(.name | contains(".tar.gz")) | .browser_download_url' | head -1)

if [ -z "${TARI_RELEASE_URL}" ]; then
    log_error "Could not find Tari release URL"
    # Fallback to a known version
    TARI_RELEASE_URL="https://github.com/tari-project/tari/releases/latest/download/minotari_suite-linux-x86_64.tar.gz"
fi

log "  Downloading from: ${TARI_RELEASE_URL}"
run_cmd wget -q "${TARI_RELEASE_URL}" -O tari.tar.gz

# Extract
log "  Extracting..."
mkdir -p tari-extract
tar -xzf tari.tar.gz -C tari-extract

# Find and copy binaries
log "  Installing binaries..."
find tari-extract -type f -executable -name "minotari_*" -exec cp {} ${TARI_DIR}/bin/ \;

# Make executable
chmod +x ${TARI_DIR}/bin/*

# Cleanup
rm -rf tari.tar.gz tari-extract

log "  Tari binaries installed"

# =============================================================================
# 2. CONFIGURE MINOTARI NODE
# =============================================================================
log "2. Configuring Minotari Node..."

# Create base config directory
mkdir -p ${TARI_DIR}/config

# Create config.toml for minotari_node
cat > ${TARI_DIR}/config/config.toml << EOF
# Minotari Node Configuration

[common]
# Base path for data
base_path = "${TARI_DIR}/data"

[base_node]
# Network (mainnet, stagenet, nextnet)
network = "mainnet"

# P2P configuration
p2p_listen_address = "/ip4/0.0.0.0/tcp/18189"
enable_mining = false

# Database
db_type = "lmdb"
lmdb_path = "${TARI_DIR}/data/db"
pruned_mode_cleanup_interval = 50

# gRPC for wallet and mining
grpc_enabled = true
grpc_address = "127.0.0.1:18142"

[wallet]
grpc_enabled = true
grpc_address = "127.0.0.1:18143"
password = "$(openssl rand -hex 16)"
EOF

# Set permissions
chown -R ${POOL_USER}:${POOL_USER} ${TARI_DIR}
chmod 600 ${TARI_DIR}/config/config.toml

log "  Minotari node configured"

# =============================================================================
# 3. CONFIGURE BASED ON MODE
# =============================================================================

if [ "${MONERO_TARI_MODE}" = "merge" ]; then
    # =============================================================================
    # MERGE MINING MODE
    # =============================================================================
    log "3. Configuring Merge Mining Proxy..."

    mkdir -p ${TARI_MERGE_DIR}/config

    # Create merge mining proxy config
    cat > ${TARI_MERGE_DIR}/config/config.toml << EOF
# Minotari Merge Mining Proxy Configuration

[merge_mining_proxy]
# Network
network = "mainnet"

# Stratum listener (miners connect here)
listener_address = "0.0.0.0:${MERGE_STRATUM_PORT}"

# Monero node connection
monerod_url = "http://127.0.0.1:18081"
monerod_username = ""
monerod_password = ""
monerod_use_auth = false

# Tari node connection (gRPC)
grpc_base_node_address = "127.0.0.1:18142"
grpc_console_wallet_address = "127.0.0.1:18143"

# Wallet for Tari coinbase
wallet_payment_address = "${XTM_WALLET_ADDRESS}"

# Mining configuration
coinbase_extra = "Solo Pool Merge"
wait_for_initial_sync_at_startup = true

# Logging
log_path = "${TARI_MERGE_DIR}/logs"
EOF

    # Set permissions
    chown -R ${POOL_USER}:${POOL_USER} ${TARI_MERGE_DIR}
    chmod 600 ${TARI_MERGE_DIR}/config/config.toml

    log_success "Tari merge mining proxy configured"
    log "  Node: ${TARI_DIR}"
    log "  Merge Proxy: ${TARI_MERGE_DIR}"
    log "  Stratum port: ${MERGE_STRATUM_PORT}"
    log "  Miners connect to port ${MERGE_STRATUM_PORT} for XMR+XTM"

elif [ "${MONERO_TARI_MODE}" = "tari_only" ]; then
    # =============================================================================
    # TARI-ONLY MINING MODE
    # =============================================================================
    log "3. Configuring Minotari Miner (Tari-only)..."

    mkdir -p ${TARI_MINER_DIR}/config

    # Create miner config
    cat > ${TARI_MINER_DIR}/config/config.toml << EOF
# Minotari Miner Configuration (Solo Tari Mining)

[miner]
# Network
network = "mainnet"

# Base node connection
base_node_grpc_address = "127.0.0.1:18142"

# Wallet for receiving rewards
wallet_grpc_address = "127.0.0.1:18143"
wallet_payment_address = "${XTM_WALLET_ADDRESS}"

# Mining configuration
num_mining_threads = 0  # 0 = auto-detect
mine_on_tip_only = true
validate_tip_timeout_sec = 30

# Stratum server (miners connect here)
stratum_enabled = true
stratum_listener_address = "0.0.0.0:${XTM_STRATUM_PORT}"

# Logging
log_path = "${TARI_MINER_DIR}/logs"
EOF

    # Set permissions
    chown -R ${POOL_USER}:${POOL_USER} ${TARI_MINER_DIR}
    chmod 600 ${TARI_MINER_DIR}/config/config.toml

    log_success "Tari miner configured"
    log "  Node: ${TARI_DIR}"
    log "  Miner: ${TARI_MINER_DIR}"
    log "  Stratum port: ${XTM_STRATUM_PORT}"

fi

# =============================================================================
# 4. CREATE WALLET (if needed)
# =============================================================================
log "4. Wallet setup notes..."
log "  A Tari wallet will be created on first run if needed"
log "  You can also import an existing wallet"
log "  Wallet address: ${XTM_WALLET_ADDRESS}"
