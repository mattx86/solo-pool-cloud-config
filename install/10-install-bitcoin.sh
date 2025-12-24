#!/bin/bash
# =============================================================================
# 10-install-bitcoin.sh
# Install Bitcoin Core and CKPool for BTC
# =============================================================================

set -e

# Source configuration
source /opt/solo-pool/install/config.sh

# Validate config was loaded successfully
if [ "${CONFIG_LOADED:-}" != "true" ]; then
    echo "ERROR: Failed to load configuration from config.sh" >&2
    exit 1
fi

# Check if Bitcoin pool is enabled
if [ "${ENABLE_BITCOIN_POOL}" != "true" ]; then
    log "Bitcoin pool is disabled, skipping..."
    exit 0
fi

log "Installing Bitcoin Core and CKPool..."

# Template directory
TEMPLATE_DIR="/opt/solo-pool/install/files/config"

# =============================================================================
# 1. INSTALL BITCOIN CORE
# =============================================================================
log "1. Installing Bitcoin Core v${BITCOIN_VERSION}..."

cd /tmp

# Download Bitcoin Core
BITCOIN_URL="https://bitcoincore.org/bin/bitcoin-core-${BITCOIN_VERSION}/bitcoin-${BITCOIN_VERSION}-x86_64-linux-gnu.tar.gz"
BITCOIN_SHA_URL="https://bitcoincore.org/bin/bitcoin-core-${BITCOIN_VERSION}/SHA256SUMS"

log "  Downloading Bitcoin Core..."
run_cmd wget -q "${BITCOIN_URL}" -O bitcoin.tar.gz
run_cmd wget -q "${BITCOIN_SHA_URL}" -O SHA256SUMS

# Verify checksum
log "  Verifying checksum..."
grep "bitcoin-${BITCOIN_VERSION}-x86_64-linux-gnu.tar.gz" SHA256SUMS | sha256sum -c - >/dev/null 2>&1

# Extract and install
log "  Extracting..."
run_cmd tar -xzf bitcoin.tar.gz

# Create standardized directory structure
log "  Creating directory structure..."
mkdir -p ${BITCOIN_DIR}/bin
mkdir -p ${BITCOIN_DIR}/config
mkdir -p ${BITCOIN_DIR}/data
mkdir -p ${BITCOIN_DIR}/logs

# Copy binaries
log "  Installing binaries..."
cp bitcoin-${BITCOIN_VERSION}/bin/* ${BITCOIN_DIR}/bin/

# Cleanup
rm -rf bitcoin.tar.gz bitcoin-${BITCOIN_VERSION} SHA256SUMS

# Create bitcoin.conf from template
log "  Creating bitcoin.conf from template..."

# Determine listen setting based on inbound P2P config
if [ "${ENABLE_INBOUND_P2P}" = "true" ]; then
    export BTC_LISTEN=1
else
    export BTC_LISTEN=0
fi

# Generate RPC password
export BTC_RPC_PASSWORD=$(apg -a 1 -m 64 -M NCL -n 1)

# Export variables for template
export BITCOIN_DIR BITCOIN_RPC_PORT BITCOIN_ZMQ_BLOCK_PORT BITCOIN_ZMQ_TX_PORT

# Generate config from template
envsubst < "${TEMPLATE_DIR}/bitcoin.conf.template" > ${BITCOIN_DIR}/config/bitcoin.conf

# Set permissions
chown -R ${POOL_USER}:${POOL_USER} ${BITCOIN_DIR}
chmod 600 ${BITCOIN_DIR}/config/bitcoin.conf

log "  Bitcoin Core installed"

# =============================================================================
# 2. BUILD AND INSTALL CKPOOL
# =============================================================================
log "2. Building CKPool (commit ${CKPOOL_COMMIT:0:8}) for Bitcoin..."

cd /tmp

# Clone CKPool at specific commit
log "  Cloning CKPool..."
rm -rf ckpool-btc
run_cmd git clone https://bitbucket.org/ckolivas/ckpool.git ckpool-btc

cd ckpool-btc

# Checkout specific commit for reproducibility
log "  Checking out commit ${CKPOOL_COMMIT:0:8}..."
run_cmd git checkout ${CKPOOL_COMMIT}

if [ $? -ne 0 ]; then
    log_error "Failed to checkout CKPool commit ${CKPOOL_COMMIT}"
    exit 1
fi

# Create standardized directory structure for CKPool
log "  Creating CKPool directory structure..."
mkdir -p ${BTC_CKPOOL_DIR}/bin
mkdir -p ${BTC_CKPOOL_DIR}/config
mkdir -p ${BTC_CKPOOL_DIR}/data
mkdir -p ${BTC_CKPOOL_DIR}/logs

# Build CKPool
log "  Building CKPool..."
run_cmd ./autogen.sh
run_cmd ./configure --prefix=${BTC_CKPOOL_DIR}
run_cmd make -j$(nproc)
run_cmd make install

# Copy binary
cp src/ckpool ${BTC_CKPOOL_DIR}/bin/
cp src/ckpmsg ${BTC_CKPOOL_DIR}/bin/
cp src/notifier ${BTC_CKPOOL_DIR}/bin/

# Cleanup
cd /tmp
rm -rf ckpool-btc

# Create CKPool configuration from template
log "  Creating CKPool configuration from template..."

# Export variables for CKPool template
export NODE_RPC_PORT="${BITCOIN_RPC_PORT}"
export NODE_RPC_USER="bitcoinrpc"
export NODE_RPC_PASSWORD="${BTC_RPC_PASSWORD}"
export POOL_SIG="Solo Pool"
export STRATUM_PORT="${BTC_STRATUM_PORT}"
export CKPOOL_DIR="${BTC_CKPOOL_DIR}"

# Determine starting difficulty
if [ "${ENABLE_CUSTOM_DIFFICULTY}" = "true" ]; then
    export START_DIFF="${BTC_START_DIFFICULTY:-42}"
else
    export START_DIFF=42
fi

# Generate config from template
envsubst < "${TEMPLATE_DIR}/ckpool.conf.template" > ${BTC_CKPOOL_DIR}/config/ckpool.conf

# Set permissions
chown -R ${POOL_USER}:${POOL_USER} ${BTC_CKPOOL_DIR}
chmod 600 ${BTC_CKPOOL_DIR}/config/ckpool.conf

log_success "Bitcoin Core and CKPool installed"
log "  Node: ${BITCOIN_DIR}"
log "  Pool: ${BTC_CKPOOL_DIR}"
log "  Stratum port: ${BTC_STRATUM_PORT}"
