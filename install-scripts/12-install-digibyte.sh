#!/bin/bash
# =============================================================================
# 12-install-digibyte.sh
# Install DigiByte Core and CKPool for DGB (SHA256 only)
# =============================================================================

set -e

# Source configuration
source /opt/solo-pool/install-scripts/config.sh

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

# =============================================================================
# 1. INSTALL DIGIBYTE CORE
# =============================================================================
log "1. Installing DigiByte Core v${DIGIBYTE_VERSION}..."

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

# Create digibyte.conf
log "  Creating digibyte.conf..."

# Determine listen setting based on inbound P2P config
if [ "${ENABLE_INBOUND_P2P}" = "true" ]; then
    DGB_LISTEN=1
else
    DGB_LISTEN=0
fi

cat > ${DIGIBYTE_DIR}/digibyte.conf << EOF
# DigiByte Core Configuration for Solo Mining Pool

# Network
server=1
daemon=0
txindex=1
listen=${DGB_LISTEN}

# RPC Configuration
rpcuser=digibyterpc
rpcpassword=$(apg -a 1 -m 64 -M NCL -n 1)
rpcallowip=127.0.0.1
rpcbind=127.0.0.1
rpcport=${DGB_RPC_PORT}

# ZMQ for block notifications
zmqpubhashblock=tcp://127.0.0.1:${DGB_ZMQ_BLOCK_PORT}
zmqpubhashtx=tcp://127.0.0.1:${DGB_ZMQ_TX_PORT}

# Performance
dbcache=512
maxconnections=50

# Data directory
datadir=${DIGIBYTE_DIR}/data

# Wallet (disabled - pool handles payouts)
disablewallet=1

# Algorithm selection for mining
# Note: CKPool only supports SHA256 algo
algo=sha256d
EOF

# Set permissions
chown -R ${POOL_USER}:${POOL_USER} ${DIGIBYTE_DIR}
chmod 600 ${DIGIBYTE_DIR}/digibyte.conf

log "  DigiByte Core installed"

# =============================================================================
# 2. BUILD AND INSTALL CKPOOL FOR DGB
# =============================================================================
log "2. Building CKPool (commit ${CKPOOL_COMMIT:0:8}) for DigiByte..."

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

# Create CKPool configuration for DGB
log "  Creating CKPool configuration..."

# Get RPC password from digibyte.conf
DGB_RPC_PASS=$(grep -i rpcpassword ${DIGIBYTE_DIR}/digibyte.conf | cut -d'=' -f2)

# Determine starting difficulty
if [ "${ENABLE_CUSTOM_DIFFICULTY}" = "true" ]; then
    DGB_STARTDIFF="${DGB_START_DIFFICULTY:-16}"
else
    DGB_STARTDIFF=16
fi

cat > ${DGB_CKPOOL_DIR}/ckpool.conf << EOF
{
    "btcd" : [
        {
            "url" : "127.0.0.1:${DGB_RPC_PORT}",
            "auth" : "digibyterpc",
            "pass" : "${DGB_RPC_PASS}",
            "notify" : true
        }
    ],
    "_comment" : "btcaddress is ignored in BTCSOLO mode (-B flag); miners use their wallet address as username",
    "btcaddress" : "ignored_in_btcsolo_mode",
    "btcsig" : "Solo Pool DGB",
    "blockpoll" : 100,
    "update_interval" : 30,
    "serverurl" : [
        "0.0.0.0:${DGB_STRATUM_PORT}"
    ],
    "mindiff" : 1,
    "startdiff" : ${DGB_STARTDIFF},
    "maxdiff" : 0,
    "logdir" : "${DGB_CKPOOL_DIR}/logs"
}
EOF

# Set permissions
chown -R ${POOL_USER}:${POOL_USER} ${DGB_CKPOOL_DIR}
chmod 600 ${DGB_CKPOOL_DIR}/ckpool.conf

log_success "DigiByte Core and CKPool installed"
log "  Node: ${DIGIBYTE_DIR}"
log "  Pool: ${DGB_CKPOOL_DIR}"
log "  Stratum port: ${DGB_STRATUM_PORT}"
log "  NOTE: Only SHA256 algorithm is supported with CKPool"
