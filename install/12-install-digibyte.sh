#!/bin/bash
# =============================================================================
# 12-install-digibyte.sh
# Install DigiByte Core and CKPool for DGB (SHA256 only)
# =============================================================================

set -e

# Source configuration
source /opt/solo-pool/install/config.sh

# Validate config was loaded successfully
if [ "${CONFIG_LOADED:-}" != "true" ]; then
    echo "ERROR: Failed to load configuration from config.sh" >&2
    exit 1
fi

# Check if DigiByte pool is enabled
if [ "${ENABLE_DGB_POOL}" != "true" ]; then
    log "DigiByte pool is disabled, skipping..."
    exit 0
fi

log "Installing DigiByte Core and CKPool..."

# Template directory
TEMPLATE_DIR="/opt/solo-pool/install/files/config"

# =============================================================================
# 1. INSTALL DIGIBYTE CORE
# =============================================================================
log "1. Installing DigiByte Core v${DIGIBYTE_VERSION}..."

# Create standardized directory structure
log "  Creating directory structure..."
mkdir -p ${DIGIBYTE_DIR}/bin
mkdir -p ${DIGIBYTE_DIR}/config
mkdir -p ${DIGIBYTE_DIR}/data
mkdir -p ${DIGIBYTE_DIR}/logs

cd /tmp

# Download DigiByte Core
DGB_URL="https://github.com/DigiByte-Core/digibyte/releases/download/v${DIGIBYTE_VERSION}/digibyte-${DIGIBYTE_VERSION}-x86_64-linux-gnu.tar.gz"

log "  Downloading DigiByte Core..."
run_cmd wget -q "${DGB_URL}" -O digibyte.tar.gz

# Extract and install
log "  Extracting..."
run_cmd tar -xzf digibyte.tar.gz

# Copy binaries
log "  Installing binaries..."
cp digibyte-${DIGIBYTE_VERSION}/bin/* ${DIGIBYTE_DIR}/bin/

# Cleanup
rm -rf digibyte.tar.gz digibyte-${DIGIBYTE_VERSION}

# Create digibyte.conf from template
log "  Creating digibyte.conf from template..."

# Determine listen setting based on inbound P2P config
if [ "${ENABLE_INBOUND_P2P}" = "true" ]; then
    export DGB_LISTEN=1
else
    export DGB_LISTEN=0
fi

# Determine network mode settings
if [ "${NETWORK_MODE}" = "testnet" ]; then
    export NETWORK_FLAG="testnet=1"
    export NETWORK_SECTION="[test]"
    export EFFECTIVE_RPC_PORT="14023"
    # DGB testnet has few peers - add known seed nodes
    export DGB_SEED_NODES="# Testnet seed nodes (testnet has limited peers)
addnode=seed.testnet-1.us.digibyteservers.io
addnode=seed.testnetexplorer.digibyteservers.io"
    log "  Network mode: TESTNET (with seed nodes)"
else
    export NETWORK_FLAG=""
    export NETWORK_SECTION="[main]"
    export EFFECTIVE_RPC_PORT="${DGB_RPC_PORT}"
    export DGB_SEED_NODES=""
    log "  Network mode: MAINNET"
fi

# Determine sync mode settings
if [ "${SYNC_MODE}" = "initial" ]; then
    export BLOCKSONLY_SETTING="blocksonly=1"
    log "  Sync mode: INITIAL (blocksonly for faster sync)"
else
    export BLOCKSONLY_SETTING="# blocksonly disabled - mining requires mempool"
    log "  Sync mode: PRODUCTION (mempool enabled for mining)"
fi

# Generate RPC credentials (random username for additional security)
export DGB_RPC_USER=$(apg -a 1 -m 16 -M NCL -n 1)
export DGB_RPC_PASSWORD=$(apg -a 1 -m 64 -M NCL -n 1)

# Save RPC credentials for other services (CKPool, WebUI, etc.)
echo "${DGB_RPC_USER}" > ${DIGIBYTE_DIR}/config/rpc.user
echo "${DGB_RPC_PASSWORD}" > ${DIGIBYTE_DIR}/config/rpc.password
chmod 600 ${DIGIBYTE_DIR}/config/rpc.user ${DIGIBYTE_DIR}/config/rpc.password
log "  Generated RPC credentials (user: ${DGB_RPC_USER})"

# Export variables for template
export DIGIBYTE_DIR DGB_RPC_PORT DGB_ZMQ_BLOCK_PORT DGB_ZMQ_TX_PORT NETWORK_FLAG NETWORK_SECTION EFFECTIVE_RPC_PORT BLOCKSONLY_SETTING DGB_RPC_USER DGB_SEED_NODES

# Generate config from template
envsubst < "${TEMPLATE_DIR}/digibyte.conf.template" > ${DIGIBYTE_DIR}/config/digibyte.conf

# Set permissions
chown -R ${POOL_USER}:${POOL_USER} ${DIGIBYTE_DIR}
chmod 600 ${DIGIBYTE_DIR}/config/digibyte.conf

log "  DigiByte Core installed"

# =============================================================================
# 2. BUILD AND INSTALL CKPOOL FOR DGB
# =============================================================================
log "2. Building CKPool (commit ${CKPOOL_COMMIT:0:8}) for DigiByte..."

# Create standardized directory structure
log "  Creating directory structure..."
mkdir -p ${DGB_CKPOOL_DIR}/bin
mkdir -p ${DGB_CKPOOL_DIR}/config
mkdir -p ${DGB_CKPOOL_DIR}/data
mkdir -p ${DGB_CKPOOL_DIR}/logs

cd /tmp

# Clone CKPool at specific commit
log "  Cloning CKPool..."
rm -rf ckpool-dgb
run_cmd git clone https://bitbucket.org/ckolivas/ckpool.git ckpool-dgb

cd ckpool-dgb

# Checkout specific commit for reproducibility
log "  Checking out commit ${CKPOOL_COMMIT:0:8}..."
run_cmd git checkout ${CKPOOL_COMMIT}

if [ $? -ne 0 ]; then
    log_error "Failed to checkout CKPool commit ${CKPOOL_COMMIT}"
    exit 1
fi

# Build CKPool
log "  Building CKPool..."
run_cmd ./autogen.sh
run_cmd ./configure --prefix=${DGB_CKPOOL_DIR}
run_cmd make -j$(nproc)
run_cmd make install

# Copy binary
cp src/ckpool ${DGB_CKPOOL_DIR}/bin/
cp src/ckpmsg ${DGB_CKPOOL_DIR}/bin/
cp src/notifier ${DGB_CKPOOL_DIR}/bin/

# Cleanup
cd /tmp
rm -rf ckpool-dgb

# Create CKPool configuration from template
log "  Creating CKPool configuration from template..."

# Export variables for CKPool template
# Use EFFECTIVE_RPC_PORT which is set based on network mode
export NODE_RPC_PORT="${EFFECTIVE_RPC_PORT}"
export NODE_RPC_USER="${DGB_RPC_USER}"
export NODE_RPC_PASSWORD="${DGB_RPC_PASSWORD}"
export POOL_SIG="Solo Pool DGB"
export STRATUM_PORT="${DGB_STRATUM_PORT}"
export CKPOOL_DIR="${DGB_CKPOOL_DIR}"

# Determine starting difficulty
if [ "${ENABLE_CUSTOM_DIFFICULTY}" = "true" ]; then
    export START_DIFF="${DGB_START_DIFFICULTY:-16}"
else
    export START_DIFF=16
fi

# Generate config from template
envsubst < "${TEMPLATE_DIR}/ckpool.conf.template" > ${DGB_CKPOOL_DIR}/config/ckpool.conf

# Set permissions
chown -R ${POOL_USER}:${POOL_USER} ${DGB_CKPOOL_DIR}
chmod 600 ${DGB_CKPOOL_DIR}/config/ckpool.conf

log_success "DigiByte Core and CKPool installed"
log "  Node: ${DIGIBYTE_DIR}"
log "  Pool: ${DGB_CKPOOL_DIR}"
log "  Stratum port: ${DGB_STRATUM_PORT}"
log "  NOTE: Only SHA256 algorithm is supported with CKPool"
