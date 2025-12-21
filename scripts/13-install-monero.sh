#!/bin/bash
# =============================================================================
# 13-install-monero.sh
# Install Monero (monerod) and monero-stratum
#
# This installs:
# - monerod (Monero full node)
# - monero-stratum (solo mining stratum server)
#
# Note: If using merge mining mode, the minotari_merge_mining_proxy
# will be used instead of monero-stratum (installed in 14-install-tari.sh)
# =============================================================================

set -e

# Source configuration
source /opt/solo-pool/config.sh

# Check if Monero pool is enabled
if [ "${ENABLE_MONERO_POOL}" != "true" ]; then
    log "Monero pool is disabled, skipping..."
    exit 0
fi

log "Installing Monero node and stratum..."

# =============================================================================
# 1. INSTALL MONEROD
# =============================================================================
log "1. Installing Monero v${MONERO_VERSION}..."

cd /tmp

# Download Monero
MONERO_URL="https://downloads.getmonero.org/cli/monero-linux-x64-v${MONERO_VERSION}.tar.bz2"

log "  Downloading Monero..."
run_cmd wget -q "${MONERO_URL}" -O monero.tar.bz2

# Extract and install
log "  Extracting..."
run_cmd tar -xjf monero.tar.bz2

# Find extracted directory (name varies)
MONERO_EXTRACTED=$(ls -d monero-x86_64-linux-gnu-* 2>/dev/null | head -1)

# Copy binaries
log "  Installing binaries..."
cp ${MONERO_EXTRACTED}/monerod ${MONERO_DIR}/bin/
cp ${MONERO_EXTRACTED}/monero-wallet-cli ${MONERO_DIR}/bin/
cp ${MONERO_EXTRACTED}/monero-wallet-rpc ${MONERO_DIR}/bin/

# Cleanup
rm -rf monero.tar.bz2 ${MONERO_EXTRACTED}

# Create monerod.conf
log "  Creating monerod configuration..."
cat > ${MONERO_DIR}/monerod.conf << EOF
# Monero Daemon Configuration for Solo Mining Pool

# Data directory
data-dir=${MONERO_DIR}/data

# Network
p2p-bind-ip=0.0.0.0
p2p-bind-port=18080
no-igd=1

# RPC
rpc-bind-ip=127.0.0.1
rpc-bind-port=18081
confirm-external-bind=1
restricted-rpc=0

# Mining
# Enable stratum server mode (for merge mining proxy)
# For solo via monero-stratum, this is not needed

# Logging
log-level=0
log-file=${MONERO_DIR}/data/monerod.log
max-log-file-size=10485760

# Performance
db-sync-mode=safe
block-sync-size=10
prep-blocks-threads=4

# ZMQ for notifications
zmq-pub=tcp://127.0.0.1:18083
EOF

# Set permissions
chown -R ${POOL_USER}:${POOL_USER} ${MONERO_DIR}
chmod 600 ${MONERO_DIR}/monerod.conf

log "  monerod installed"

# =============================================================================
# 2. BUILD AND INSTALL MONERO-STRATUM
# =============================================================================
# Only install monero-stratum if mode is "monero_only"
# For merge mining, the Tari proxy handles stratum

if [ "${MONERO_TARI_MODE}" = "monero_only" ]; then
    log "2. Building monero-stratum for solo Monero mining..."

    # Ensure Go is in PATH
    export PATH=$PATH:/usr/local/go/bin
    export GOPATH=/root/go

    cd /tmp

    # Clone monero-stratum
    log "  Cloning monero-stratum..."
    rm -rf monero-stratum
    run_cmd git clone https://github.com/sammy007/monero-stratum.git

    cd monero-stratum

    # Build
    log "  Building monero-stratum..."
    run_cmd go build -o monero-stratum .

    # Install
    cp monero-stratum ${MONERO_STRATUM_DIR}/bin/

    # Cleanup
    cd /tmp
    rm -rf monero-stratum

    # Create configuration
    log "  Creating monero-stratum configuration..."
    cat > ${MONERO_STRATUM_DIR}/config.json << EOF
{
    "address": "${XMR_WALLET_ADDRESS}",
    "bypassAddressValidation": false,
    "bypassShareValidation": false,

    "threads": 2,

    "estimationWindow": "15m",
    "luckWindow": "24h",
    "largeLuckWindow": "72h",

    "stratum": {
        "paymentId": {
            "addressSeparator": "+"
        },
        "fixedDiff": {
            "addressSeparator": "."
        },
        "workerID": {
            "addressSeparator": "."
        },
        "timeout": "15m",
        "healthCheck": true,
        "maxFails": 100,
        "listen": [
            {
                "host": "0.0.0.0",
                "port": ${XMR_STRATUM_PORT},
                "diff": 5000,
                "maxConn": 32768,
                "tls": false
            }
        ]
    },

    "daemon": {
        "host": "127.0.0.1",
        "port": 18081,
        "timeout": "10s"
    },

    "api": {
        "enabled": false,
        "listen": "127.0.0.1:8080"
    },

    "upstream": [
        {
            "name": "Local",
            "host": "127.0.0.1",
            "port": 18081,
            "timeout": "10s"
        }
    ],

    "redis": {
        "enabled": false
    },

    "newrelicEnabled": false
}
EOF

    # Set permissions
    chown -R ${POOL_USER}:${POOL_USER} ${MONERO_STRATUM_DIR}
    chmod 600 ${MONERO_STRATUM_DIR}/config.json

    log_success "Monero node and stratum installed"
    log "  Node: ${MONERO_DIR}"
    log "  Pool: ${MONERO_STRATUM_DIR}"
    log "  Stratum port: ${XMR_STRATUM_PORT}"

else
    log "2. Skipping monero-stratum (merge mining mode enabled)"
    log "  The minotari_merge_mining_proxy will handle stratum"
    log_success "Monero node installed (stratum via merge mining proxy)"
    log "  Node: ${MONERO_DIR}"
fi
