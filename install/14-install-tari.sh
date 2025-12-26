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

# Check if Tari pool is enabled (merge, merged, or tari_only modes)
case "${ENABLE_MONERO_TARI_POOL}" in
    merge|merged|tari_only)
        ;;
    *)
        log "Tari pool is disabled, skipping..."
        exit 0
        ;;
esac

log "Installing Tari node and mining software v${TARI_VERSION}..."

# Template directory
TEMPLATE_DIR="/opt/solo-pool/install/files/config"

# Determine network mode settings
if [ "${NETWORK_MODE}" = "testnet" ]; then
    export TARI_NETWORK="esmeralda"
    log "  Network mode: ESMERALDA (testnet)"
else
    export TARI_NETWORK="mainnet"
    log "  Network mode: MAINNET"
fi

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

# Determine network name for download URL
# Tari uses "esme" for esmeralda testnet, "mainnet" for mainnet
if [ "${TARI_NETWORK}" = "esmeralda" ]; then
    TARI_NETWORK_SHORT="esme"
else
    TARI_NETWORK_SHORT="mainnet"
fi

# Get the actual download URL from GitHub API (release assets have a commit hash in the name)
log "  Finding download URL for Tari v${TARI_VERSION} (${TARI_NETWORK_SHORT})..."
RELEASE_INFO=$(wget -q -O - "https://api.github.com/repos/tari-project/tari/releases/tags/v${TARI_VERSION}" 2>/dev/null)

if [ -z "${RELEASE_INFO}" ]; then
    log_error "Failed to get Tari release info for v${TARI_VERSION}"
    exit 1
fi

# Find the asset URL matching tari_suite-{version}-{network}-*-linux-x86_64.zip
TARI_RELEASE_URL=$(echo "${RELEASE_INFO}" | grep -oP '"browser_download_url":\s*"\K[^"]+tari_suite-[^"]*'"${TARI_NETWORK_SHORT}"'[^"]*linux-x86_64\.zip(?=")' | head -1)

if [ -z "${TARI_RELEASE_URL}" ]; then
    log_error "Could not find Tari ${TARI_NETWORK_SHORT} asset for linux-x86_64 in release v${TARI_VERSION}"
    exit 1
fi

log "  Downloading from: ${TARI_RELEASE_URL}"
# Don't use run_cmd for wget - it breaks exit status checking due to pipe
rm -f tari.zip
if ! wget -q "${TARI_RELEASE_URL}" -O tari.zip; then
    log_error "Failed to download Tari v${TARI_VERSION}"
    exit 1
fi

# Verify download succeeded (file exists and is not empty)
if [ ! -f tari.zip ] || [ ! -s tari.zip ]; then
    log_error "Tari download failed - file is empty or missing"
    exit 1
fi

# Verify it's a valid zip file
if ! unzip -t tari.zip >/dev/null 2>&1; then
    log_error "Tari download is corrupt (invalid zip file)"
    rm -f tari.zip
    exit 1
fi

# Extract
log "  Extracting..."
mkdir -p tari-extract
if ! unzip -q tari.zip -d tari-extract; then
    log_error "Failed to extract Tari archive"
    rm -rf tari.zip tari-extract
    exit 1
fi

# Find and copy binaries (node, wallet, miner, and merge proxy)
log "  Installing binaries..."
find tari-extract -type f -executable -name "minotari_*" -exec cp {} ${TARI_DIR}/bin/ \;

# Make executable
chmod +x ${TARI_DIR}/bin/*

# Cleanup
rm -rf tari.zip tari-extract

log "  Tari binaries installed"

# =============================================================================
# 2. CONFIGURE MINOTARI NODE
# =============================================================================
log "2. Configuring Minotari Node..."

# Create base config directory
mkdir -p ${TARI_DIR}/config

# Determine P2P listen address based on inbound config (libp2p multiaddress format)
if [ "${ENABLE_INBOUND_P2P}" = "true" ]; then
    export TARI_P2P_MULTIADDR="/ip4/0.0.0.0/tcp/18189"
else
    export TARI_P2P_MULTIADDR="/ip4/127.0.0.1/tcp/18189"
fi

# Generate password for node's internal wallet
export XTM_NODE_WALLET_PASSWORD=$(apg -a 1 -m 32 -M NCL -n 1)

# Generate RPC credentials for Tari gRPC authentication (same method as BTC/BCH/DGB/XMR)
# Use random username for additional security
export XTM_RPC_USER=$(apg -a 1 -m 16 -M NCL -n 1)
export XTM_RPC_PASSWORD=$(apg -a 1 -m 64 -M NCL -n 1)

# Save RPC credentials for other services (merge proxy, WebUI, etc.)
echo "${XTM_RPC_USER}" > ${TARI_DIR}/config/rpc.user
echo "${XTM_RPC_PASSWORD}" > ${TARI_DIR}/config/rpc.password
chmod 600 ${TARI_DIR}/config/rpc.user ${TARI_DIR}/config/rpc.password
log "  Generated gRPC credentials"

# Export variables for template
export TARI_DIR TARI_NODE_GRPC_PORT TARI_WALLET_GRPC_PORT TARI_NETWORK TARI_P2P_MULTIADDR
export XTM_RPC_USER XTM_RPC_PASSWORD

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

# Create wallet config from template (TARI_NETWORK already exported)
log "  Creating wallet configuration from template..."
export TARI_NETWORK
envsubst < "${TEMPLATE_DIR}/tari-wallet.toml.template" > ${TARI_DIR}/wallet/config/config.toml
chmod 600 ${TARI_DIR}/wallet/config/config.toml

# Create wallet start script from template
log "  Creating wallet start script from template..."
envsubst < "${TEMPLATE_DIR}/start-tari-wallet.sh.template" > ${TARI_DIR}/bin/start-wallet.sh
chmod +x ${TARI_DIR}/bin/start-wallet.sh

# Initialize the wallet to generate keys (non-interactive mode)
log "  Initializing wallet..."
cd ${TARI_DIR}/wallet

# Create a command file that will initialize the wallet and show the address
# The wallet auto-creates on first run. We use an input file with commands.
cat > /tmp/wallet_init_cmds.txt << 'EOF'
get-balance
exit
EOF

# Run wallet with the command file - this creates the wallet if it doesn't exist
# and outputs wallet info including the address
WALLET_OUTPUT=$(${TARI_DIR}/bin/minotari_console_wallet \
    --base-path ${TARI_DIR}/wallet/data \
    --config ${TARI_DIR}/wallet/config/config.toml \
    --password "${XTM_WALLET_PASSWORD}" \
    --non-interactive-mode \
    --input-file /tmp/wallet_init_cmds.txt 2>&1 || true)

# Cleanup temp file
rm -f /tmp/wallet_init_cmds.txt

# Extract wallet address from output (Tari addresses start with tari_ prefix or are hex)
# Try various patterns
XTM_POOL_ADDRESS=$(echo "${WALLET_OUTPUT}" | grep -oE 'tari://[a-zA-Z0-9]+' | head -1 | sed 's/tari:\/\///')
if [ -z "${XTM_POOL_ADDRESS}" ]; then
    # Try to find a 64+ character hex string (typical Tari address format)
    XTM_POOL_ADDRESS=$(echo "${WALLET_OUTPUT}" | grep -oE '[0-9a-f]{64,}' | head -1)
fi

# If still not found, try the emoji ID format
if [ -z "${XTM_POOL_ADDRESS}" ]; then
    XTM_POOL_ADDRESS=$(echo "${WALLET_OUTPUT}" | grep -oE '\|[🎀-🏿]{12,}\|' | head -1 || true)
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
log "  Wallet address: ${XTM_WALLET_ADDRESS:0:20}[...]"
log "  *** BACKUP wallet keys and seed IMMEDIATELY! ***"

# =============================================================================
# 4. CONFIGURE BASED ON MODE
# =============================================================================

if [ "${ENABLE_MONERO_TARI_POOL}" = "merge" ] || [ "${ENABLE_MONERO_TARI_POOL}" = "merged" ]; then
    # =============================================================================
    # MERGE MINING MODE
    # =============================================================================
    log "4. Configuring Merge Mining Proxy..."

    # Create standardized directory structure
    mkdir -p ${XMR_XTM_MERGE_DIR}/bin
    mkdir -p ${XMR_XTM_MERGE_DIR}/config
    mkdir -p ${XMR_XTM_MERGE_DIR}/data
    mkdir -p ${XMR_XTM_MERGE_DIR}/logs

    # Read Monero RPC credentials (generated by 13-install-monero.sh)
    if [ -f "${MONERO_DIR}/config/rpc.user" ] && [ -f "${MONERO_DIR}/config/rpc.password" ]; then
        export XMR_RPC_USER=$(cat "${MONERO_DIR}/config/rpc.user")
        export XMR_RPC_PASSWORD=$(cat "${MONERO_DIR}/config/rpc.password")
        log "  Read Monero RPC credentials"
    else
        log_error "  Monero RPC credentials not found - was 13-install-monero.sh run?"
        exit 1
    fi

    # Determine effective Monero RPC port (stagenet uses 38081)
    if [ "${NETWORK_MODE}" = "testnet" ]; then
        export XMR_EFFECTIVE_RPC_PORT="38081"
    else
        export XMR_EFFECTIVE_RPC_PORT="${MONERO_RPC_PORT}"
    fi

    # Export variables for template
    export XMR_XTM_MERGE_STRATUM_PORT XMR_EFFECTIVE_RPC_PORT XTM_WALLET_ADDRESS XMR_XTM_MERGE_DIR
    export TARI_NODE_GRPC_PORT TARI_WALLET_GRPC_PORT TARI_NETWORK

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

elif [ "${ENABLE_MONERO_TARI_POOL}" = "tari_only" ]; then
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
    export TARI_NODE_GRPC_PORT TARI_WALLET_GRPC_PORT TARI_NETWORK

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
log "  Pool wallet address: ${XTM_WALLET_ADDRESS:0:20}[...]"
log "  *** BACKUP ${TARI_DIR}/wallet/keys/ IMMEDIATELY! ***"
