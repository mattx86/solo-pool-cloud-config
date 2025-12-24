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
# Note: A pool wallet is auto-generated during install. Rewards go to this wallet
# and the payment processor distributes to miners based on their shares.
#
# Mode selection:
# - "merge": Uses minotari_merge_mining_proxy with monerod
# - "tari_only": Uses minotari_miner directly
# - "monero_only": Skips Tari entirely (handled in 13-install-monero.sh)
# =============================================================================

set -e

# Source configuration
source /opt/solo-pool/install/config.sh

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

# Template directory
TEMPLATE_DIR="/opt/solo-pool/install/files/config"

# =============================================================================
# 1. DOWNLOAD TARI BINARIES
# =============================================================================
log "1. Downloading Tari binaries v${TARI_VERSION}..."

# Create standardized directory structure
log "  Creating directory structure..."
mkdir -p ${TARI_DIR}/bin
mkdir -p ${TARI_DIR}/config
mkdir -p ${TARI_DIR}/data
mkdir -p ${TARI_DIR}/logs

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
    export TARI_P2P_LISTEN="/ip4/0.0.0.0/tcp/18189"
else
    export TARI_P2P_LISTEN="/ip4/127.0.0.1/tcp/18189"
fi

# Generate password for node's internal wallet
export XTM_NODE_WALLET_PASSWORD=$(apg -a 1 -m 32 -M NCL -n 1)

# Export variables for template
export TARI_DIR TARI_NODE_GRPC_PORT TARI_WALLET_GRPC_PORT

# Generate config from template
log "  Creating minotari node configuration from template..."
envsubst < "${TEMPLATE_DIR}/tari-node.toml.template" > ${TARI_DIR}/config/config.toml

# Set permissions
chown -R ${POOL_USER}:${POOL_USER} ${TARI_DIR}
chmod 600 ${TARI_DIR}/config/config.toml

log "  Minotari node configured"

# =============================================================================
# 3. GENERATE POOL WALLET
# =============================================================================
log "3. Generating Tari pool wallet..."

# Create standardized wallet directory structure
mkdir -p ${TARI_DIR}/wallet/keys
mkdir -p ${TARI_DIR}/wallet/config
mkdir -p ${TARI_DIR}/wallet/data
mkdir -p ${TARI_DIR}/wallet/logs

# Generate a secure wallet password
export XTM_WALLET_PASSWORD=$(apg -a 1 -m 32 -M NCL -n 1)

# Save the password securely
echo "${XTM_WALLET_PASSWORD}" > ${TARI_DIR}/wallet/keys/pool-wallet.password
chmod 600 ${TARI_DIR}/wallet/keys/pool-wallet.password

log "  Password generated and saved"

# Create wallet config from template
log "  Creating wallet configuration from template..."
envsubst < "${TEMPLATE_DIR}/tari-wallet.toml.template" > ${TARI_DIR}/wallet/config/config.toml
chmod 600 ${TARI_DIR}/wallet/config/config.toml

# Create wallet start script from template
log "  Creating wallet start script from template..."
envsubst < "${TEMPLATE_DIR}/start-tari-wallet.sh.template" > ${TARI_DIR}/bin/start-wallet.sh
chmod +x ${TARI_DIR}/bin/start-wallet.sh

# Initialize the wallet to generate keys (non-interactive mode)
log "  Initializing wallet..."
cd ${TARI_DIR}/wallet

# Run wallet init command to generate new wallet
# Note: --init creates a new wallet, --create-id generates the identity
WALLET_OUTPUT=$(${TARI_DIR}/bin/minotari_console_wallet \
    --base-path ${TARI_DIR}/wallet/data \
    --config ${TARI_DIR}/wallet/config/config.toml \
    --password "${XTM_WALLET_PASSWORD}" \
    --non-interactive \
    --init \
    --create-id 2>&1 || true)

# Extract wallet address from output
# The wallet outputs the address when initialized
XTM_POOL_ADDRESS=$(echo "${WALLET_OUTPUT}" | grep -oP 'f[a-zA-Z0-9]{64,}' | head -1)

# If not found in output, try to get it from the wallet
if [ -z "${XTM_POOL_ADDRESS}" ]; then
    # Run wallet to get address
    XTM_POOL_ADDRESS=$(${TARI_DIR}/bin/minotari_console_wallet \
        --base-path ${TARI_DIR}/wallet/data \
        --config ${TARI_DIR}/wallet/config/config.toml \
        --password "${XTM_WALLET_PASSWORD}" \
        --non-interactive \
        --command "get-balance" 2>&1 | grep -oP 'f[a-zA-Z0-9]{64,}' | head -1 || true)
fi

# Export for use in templates
export XTM_WALLET_ADDRESS="${XTM_POOL_ADDRESS}"

if [ -z "${XTM_WALLET_ADDRESS}" ]; then
    log_error "Failed to extract wallet address from wallet initialization"
    log_error "Wallet output: ${WALLET_OUTPUT}"
    # Set a placeholder - wallet will be properly initialized at first startup
    XTM_WALLET_ADDRESS="WALLET_INITIALIZATION_PENDING"
    log "  Wallet will be fully initialized at first startup via start-xtm.sh"
fi

# Save the wallet address
echo "${XTM_WALLET_ADDRESS}" > ${TARI_DIR}/wallet/keys/pool-wallet.address
chmod 644 ${TARI_DIR}/wallet/keys/pool-wallet.address

# Try to extract seed words if available
SEED_WORDS=$(echo "${WALLET_OUTPUT}" | grep -A24 "seed words" | tail -24 | tr '\n' ' ' || true)
if [ -n "${SEED_WORDS}" ]; then
    echo "${SEED_WORDS}" > ${TARI_DIR}/wallet/keys/SEED_BACKUP.txt
    chmod 600 ${TARI_DIR}/wallet/keys/SEED_BACKUP.txt
    log "  Seed words saved to SEED_BACKUP.txt"
else
    touch ${TARI_DIR}/wallet/keys/SEED_BACKUP.txt
    chmod 600 ${TARI_DIR}/wallet/keys/SEED_BACKUP.txt
    log "  NOTE: Seed words will be available after first wallet connection"
fi

# Mark wallet as initialized
touch ${TARI_DIR}/wallet/keys/.initialized

# Set ownership
chown -R ${POOL_USER}:${POOL_USER} ${TARI_DIR}/wallet

log_success "Pool wallet generated"
log "  Wallet address: ${XTM_WALLET_ADDRESS}"
log "  Wallet config: ${TARI_DIR}/wallet/config/config.toml"
log "  *** BACKUP ${TARI_DIR}/wallet/keys/ IMMEDIATELY! ***"

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

    # Create standardized directory structure
    mkdir -p ${XMR_XTM_MERGE_DIR}/bin
    mkdir -p ${XMR_XTM_MERGE_DIR}/config
    mkdir -p ${XMR_XTM_MERGE_DIR}/data
    mkdir -p ${XMR_XTM_MERGE_DIR}/logs

    # Export variables for template
    export XMR_XTM_MERGE_STRATUM_PORT MONERO_RPC_PORT XTM_WALLET_ADDRESS XMR_XTM_MERGE_DIR
    export TARI_NODE_GRPC_PORT TARI_WALLET_GRPC_PORT

    # Create merge mining proxy config from template
    log "  Creating merge mining proxy configuration from template..."
    envsubst < "${TEMPLATE_DIR}/tari-merge-proxy.toml.template" > ${XMR_XTM_MERGE_DIR}/config/config.toml

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

    # Create standardized directory structure
    mkdir -p ${XTM_MINER_DIR}/bin
    mkdir -p ${XTM_MINER_DIR}/config
    mkdir -p ${XTM_MINER_DIR}/data
    mkdir -p ${XTM_MINER_DIR}/logs

    # Export variables for template
    export XTM_STRATUM_PORT XTM_WALLET_ADDRESS XTM_MINER_DIR
    export TARI_NODE_GRPC_PORT TARI_WALLET_GRPC_PORT

    # Create miner config from template
    log "  Creating miner configuration from template..."
    envsubst < "${TEMPLATE_DIR}/tari-miner.toml.template" > ${XTM_MINER_DIR}/config/config.toml

    # Set permissions
    chown -R ${POOL_USER}:${POOL_USER} ${XTM_MINER_DIR}
    chmod 600 ${XTM_MINER_DIR}/config/config.toml

    log_success "Tari miner configured"
    log "  Node: ${TARI_DIR}"
    log "  Miner: ${XTM_MINER_DIR}"
    log "  Stratum port: ${XTM_STRATUM_PORT}"

fi

# =============================================================================
# 5. FINAL SUMMARY
# =============================================================================
log "5. Installation summary..."
log "  Pool wallet location: ${TARI_DIR}/wallet/"
log "  Pool wallet address: ${XTM_WALLET_ADDRESS}"
log ""
log "  Wallet files:"
log "    Address:  ${TARI_DIR}/wallet/keys/pool-wallet.address"
log "    Seed:     ${TARI_DIR}/wallet/keys/SEED_BACKUP.txt"
log "    Password: ${TARI_DIR}/wallet/keys/pool-wallet.password"
log ""
log "  *** BACKUP ${TARI_DIR}/wallet/keys/ IMMEDIATELY! ***"
