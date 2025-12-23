#!/bin/bash
# =============================================================================
# 13-install-monero.sh
# Install Monero (monerod) and monero-pool
#
# This installs:
# - monerod (Monero full node)
# - monero-pool (mining pool with PPLNS payouts and share tracking)
#
# Note: If using merge mining mode, the minotari_merge_mining_proxy
# will be used instead of monero-pool (installed in 14-install-tari.sh)
#
# monero-pool requires building from source with Monero libraries.
# =============================================================================

set -e

# Source configuration
source /opt/solo-pool/install-scripts/config.sh

# Validate config was loaded successfully
if [ "${CONFIG_LOADED:-}" != "true" ]; then
    echo "ERROR: Failed to load configuration from config.sh" >&2
    exit 1
fi

# Check if Monero pool is enabled
if [ "${ENABLE_MONERO_POOL}" != "true" ]; then
    log "Monero pool is disabled, skipping..."
    exit 0
fi

log "Installing Monero node v${MONERO_VERSION} and monero-pool..."

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

# Copy binaries (monerod + wallet tools for pool operation)
log "  Installing binaries..."
cp ${MONERO_EXTRACTED}/monerod ${MONERO_DIR}/bin/
cp ${MONERO_EXTRACTED}/monero-wallet-cli ${MONERO_DIR}/bin/
cp ${MONERO_EXTRACTED}/monero-wallet-rpc ${MONERO_DIR}/bin/

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
zmq-pub=tcp://127.0.0.1:${MONERO_ZMQ_PORT}
EOF

# Set permissions
chown -R ${POOL_USER}:${POOL_USER} ${MONERO_DIR}
chmod 600 ${MONERO_DIR}/monerod.conf

log "  monerod installed"

# =============================================================================
# 2. CREATE POOL WALLET
# =============================================================================
log "2. Creating Monero pool wallet..."

# Create wallet directory
mkdir -p ${MONERO_DIR}/wallet

# Generate a secure wallet password
XMR_WALLET_PASSWORD=$(apg -a 1 -m 32 -M NCL -n 1)

# Save the password securely
echo "${XMR_WALLET_PASSWORD}" > ${MONERO_DIR}/wallet/pool-wallet.password
chmod 600 ${MONERO_DIR}/wallet/pool-wallet.password

# Wait for monerod to be available (we need it to create the wallet)
# For now, create the wallet without daemon connection (offline creation)
# The wallet will sync when monero-wallet-rpc starts

log "  Generating new pool wallet..."

# Create wallet using monero-wallet-cli in non-interactive mode
# This generates a new wallet with a random seed
${MONERO_DIR}/bin/monero-wallet-cli \
    --generate-new-wallet=${MONERO_DIR}/wallet/pool-wallet \
    --password="${XMR_WALLET_PASSWORD}" \
    --mnemonic-language=English \
    --command exit 2>/dev/null

# Extract the wallet address from the wallet file
log "  Extracting wallet address..."
XMR_POOL_WALLET_ADDRESS=$(${MONERO_DIR}/bin/monero-wallet-cli \
    --wallet-file=${MONERO_DIR}/wallet/pool-wallet \
    --password="${XMR_WALLET_PASSWORD}" \
    --command address 2>/dev/null | grep -oP '^4[0-9A-Za-z]{94}' | head -1)

if [ -z "${XMR_POOL_WALLET_ADDRESS}" ]; then
    log_error "Failed to extract wallet address"
    exit 1
fi

# Save the wallet address
echo "${XMR_POOL_WALLET_ADDRESS}" > ${MONERO_DIR}/wallet/pool-wallet.address
chmod 644 ${MONERO_DIR}/wallet/pool-wallet.address

# Export the mnemonic seed for backup (CRITICAL!)
log "  Exporting mnemonic seed for backup..."
${MONERO_DIR}/bin/monero-wallet-cli \
    --wallet-file=${MONERO_DIR}/wallet/pool-wallet \
    --password="${XMR_WALLET_PASSWORD}" \
    --command "seed" 2>/dev/null | grep -A 25 "NOTE:" > ${MONERO_DIR}/wallet/SEED_BACKUP.txt

# Also try to get just the seed words
SEED_WORDS=$(${MONERO_DIR}/bin/monero-wallet-cli \
    --wallet-file=${MONERO_DIR}/wallet/pool-wallet \
    --password="${XMR_WALLET_PASSWORD}" \
    --command "seed" 2>/dev/null | grep -E '^[a-z]+ [a-z]+' | head -1)

if [ -n "${SEED_WORDS}" ]; then
    echo "" >> ${MONERO_DIR}/wallet/SEED_BACKUP.txt
    echo "Mnemonic Seed:" >> ${MONERO_DIR}/wallet/SEED_BACKUP.txt
    echo "${SEED_WORDS}" >> ${MONERO_DIR}/wallet/SEED_BACKUP.txt
fi

chmod 600 ${MONERO_DIR}/wallet/SEED_BACKUP.txt

# Create monero-wallet-rpc start script
log "  Creating monero-wallet-rpc start script..."
cat > ${MONERO_DIR}/start-wallet-rpc.sh << EOF
#!/bin/bash
# Monero Wallet RPC Start Script
# Used by payment processor to send payments to miners

exec ${MONERO_DIR}/bin/monero-wallet-rpc \\
    --wallet-file=${MONERO_DIR}/wallet/pool-wallet \\
    --password-file=${MONERO_DIR}/wallet/pool-wallet.password \\
    --rpc-bind-ip=127.0.0.1 \\
    --rpc-bind-port=${MONERO_WALLET_RPC_PORT} \\
    --daemon-address=127.0.0.1:${MONERO_RPC_PORT} \\
    --disable-rpc-login \\
    --trusted-daemon \\
    --log-file=${MONERO_DIR}/wallet/wallet-rpc.log \\
    --log-level=1
EOF

chmod +x ${MONERO_DIR}/start-wallet-rpc.sh

# Set ownership
chown -R ${POOL_USER}:${POOL_USER} ${MONERO_DIR}/wallet
chown ${POOL_USER}:${POOL_USER} ${MONERO_DIR}/start-wallet-rpc.sh

log_success "Pool wallet created"
log "  Address: ${XMR_POOL_WALLET_ADDRESS}"
log "  Wallet file: ${MONERO_DIR}/wallet/pool-wallet"
log "  Password file: ${MONERO_DIR}/wallet/pool-wallet.password"
log "  *** BACKUP ${MONERO_DIR}/wallet/SEED_BACKUP.txt IMMEDIATELY! ***"

# =============================================================================
# 3. INSTALL MONERO-POOL
# =============================================================================
# Only install monero-pool if mode is "monero_only"
# For merge mining, the Tari proxy handles stratum

if [ "${MONERO_TARI_MODE}" = "monero_only" ]; then
    log "3. Installing monero-pool (jtgrassie/monero-pool)..."

    # monero-pool requires building from source with Monero libraries
    # Dependencies: liblmdb-dev libevent-dev libjson-c-dev uuid-dev

    log "  Installing build dependencies..."
    run_cmd apt-get install -y liblmdb-dev libevent-dev libjson-c-dev uuid-dev

    cd /tmp

    # Clone Monero source (needed for building monero-pool)
    log "  Cloning Monero source for library build..."
    if [ -d "monero" ]; then
        rm -rf monero
    fi
    run_cmd git clone --recursive --depth 1 --branch v${MONERO_VERSION} https://github.com/monero-project/monero.git

    # Build Monero (needed for libmonero-crypto)
    log "  Building Monero libraries (this may take a while)..."
    cd monero
    run_cmd make release-static -j$(nproc)
    MONERO_ROOT=$(pwd)
    cd /tmp

    # Clone monero-pool
    log "  Cloning monero-pool..."
    if [ -d "monero-pool" ]; then
        rm -rf monero-pool
    fi
    run_cmd git clone https://github.com/jtgrassie/monero-pool.git
    cd monero-pool
    run_cmd git checkout ${MONERO_POOL_COMMIT}

    # Build monero-pool
    log "  Building monero-pool..."
    export MONERO_ROOT
    run_cmd make release

    # Install binary
    log "  Installing monero-pool..."
    mkdir -p ${XMR_MONERO_POOL_DIR}/bin
    mkdir -p ${XMR_MONERO_POOL_DIR}/data
    mkdir -p ${XMR_MONERO_POOL_DIR}/logs
    cp build/release/monero-pool ${XMR_MONERO_POOL_DIR}/bin/
    chmod +x ${XMR_MONERO_POOL_DIR}/bin/monero-pool

    # Cleanup build files
    cd /tmp
    rm -rf monero monero-pool

    # Create pool.conf configuration
    log "  Creating monero-pool configuration..."
    cat > ${XMR_MONERO_POOL_DIR}/pool.conf << EOF
# monero-pool configuration
# See: https://github.com/jtgrassie/monero-pool

# Pool wallet address (receives block rewards)
# Uses the generated pool wallet from /opt/solo-pool/node/monero/wallet/
pool-wallet = ${XMR_POOL_WALLET_ADDRESS}

# Stratum listen address and port
pool-start-diff = ${XMR_STARTING_DIFF}
pool-fixed-diff = 0
pool-fee = 0
pool-port = ${XMR_STRATUM_PORT}
pool-listen = 0.0.0.0:${XMR_STRATUM_PORT}

# Web UI disabled (API only via payment processor)
webui-listen =

# Monero daemon RPC
rpc-host = 127.0.0.1
rpc-port = ${MONERO_RPC_PORT}
rpc-timeout = 15

# Wallet RPC (for payouts)
wallet-rpc-host = 127.0.0.1
wallet-rpc-port = ${MONERO_WALLET_RPC_PORT}

# Data directory (LMDB database for shares)
data-dir = ${XMR_MONERO_POOL_DIR}/data

# Logging
log-level = 0
log-file = ${XMR_MONERO_POOL_DIR}/logs/pool.log

# Block template refresh interval (seconds)
block-notified = 0

# Payment processing
payment-threshold = 0
EOF

    chmod 600 ${XMR_MONERO_POOL_DIR}/pool.conf

    # Create start script
    log "  Creating monero-pool start script..."
    cat > ${XMR_MONERO_POOL_DIR}/start-monero-pool.sh << EOF
#!/bin/bash
# monero-pool Start Script
# Monero mining pool with PPLNS payouts

cd ${XMR_MONERO_POOL_DIR}
exec ${XMR_MONERO_POOL_DIR}/bin/monero-pool -c ${XMR_MONERO_POOL_DIR}/pool.conf
EOF

    chmod +x ${XMR_MONERO_POOL_DIR}/start-monero-pool.sh

    # Create setup notes
    cat > ${XMR_MONERO_POOL_DIR}/SETUP_NOTES.txt << EOF
monero-pool Setup Notes
=======================

monero-pool is a Monero mining pool with PPLNS payouts and share tracking.
https://github.com/jtgrassie/monero-pool

POOL WALLET (AUTO-GENERATED):
- Wallet Address: ${XMR_POOL_WALLET_ADDRESS}
- Wallet File: ${MONERO_DIR}/wallet/pool-wallet
- Password File: ${MONERO_DIR}/wallet/pool-wallet.password
- Seed Backup: ${MONERO_DIR}/wallet/SEED_BACKUP.txt

*** IMPORTANT: BACKUP THE SEED IMMEDIATELY! ***
The seed backup file contains your wallet recovery phrase.
If lost, you will lose access to all pool funds.

Requirements:
- monerod must be fully synced before starting monero-pool
- monero-wallet-rpc must be running for payouts

Starting Services (in order):
1. Start monerod: sudo systemctl start node-xmr-monerod
2. Wait for sync: Check with monero-cli status
3. Start wallet-rpc: sudo systemctl start wallet-xmr-rpc
4. Start monero-pool: sudo systemctl start pool-xmr-monero-pool

Miner Connection:
- Stratum: stratum+tcp://<server>:${XMR_STRATUM_PORT}
- Username: your Monero wallet address
- Password: worker name (optional)

API Endpoints:
- Stats: http://localhost:${MONERO_POOL_API_PORT}/stats
- Workers: http://localhost:${MONERO_POOL_API_PORT}/workers

Configuration:
- Pool config: ${XMR_MONERO_POOL_DIR}/pool.conf
- Share database: ${XMR_MONERO_POOL_DIR}/data/ (LMDB)
EOF

    # Set permissions
    chown -R ${POOL_USER}:${POOL_USER} ${XMR_MONERO_POOL_DIR}

    log_success "Monero node and monero-pool installed"
    log "  Node: ${MONERO_DIR}"
    log "  Pool: ${XMR_MONERO_POOL_DIR}"
    log "  Stratum port: ${XMR_STRATUM_PORT}"
    log "  API port: ${MONERO_POOL_API_PORT}"

else
    log "3. Skipping monero-pool (merge mining mode enabled)"
    log "  The minotari_merge_mining_proxy will handle stratum"
    log_success "Monero node and wallet installed (stratum via merge mining proxy)"
    log "  Node: ${MONERO_DIR}"
    log "  Wallet: ${MONERO_DIR}/wallet/pool-wallet"
    log "  *** BACKUP ${MONERO_DIR}/wallet/SEED_BACKUP.txt IMMEDIATELY! ***"
fi
