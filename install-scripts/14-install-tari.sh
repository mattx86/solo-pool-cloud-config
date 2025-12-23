#!/bin/bash
# =============================================================================
# 14-install-tari.sh
# Install Tari Node and Mining Software
#
# This installs:
# - minotari_node (Tari full node)
# - minotari_miner (solo Tari mining, tari_only mode)
# - minotari_merge_mining_proxy (Monero+Tari merge mining)
#
# Note: Rewards are sent to the wallet address configured in XTM_WALLET_ADDRESS.
# You can use your Tari Universe wallet address - no server-side wallet needed.
#
# Mode selection:
# - "merge": Uses minotari_merge_mining_proxy with monerod
# - "tari_only": Uses minotari_miner directly
# - "monero_only": Skips Tari entirely (handled in 13-install-monero.sh)
# =============================================================================

set -e

# Source configuration
source /opt/solo-pool/install-scripts/config.sh

# Validate config was loaded successfully
if [ "${CONFIG_LOADED:-}" != "true" ]; then
    echo "ERROR: Failed to load configuration from config.sh" >&2
    exit 1
fi

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

log "Installing Tari node and mining software v${TARI_VERSION}..."

# =============================================================================
# 1. DOWNLOAD TARI BINARIES
# =============================================================================
log "1. Downloading Tari binaries v${TARI_VERSION}..."

cd /tmp

# Download specific version
TARI_RELEASE_URL="https://github.com/tari-project/tari/releases/download/v${TARI_VERSION}/minotari_suite-linux-x86_64.tar.gz"

log "  Downloading from: ${TARI_RELEASE_URL}"
run_cmd wget -q "${TARI_RELEASE_URL}" -O tari.tar.gz

if [ $? -ne 0 ]; then
    log_error "Failed to download Tari v${TARI_VERSION}"
    exit 1
fi

# Extract
log "  Extracting..."
mkdir -p tari-extract
tar -xzf tari.tar.gz -C tari-extract

# Find and copy binaries (node, wallet, miner, and merge proxy)
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

# Determine P2P listen address based on inbound config
if [ "${ENABLE_INBOUND_P2P}" = "true" ]; then
    TARI_P2P_LISTEN="/ip4/0.0.0.0/tcp/18189"
else
    TARI_P2P_LISTEN="/ip4/127.0.0.1/tcp/18189"
fi

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
p2p_listen_address = "${TARI_P2P_LISTEN}"
enable_mining = false

# Database
db_type = "lmdb"
lmdb_path = "${TARI_DIR}/data/db"
pruned_mode_cleanup_interval = 50

# gRPC for wallet and mining
grpc_enabled = true
grpc_address = "127.0.0.1:${TARI_NODE_GRPC_PORT}"

[wallet]
grpc_enabled = true
grpc_address = "127.0.0.1:${TARI_WALLET_GRPC_PORT}"
password = "$(apg -a 1 -m 32 -M NCL -n 1)"
EOF

# Set permissions
chown -R ${POOL_USER}:${POOL_USER} ${TARI_DIR}
chmod 600 ${TARI_DIR}/config/config.toml

log "  Minotari node configured"

# =============================================================================
# 3. PREPARE POOL WALLET (actual creation happens after node sync)
# =============================================================================
log "3. Preparing Tari pool wallet..."

# Create wallet directory
mkdir -p ${TARI_DIR}/wallet
mkdir -p ${TARI_DIR}/wallet/data

# Generate a secure wallet password
XTM_WALLET_PASSWORD=$(apg -a 1 -m 32 -M NCL -n 1)

# Save the password securely
echo "${XTM_WALLET_PASSWORD}" > ${TARI_DIR}/wallet/pool-wallet.password
chmod 600 ${TARI_DIR}/wallet/pool-wallet.password

log "  Password generated and saved"

# Create wallet config for console wallet
cat > ${TARI_DIR}/wallet/config.toml << EOF
# Tari Pool Wallet Configuration

[wallet]
network = "mainnet"
grpc_enabled = true
grpc_address = "127.0.0.1:${TARI_WALLET_GRPC_PORT}"
base_node_grpc_address = "127.0.0.1:${TARI_NODE_GRPC_PORT}"
data_dir = "${TARI_DIR}/wallet/data"
password = "${XTM_WALLET_PASSWORD}"
EOF

chmod 600 ${TARI_DIR}/wallet/config.toml

# Create wallet start script
log "  Creating wallet start script..."
cat > ${TARI_DIR}/start-wallet.sh << EOF
#!/bin/bash
# Tari Wallet Start Script
# Runs minotari_console_wallet in daemon mode with gRPC enabled

PASSWORD=\$(cat ${TARI_DIR}/wallet/pool-wallet.password)

exec ${TARI_DIR}/bin/minotari_console_wallet \\
    --config ${TARI_DIR}/wallet/config.toml \\
    --password "\${PASSWORD}" \\
    --daemon
EOF

chmod +x ${TARI_DIR}/start-wallet.sh

# Create placeholder files (will be populated after node sync)
touch ${TARI_DIR}/wallet/pool-wallet.address
touch ${TARI_DIR}/wallet/SEED_BACKUP.txt
chmod 644 ${TARI_DIR}/wallet/pool-wallet.address
chmod 600 ${TARI_DIR}/wallet/SEED_BACKUP.txt

# Set ownership
chown -R ${POOL_USER}:${POOL_USER} ${TARI_DIR}/wallet
chown ${POOL_USER}:${POOL_USER} ${TARI_DIR}/start-wallet.sh

log_success "Pool wallet prepared"
log "  Wallet config: ${TARI_DIR}/wallet/config.toml"
log "  NOTE: Wallet will be initialized after node sync via start-xtm.sh"

# =============================================================================
# 4. CONFIGURE BASED ON MODE
# =============================================================================

if [ "${MONERO_TARI_MODE}" = "merge" ]; then
    # =============================================================================
    # MERGE MINING MODE
    # =============================================================================

    # Merge mining requires Monero pool to be enabled
    if [ "${ENABLE_MONERO_POOL}" != "true" ]; then
        log_error "Merge mining mode requires ENABLE_MONERO_POOL=true"
        log_error "Either enable Monero pool or use MONERO_TARI_MODE=tari_only"
        exit 1
    fi

    log "4. Configuring Merge Mining Proxy..."

    mkdir -p ${XMR_XTM_MERGE_DIR}/config

    # Create merge mining proxy config
    cat > ${XMR_XTM_MERGE_DIR}/config/config.toml << EOF
# Minotari Merge Mining Proxy Configuration

[merge_mining_proxy]
# Network
network = "mainnet"

# Stratum listener (miners connect here)
listener_address = "0.0.0.0:${XMR_XTM_MERGE_STRATUM_PORT}"

# Monero node connection
monerod_url = "http://127.0.0.1:${MONERO_RPC_PORT}"
monerod_username = ""
monerod_password = ""
monerod_use_auth = false

# Tari node connection (gRPC)
grpc_base_node_address = "127.0.0.1:${TARI_NODE_GRPC_PORT}"
grpc_console_wallet_address = "127.0.0.1:${TARI_WALLET_GRPC_PORT}"

# Wallet for Tari coinbase
# Use the pool wallet address from ${TARI_DIR}/wallet/pool-wallet.address
# or configure XTM_WALLET_ADDRESS in config.sh
wallet_payment_address = "${XTM_WALLET_ADDRESS}"

# Mining configuration
coinbase_extra = "Solo Pool Merge"
wait_for_initial_sync_at_startup = true

# Logging
log_path = "${XMR_XTM_MERGE_DIR}/logs"
EOF

    # Set permissions
    chown -R ${POOL_USER}:${POOL_USER} ${XMR_XTM_MERGE_DIR}
    chmod 600 ${XMR_XTM_MERGE_DIR}/config/config.toml

    log_success "Tari merge mining proxy configured"
    log "  Node: ${TARI_DIR}"
    log "  Merge Proxy: ${XMR_XTM_MERGE_DIR}"
    log "  Stratum port: ${XMR_XTM_MERGE_STRATUM_PORT}"
    log "  Miners connect to port ${XMR_XTM_MERGE_STRATUM_PORT} for XMR+XTM"

elif [ "${MONERO_TARI_MODE}" = "tari_only" ]; then
    # =============================================================================
    # TARI-ONLY MINING MODE
    # =============================================================================
    log "4. Configuring Minotari Miner (Tari-only)..."

    mkdir -p ${XTM_MINER_DIR}/config

    # Create miner config
    cat > ${XTM_MINER_DIR}/config/config.toml << EOF
# Minotari Miner Configuration (Solo Tari Mining)

[miner]
# Network
network = "mainnet"

# Base node connection
base_node_grpc_address = "127.0.0.1:${TARI_NODE_GRPC_PORT}"

# Wallet for receiving rewards
# Use the pool wallet address from ${TARI_DIR}/wallet/pool-wallet.address
# or configure XTM_WALLET_ADDRESS in config.sh
wallet_grpc_address = "127.0.0.1:${TARI_WALLET_GRPC_PORT}"
wallet_payment_address = "${XTM_WALLET_ADDRESS}"

# Mining configuration
num_mining_threads = 0  # 0 = auto-detect
mine_on_tip_only = true
validate_tip_timeout_sec = 30

# Stratum server (miners connect here)
stratum_enabled = true
stratum_listener_address = "0.0.0.0:${XTM_STRATUM_PORT}"

# Logging
log_path = "${XTM_MINER_DIR}/logs"
EOF

    # Set permissions
    chown -R ${POOL_USER}:${POOL_USER} ${XTM_MINER_DIR}
    chmod 600 ${XTM_MINER_DIR}/config/config.toml

    log_success "Tari miner configured"
    log "  Node: ${TARI_DIR}"
    log "  Miner: ${XTM_MINER_DIR}"
    log "  Stratum port: ${XTM_STRATUM_PORT}"

fi

# =============================================================================
# 5. WALLET SETUP INFO
# =============================================================================
log "5. Wallet setup info..."
log "  Pool wallet location: ${TARI_DIR}/wallet/"
log "  Configured payment address: ${XTM_WALLET_ADDRESS}"
log ""
log "  Wallet Initialization:"
log "    The wallet will be automatically initialized when the node is synced."
log "    Use start-xtm.sh or start-all.sh to start the node and initialize the wallet."
log ""
log "  After initialization:"
log "    Wallet address: cat ${TARI_DIR}/wallet/pool-wallet.address"
log "    Seed backup:    cat ${TARI_DIR}/wallet/SEED_BACKUP.txt"
log ""
log "  *** BACKUP SEED_BACKUP.txt immediately after initialization! ***"
