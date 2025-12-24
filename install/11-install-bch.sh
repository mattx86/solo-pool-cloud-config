#!/bin/bash
# =============================================================================
# 11-install-bch.sh
# Install Bitcoin Cash Node (BCHN) and CKPool for BCH
# =============================================================================

set -e

# Source configuration
source /opt/solo-pool/install/config.sh

# Validate config was loaded successfully
if [ "${CONFIG_LOADED:-}" != "true" ]; then
    echo "ERROR: Failed to load configuration from config.sh" >&2
    exit 1
fi

# Check if BCH pool is enabled
if [ "${ENABLE_BCH_POOL}" != "true" ]; then
    log "Bitcoin Cash pool is disabled, skipping..."
    exit 0
fi

log "Installing Bitcoin Cash Node and CKPool..."

# Template directory
TEMPLATE_DIR="/opt/solo-pool/install/files/config"

# =============================================================================
# 1. INSTALL BITCOIN CASH NODE (BCHN)
# =============================================================================
log "1. Installing BCHN v${BCHN_VERSION}..."

cd /tmp

# Download BCHN
BCHN_URL="https://github.com/bitcoin-cash-node/bitcoin-cash-node/releases/download/v${BCHN_VERSION}/bitcoin-cash-node-${BCHN_VERSION}-x86_64-linux-gnu.tar.gz"

log "  Downloading BCHN..."
run_cmd wget -q "${BCHN_URL}" -O bchn.tar.gz

# Extract and install
log "  Extracting..."
run_cmd tar -xzf bchn.tar.gz

# Create standardized directory structure
log "  Creating directory structure..."
mkdir -p ${BCHN_DIR}/bin
mkdir -p ${BCHN_DIR}/config
mkdir -p ${BCHN_DIR}/data
mkdir -p ${BCHN_DIR}/logs

# Copy binaries
log "  Installing binaries..."
cp bitcoin-cash-node-${BCHN_VERSION}/bin/* ${BCHN_DIR}/bin/

# Cleanup
rm -rf bchn.tar.gz bitcoin-cash-node-${BCHN_VERSION}

# Create bitcoin.conf from template
log "  Creating bitcoin.conf from template..."

# Determine listen setting based on inbound P2P config
if [ "${ENABLE_INBOUND_P2P}" = "true" ]; then
    export BCH_LISTEN=1
else
    export BCH_LISTEN=0
fi

# Determine network mode settings
if [ "${NETWORK_MODE}" = "testnet" ]; then
    export NETWORK_FLAG="testnet4=1"
    export EFFECTIVE_RPC_PORT="48334"
    log "  Network mode: TESTNET4"
else
    export NETWORK_FLAG=""
    export EFFECTIVE_RPC_PORT="${BCH_RPC_PORT}"
    log "  Network mode: MAINNET"
fi

# Generate RPC password
export BCH_RPC_PASSWORD=$(apg -a 1 -m 64 -M NCL -n 1)

# Export variables for template
export BCHN_DIR BCH_RPC_PORT BCH_ZMQ_BLOCK_PORT BCH_ZMQ_TX_PORT NETWORK_FLAG

# Generate config from template
envsubst < "${TEMPLATE_DIR}/bchn.conf.template" > ${BCHN_DIR}/config/bitcoin.conf

# Set permissions
chown -R ${POOL_USER}:${POOL_USER} ${BCHN_DIR}
chmod 600 ${BCHN_DIR}/config/bitcoin.conf

log "  BCHN installed"

# =============================================================================
# 2. BUILD AND INSTALL CKPOOL FOR BCH
# =============================================================================
log "2. Building CKPool (commit ${CKPOOL_COMMIT:0:8}) for Bitcoin Cash..."

cd /tmp

# Clone CKPool at specific commit
log "  Cloning CKPool..."
rm -rf ckpool-bch
run_cmd git clone https://bitbucket.org/ckolivas/ckpool.git ckpool-bch

cd ckpool-bch

# Checkout specific commit for reproducibility
log "  Checking out commit ${CKPOOL_COMMIT:0:8}..."
run_cmd git checkout ${CKPOOL_COMMIT}

if [ $? -ne 0 ]; then
    log_error "Failed to checkout CKPool commit ${CKPOOL_COMMIT}"
    exit 1
fi

# Create standardized directory structure for CKPool
log "  Creating CKPool directory structure..."
mkdir -p ${BCH_CKPOOL_DIR}/bin
mkdir -p ${BCH_CKPOOL_DIR}/config
mkdir -p ${BCH_CKPOOL_DIR}/data
mkdir -p ${BCH_CKPOOL_DIR}/logs

# Build CKPool
log "  Building CKPool..."
run_cmd ./autogen.sh
run_cmd ./configure --prefix=${BCH_CKPOOL_DIR}
run_cmd make -j$(nproc)
run_cmd make install

# Copy binary
cp src/ckpool ${BCH_CKPOOL_DIR}/bin/
cp src/ckpmsg ${BCH_CKPOOL_DIR}/bin/
cp src/notifier ${BCH_CKPOOL_DIR}/bin/

# Cleanup
cd /tmp
rm -rf ckpool-bch

# Create CKPool configuration from template
log "  Creating CKPool configuration from template..."

# Export variables for CKPool template
# Use EFFECTIVE_RPC_PORT which is set based on network mode
export NODE_RPC_PORT="${EFFECTIVE_RPC_PORT}"
export NODE_RPC_USER="bchrpc"
export NODE_RPC_PASSWORD="${BCH_RPC_PASSWORD}"
export POOL_SIG="Solo Pool BCH"
export STRATUM_PORT="${BCH_STRATUM_PORT}"
export CKPOOL_DIR="${BCH_CKPOOL_DIR}"

# Determine starting difficulty
if [ "${ENABLE_CUSTOM_DIFFICULTY}" = "true" ]; then
    export START_DIFF="${BCH_START_DIFFICULTY:-42}"
else
    export START_DIFF=42
fi

# Generate config from template
envsubst < "${TEMPLATE_DIR}/ckpool.conf.template" > ${BCH_CKPOOL_DIR}/config/ckpool.conf

# Set permissions
chown -R ${POOL_USER}:${POOL_USER} ${BCH_CKPOOL_DIR}
chmod 600 ${BCH_CKPOOL_DIR}/config/ckpool.conf

log_success "BCHN and CKPool for BCH installed"
log "  Node: ${BCHN_DIR}"
log "  Pool: ${BCH_CKPOOL_DIR}"
log "  Stratum port: ${BCH_STRATUM_PORT}"
