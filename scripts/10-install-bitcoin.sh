#!/bin/bash
# =============================================================================
# 10-install-bitcoin.sh
# Install Bitcoin Core and CKPool for BTC
# =============================================================================

set -e

# Source configuration
source /opt/solo-pool/config.sh

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
cat > ${BITCOIN_DIR}/bitcoin.conf << EOF
# Bitcoin Core Configuration for Solo Mining Pool

# Network
server=1
daemon=0
txindex=1
listen=1

# RPC Configuration
rpcuser=bitcoinrpc
rpcpassword=$(openssl rand -hex 32)
rpcallowip=127.0.0.1
rpcbind=127.0.0.1
rpcport=8332

# ZMQ for block notifications
zmqpubhashblock=tcp://127.0.0.1:28332
zmqpubhashtx=tcp://127.0.0.1:28333

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
log "2. Building CKPool for Bitcoin..."

cd /tmp

# Clone CKPool
log "  Cloning CKPool..."
rm -rf ckpool-btc
run_cmd git clone https://bitbucket.org/ckolivas/ckpool.git ckpool-btc

cd ckpool-btc

# Build CKPool
log "  Building CKPool..."
run_cmd ./autogen.sh
run_cmd ./configure --prefix=${CKPOOL_BTC_DIR}
run_cmd make -j$(nproc)
run_cmd make install

# Copy binary
cp src/ckpool ${CKPOOL_BTC_DIR}/bin/
cp src/ckpmsg ${CKPOOL_BTC_DIR}/bin/
cp src/notifier ${CKPOOL_BTC_DIR}/bin/

# Cleanup
cd /tmp
rm -rf ckpool-btc

# Create CKPool configuration
log "  Creating CKPool configuration..."

# Get RPC password from bitcoin.conf
BTC_RPC_PASS=$(grep rpcpassword ${BITCOIN_DIR}/bitcoin.conf | cut -d'=' -f2)

cat > ${CKPOOL_BTC_DIR}/ckpool.conf << EOF
{
    "btcd" : [
        {
            "url" : "127.0.0.1:8332",
            "auth" : "bitcoinrpc",
            "pass" : "${BTC_RPC_PASS}",
            "notify" : true
        }
    ],
    "btcaddress" : "${BTC_WALLET_ADDRESS}",
    "btcsig" : "Solo Pool",
    "blockpoll" : 100,
    "update_interval" : 30,
    "serverurl" : [
        "0.0.0.0:${BTC_STRATUM_PORT}"
    ],
    "mindiff" : 1,
    "startdiff" : 42,
    "maxdiff" : 0,
    "logdir" : "${CKPOOL_BTC_DIR}/logs"
}
EOF

# Set permissions
chown -R ${POOL_USER}:${POOL_USER} ${CKPOOL_BTC_DIR}
chmod 600 ${CKPOOL_BTC_DIR}/ckpool.conf

log_success "Bitcoin Core and CKPool installed"
log "  Node: ${BITCOIN_DIR}"
log "  Pool: ${CKPOOL_BTC_DIR}"
log "  Stratum port: ${BTC_STRATUM_PORT}"
