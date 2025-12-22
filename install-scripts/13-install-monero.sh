#!/bin/bash
# =============================================================================
# 13-install-monero.sh
# Install Monero (monerod) and P2Pool
#
# This installs:
# - monerod (Monero full node)
# - P2Pool (decentralized mining pool)
#
# Note: If using merge mining mode, the minotari_merge_mining_proxy
# will be used instead of P2Pool (installed in 14-install-tari.sh)
# =============================================================================

set -e

# Source configuration
source /opt/solo-pool/install-scripts/config.sh

# Check if Monero pool is enabled
if [ "${ENABLE_MONERO_POOL}" != "true" ]; then
    log "Monero pool is disabled, skipping..."
    exit 0
fi

log "Installing Monero node v${MONERO_VERSION} and P2Pool v${P2POOL_VERSION}..."

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

# Copy binaries (only monerod needed for pool operation)
log "  Installing binaries..."
cp ${MONERO_EXTRACTED}/monerod ${MONERO_DIR}/bin/

# Cleanup
rm -rf monero.tar.bz2 ${MONERO_EXTRACTED}

# Create monerod.conf
log "  Creating monerod configuration..."

# Determine P2P settings based on inbound config
if [ "${ENABLE_INBOUND_P2P}" = "true" ]; then
    XMR_P2P_BIND="0.0.0.0"
    XMR_IN_PEERS=""
else
    XMR_P2P_BIND="0.0.0.0"
    XMR_IN_PEERS="in-peers=0"
fi

cat > ${MONERO_DIR}/monerod.conf << EOF
# Monero Daemon Configuration for Solo Mining Pool

# Data directory
data-dir=${MONERO_DIR}/data

# Network
p2p-bind-ip=${XMR_P2P_BIND}
p2p-bind-port=18080
no-igd=1
${XMR_IN_PEERS}

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
# 2. INSTALL P2POOL
# =============================================================================
# Only install P2Pool if mode is "monero_only"
# For merge mining, the Tari proxy handles stratum

if [ "${MONERO_TARI_MODE}" = "monero_only" ]; then
    log "2. Installing P2Pool v${P2POOL_VERSION}..."

    cd /tmp

    # Download P2Pool pre-built binary
    P2POOL_URL="https://github.com/SChernykh/p2pool/releases/download/v${P2POOL_VERSION}/p2pool-v${P2POOL_VERSION}-linux-x64.tar.gz"

    log "  Downloading P2Pool v${P2POOL_VERSION}..."
    run_cmd wget -q "${P2POOL_URL}" -O p2pool.tar.gz

    if [ $? -ne 0 ]; then
        log_error "Failed to download P2Pool v${P2POOL_VERSION}"
        exit 1
    fi

    # Extract
    log "  Extracting..."
    mkdir -p p2pool-extract
    tar -xzf p2pool.tar.gz -C p2pool-extract

    # Install binary
    log "  Installing binary..."
    mkdir -p ${XMR_P2POOL_DIR}/bin
    cp p2pool-extract/p2pool-v${P2POOL_VERSION}-linux-x64/p2pool ${XMR_P2POOL_DIR}/bin/
    chmod +x ${XMR_P2POOL_DIR}/bin/p2pool

    # Cleanup
    rm -rf p2pool.tar.gz p2pool-extract

    # Create directories
    mkdir -p ${XMR_P2POOL_DIR}/data
    mkdir -p ${XMR_P2POOL_DIR}/logs

    # Create start script
    log "  Creating P2Pool start script..."

    # Determine P2Pool P2P settings
    if [ "${ENABLE_INBOUND_P2P}" = "true" ]; then
        P2POOL_P2P_OPTS="--p2p 0.0.0.0:37889"
    else
        P2POOL_P2P_OPTS="--p2p 127.0.0.1:37889 --no-dns"
    fi

    cat > ${XMR_P2POOL_DIR}/start-p2pool.sh << EOF
#!/bin/bash
# P2Pool Start Script
# Decentralized Monero mining pool

exec ${XMR_P2POOL_DIR}/bin/p2pool \\
    --host 127.0.0.1 \\
    --rpc-port 18081 \\
    --zmq-port 18083 \\
    --wallet ${XMR_WALLET_ADDRESS} \\
    --stratum 0.0.0.0:${XMR_STRATUM_PORT} \\
    ${P2POOL_P2P_OPTS} \\
    --data-api ${XMR_P2POOL_DIR}/data \\
    --local-api \\
    --log-level 2
EOF

    chmod +x ${XMR_P2POOL_DIR}/start-p2pool.sh

    # Create setup notes
    cat > ${XMR_P2POOL_DIR}/SETUP_NOTES.txt << EOF
P2Pool Setup Notes
==================

P2Pool is a decentralized mining pool for Monero. Unlike traditional pools,
there is no central server - miners work together on a side blockchain.

Requirements:
- monerod must be fully synced before starting P2Pool
- monerod must have ZMQ enabled (zmq-pub=tcp://127.0.0.1:18083)

Starting P2Pool:
1. Ensure monerod is running and synced
2. Run: sudo systemctl start pool-xmr-p2pool
   Or manually: ${XMR_P2POOL_DIR}/start-p2pool.sh

Miner Connection:
- Stratum: localhost:${XMR_STRATUM_PORT}
- Use your Monero wallet address as username
- Password can be anything (or worker name)

Network Ports:
- Stratum: ${XMR_STRATUM_PORT} (miners connect here)
- P2P: 37889 (P2Pool sidechain communication)

Commands:
- Check status: curl http://localhost:${XMR_STRATUM_PORT}/local/stats
- View pool stats: curl http://localhost:${XMR_STRATUM_PORT}/pool/stats

Note: P2Pool has no pool fees and payouts come directly from the blockchain.
EOF

    # Set permissions
    chown -R ${POOL_USER}:${POOL_USER} ${XMR_P2POOL_DIR}
    chmod 600 ${XMR_P2POOL_DIR}/start-p2pool.sh

    log_success "Monero node and P2Pool installed"
    log "  Node: ${MONERO_DIR}"
    log "  Pool: ${XMR_P2POOL_DIR}"
    log "  Stratum port: ${XMR_STRATUM_PORT}"
    log "  P2P port: 37889"

else
    log "2. Skipping P2Pool (merge mining mode enabled)"
    log "  The minotari_merge_mining_proxy will handle stratum"
    log_success "Monero node installed (stratum via merge mining proxy)"
    log "  Node: ${MONERO_DIR}"
fi
