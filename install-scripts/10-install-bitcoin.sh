#!/bin/bash
# =============================================================================
# 10-install-bitcoin.sh
# Install Bitcoin Core and CKPool for BTC
# =============================================================================

set -e

# Source configuration
source /opt/solo-pool/install-scripts/config.sh

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
grep "bitcoin-${BITCOIN_VERSION}-x86_64-linux-gnu.tar.gz" SHA256SUMS | sha256sum -c - >/dev/tty1 2>&1

# Extract and install
log "  Extracting..."
run_cmd tar -xzf bitcoin.tar.gz

# Copy binaries
log "  Installing binaries..."
cp bitcoin-${BITCOIN_VERSION}/bin/* ${BITCOIN_DIR}/bin/

# Cleanup
rm -rf bitcoin.tar.gz bitcoin-${BITCOIN_VERSION} SHA256SUMS

# Create bitcoin.conf
log "  Creating bitcoin.conf..."

# Determine listen setting based on inbound P2P config
if [ "${ENABLE_INBOUND_P2P}" = "true" ]; then
    BTC_LISTEN=1
else
    BTC_LISTEN=0
fi

cat > ${BITCOIN_DIR}/bitcoin.conf << EOF
# Bitcoin Core Configuration for Solo Mining Pool

# Network
server=1
daemon=0
txindex=1
listen=${BTC_LISTEN}

# RPC Configuration
rpcuser=bitcoinrpc
rpcpassword=$(apg -a 1 -m 64 -M NCL -n 1)
rpcallowip=127.0.0.1
rpcbind=127.0.0.1
rpcport=${BITCOIN_RPC_PORT}

# ZMQ for block notifications
zmqpubhashblock=tcp://127.0.0.1:${BITCOIN_ZMQ_BLOCK_PORT}
zmqpubhashtx=tcp://127.0.0.1:${BITCOIN_ZMQ_TX_PORT}

# Performance
dbcache=1024
maxconnections=50
maxuploadtarget=5000

# Data directory
datadir=${BITCOIN_DIR}/data

# Wallet (disabled - pool handles payouts)
disablewallet=1
EOF

# Set permissions
chown -R ${POOL_USER}:${POOL_USER} ${BITCOIN_DIR}
chmod 600 ${BITCOIN_DIR}/bitcoin.conf

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

# Create CKPool configuration
log "  Creating CKPool configuration..."

# Get RPC password from bitcoin.conf
BTC_RPC_PASS=$(grep -i rpcpassword ${BITCOIN_DIR}/bitcoin.conf | cut -d'=' -f2)

# Determine starting difficulty
if [ "${ENABLE_CUSTOM_DIFFICULTY}" = "true" ]; then
    BTC_STARTDIFF="${BTC_START_DIFFICULTY:-42}"
else
    BTC_STARTDIFF=42
fi

cat > ${BTC_CKPOOL_DIR}/ckpool.conf << EOF
{
    "btcd" : [
        {
            "url" : "127.0.0.1:${BITCOIN_RPC_PORT}",
            "auth" : "bitcoinrpc",
            "pass" : "${BTC_RPC_PASS}",
            "notify" : true
        }
    ],
    "_comment" : "btcaddress is ignored in BTCSOLO mode (-B flag); miners use their wallet address as username",
    "btcaddress" : "ignored_in_btcsolo_mode",
    "btcsig" : "Solo Pool",
    "blockpoll" : 100,
    "update_interval" : 30,
    "serverurl" : [
        "0.0.0.0:${BTC_STRATUM_PORT}"
    ],
    "mindiff" : 1,
    "startdiff" : ${BTC_STARTDIFF},
    "maxdiff" : 0,
    "logdir" : "${BTC_CKPOOL_DIR}/logs"
}
EOF

# Set permissions
chown -R ${POOL_USER}:${POOL_USER} ${BTC_CKPOOL_DIR}
chmod 600 ${BTC_CKPOOL_DIR}/ckpool.conf

log_success "Bitcoin Core and CKPool installed"
log "  Node: ${BITCOIN_DIR}"
log "  Pool: ${BTC_CKPOOL_DIR}"
log "  Stratum port: ${BTC_STRATUM_PORT}"
