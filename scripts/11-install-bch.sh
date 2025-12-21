#!/bin/bash
# =============================================================================
# 11-install-bch.sh
# Install Bitcoin Cash Node (BCHN) and CKPool for BCH
# =============================================================================

set -e

# Source configuration
source /opt/solo-pool/config.sh

# Check if BCH pool is enabled
if [ "${ENABLE_BCH_POOL}" != "true" ]; then
    log "Bitcoin Cash pool is disabled, skipping..."
    exit 0
fi

log "Installing Bitcoin Cash Node and CKPool..."

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

# Copy binaries
log "  Installing binaries..."
cp bitcoin-cash-node-${BCHN_VERSION}/bin/* ${BCHN_DIR}/bin/

# Cleanup
rm -rf bchn.tar.gz bitcoin-cash-node-${BCHN_VERSION}

# Create bitcoin.conf for BCH
log "  Creating bitcoin.conf..."
cat > ${BCHN_DIR}/bitcoin.conf << EOF
# Bitcoin Cash Node Configuration for Solo Mining Pool

# Network
server=1
daemon=0
txindex=1
listen=1

# Use different ports than BTC
port=8335
rpcport=8334

# RPC Configuration
rpcuser=bchrpc
rpcpassword=$(openssl rand -hex 32)
rpcallowip=127.0.0.1
rpcbind=127.0.0.1

# ZMQ for block notifications (different ports than BTC)
zmqpubhashblock=tcp://127.0.0.1:28334
zmqpubhashtx=tcp://127.0.0.1:28335

# Performance
dbcache=1024
maxconnections=50

# Data directory
datadir=${BCHN_DIR}/data

# Wallet (disabled - pool handles payouts)
disablewallet=1
EOF

# Set permissions
chown -R ${POOL_USER}:${POOL_USER} ${BCHN_DIR}
chmod 600 ${BCHN_DIR}/bitcoin.conf

log "  BCHN installed"

# =============================================================================
# 2. BUILD AND INSTALL CKPOOL FOR BCH
# =============================================================================
log "2. Building CKPool for Bitcoin Cash..."

cd /tmp

# Clone CKPool
log "  Cloning CKPool..."
rm -rf ckpool-bch
run_cmd git clone https://bitbucket.org/ckolivas/ckpool.git ckpool-bch

cd ckpool-bch

# Build CKPool
log "  Building CKPool..."
run_cmd ./autogen.sh
run_cmd ./configure --prefix=${CKPOOL_BCH_DIR}
run_cmd make -j$(nproc)
run_cmd make install

# Copy binary
cp src/ckpool ${CKPOOL_BCH_DIR}/bin/
cp src/ckpmsg ${CKPOOL_BCH_DIR}/bin/
cp src/notifier ${CKPOOL_BCH_DIR}/bin/

# Cleanup
cd /tmp
rm -rf ckpool-bch

# Create CKPool configuration for BCH
log "  Creating CKPool configuration..."

# Get RPC password from bitcoin.conf
BCH_RPC_PASS=$(grep rpcpassword ${BCHN_DIR}/bitcoin.conf | cut -d'=' -f2)

cat > ${CKPOOL_BCH_DIR}/ckpool.conf << EOF
{
    "btcd" : [
        {
            "url" : "127.0.0.1:8334",
            "auth" : "bchrpc",
            "pass" : "${BCH_RPC_PASS}",
            "notify" : true
        }
    ],
    "btcaddress" : "${BCH_WALLET_ADDRESS}",
    "btcsig" : "Solo Pool BCH",
    "blockpoll" : 100,
    "update_interval" : 30,
    "serverurl" : [
        "0.0.0.0:${BCH_STRATUM_PORT}"
    ],
    "mindiff" : 1,
    "startdiff" : 42,
    "maxdiff" : 0,
    "logdir" : "${CKPOOL_BCH_DIR}/logs"
}
EOF

# Set permissions
chown -R ${POOL_USER}:${POOL_USER} ${CKPOOL_BCH_DIR}
chmod 600 ${CKPOOL_BCH_DIR}/ckpool.conf

log_success "BCHN and CKPool for BCH installed"
log "  Node: ${BCHN_DIR}"
log "  Pool: ${CKPOOL_BCH_DIR}"
log "  Stratum port: ${BCH_STRATUM_PORT}"
