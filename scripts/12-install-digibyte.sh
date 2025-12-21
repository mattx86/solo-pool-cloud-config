#!/bin/bash
# =============================================================================
# 12-install-digibyte.sh
# Install DigiByte Core and CKPool for DGB (SHA256 only)
# =============================================================================

set -e

# Source configuration
source /opt/solo-pool/config.sh

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
cat > ${DIGIBYTE_DIR}/digibyte.conf << EOF
# DigiByte Core Configuration for Solo Mining Pool

# Network
server=1
daemon=0
txindex=1
listen=1

# RPC Configuration
rpcuser=digibyterpc
rpcpassword=$(openssl rand -hex 32)
rpcallowip=127.0.0.1
rpcbind=127.0.0.1
rpcport=14022

# ZMQ for block notifications
zmqpubhashblock=tcp://127.0.0.1:28336
zmqpubhashtx=tcp://127.0.0.1:28337

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
log "2. Building CKPool for DigiByte..."

cd /tmp

# Clone CKPool
log "  Cloning CKPool..."
rm -rf ckpool-dgb
run_cmd git clone https://bitbucket.org/ckolivas/ckpool.git ckpool-dgb

cd ckpool-dgb

# Build CKPool
log "  Building CKPool..."
run_cmd ./autogen.sh
run_cmd ./configure --prefix=${CKPOOL_DGB_DIR}
run_cmd make -j$(nproc)
run_cmd make install

# Copy binary
cp src/ckpool ${CKPOOL_DGB_DIR}/bin/
cp src/ckpmsg ${CKPOOL_DGB_DIR}/bin/
cp src/notifier ${CKPOOL_DGB_DIR}/bin/

# Cleanup
cd /tmp
rm -rf ckpool-dgb

# Create CKPool configuration for DGB
log "  Creating CKPool configuration..."

# Get RPC password from digibyte.conf
DGB_RPC_PASS=$(grep rpcpassword ${DIGIBYTE_DIR}/digibyte.conf | cut -d'=' -f2)

cat > ${CKPOOL_DGB_DIR}/ckpool.conf << EOF
{
    "btcd" : [
        {
            "url" : "127.0.0.1:14022",
            "auth" : "digibyterpc",
            "pass" : "${DGB_RPC_PASS}",
            "notify" : true
        }
    ],
    "btcaddress" : "${DGB_WALLET_ADDRESS}",
    "btcsig" : "Solo Pool DGB",
    "blockpoll" : 100,
    "update_interval" : 30,
    "serverurl" : [
        "0.0.0.0:${DGB_STRATUM_PORT}"
    ],
    "mindiff" : 1,
    "startdiff" : 16,
    "maxdiff" : 0,
    "logdir" : "${CKPOOL_DGB_DIR}/logs"
}
EOF

# Set permissions
chown -R ${POOL_USER}:${POOL_USER} ${CKPOOL_DGB_DIR}
chmod 600 ${CKPOOL_DGB_DIR}/ckpool.conf

log_success "DigiByte Core and CKPool installed"
log "  Node: ${DIGIBYTE_DIR}"
log "  Pool: ${CKPOOL_DGB_DIR}"
log "  Stratum port: ${DGB_STRATUM_PORT}"
log "  NOTE: Only SHA256 algorithm is supported with CKPool"
