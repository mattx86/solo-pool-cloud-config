#!/bin/bash
# =============================================================================
# 11-install-bch.sh
# Install Bitcoin Cash Node (BCHN) and CKPool for BCH
# =============================================================================

set -e

# Source configuration
source /opt/solo-pool/install-scripts/config.sh

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

# Determine listen setting based on inbound P2P config
if [ "${ENABLE_INBOUND_P2P}" = "true" ]; then
    BCH_LISTEN=1
else
    BCH_LISTEN=0
fi

cat > ${BCHN_DIR}/bitcoin.conf << EOF
# Bitcoin Cash Node Configuration for Solo Mining Pool

# Network
server=1
daemon=0
txindex=1
listen=${BCH_LISTEN}

# Use different ports than BTC
port=8335
rpcport=${BCH_RPC_PORT}

# RPC Configuration
rpcuser=bchrpc
rpcpassword=$(apg -a 1 -m 64 -M NCL -n 1)
rpcallowip=127.0.0.1
rpcbind=127.0.0.1

# ZMQ for block notifications (different ports than BTC)
zmqpubhashblock=tcp://127.0.0.1:${BCH_ZMQ_BLOCK_PORT}
zmqpubhashtx=tcp://127.0.0.1:${BCH_ZMQ_TX_PORT}

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

# Create CKPool configuration for BCH
log "  Creating CKPool configuration..."

# Get RPC password from bitcoin.conf
BCH_RPC_PASS=$(grep -i rpcpassword ${BCHN_DIR}/bitcoin.conf | cut -d'=' -f2)

# Determine starting difficulty
if [ "${ENABLE_CUSTOM_DIFFICULTY}" = "true" ]; then
    BCH_STARTDIFF="${BCH_START_DIFFICULTY:-42}"
else
    BCH_STARTDIFF=42
fi

cat > ${BCH_CKPOOL_DIR}/ckpool.conf << EOF
{
    "btcd" : [
        {
            "url" : "127.0.0.1:${BCH_RPC_PORT}",
            "auth" : "bchrpc",
            "pass" : "${BCH_RPC_PASS}",
            "notify" : true
        }
    ],
    "_comment" : "btcaddress is ignored in BTCSOLO mode (-B flag); miners use their wallet address as username",
    "btcaddress" : "ignored_in_btcsolo_mode",
    "btcsig" : "Solo Pool BCH",
    "blockpoll" : 100,
    "update_interval" : 30,
    "serverurl" : [
        "0.0.0.0:${BCH_STRATUM_PORT}"
    ],
    "mindiff" : 1,
    "startdiff" : ${BCH_STARTDIFF},
    "maxdiff" : 0,
    "logdir" : "${BCH_CKPOOL_DIR}/logs"
}
EOF

# Set permissions
chown -R ${POOL_USER}:${POOL_USER} ${BCH_CKPOOL_DIR}
chmod 600 ${BCH_CKPOOL_DIR}/ckpool.conf

log_success "BCHN and CKPool for BCH installed"
log "  Node: ${BCHN_DIR}"
log "  Pool: ${BCH_CKPOOL_DIR}"
log "  Stratum port: ${BCH_STRATUM_PORT}"
