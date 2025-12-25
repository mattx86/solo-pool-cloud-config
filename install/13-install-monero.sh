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
source /opt/solo-pool/install/config.sh

# Validate config was loaded successfully
if [ "${CONFIG_LOADED:-}" != "true" ]; then
    echo "ERROR: Failed to load configuration from config.sh" >&2
    exit 1
fi

# Check if Monero pool is enabled (merge, merged, or monero_only modes)
case "${ENABLE_MONERO_TARI_POOL}" in
    merge|merged|monero_only)
        ;;
    *)
        log "Monero pool is disabled, skipping..."
        exit 0
        ;;
esac

log "Installing Monero node v${MONERO_VERSION} and monero-pool..."

# Template directory
TEMPLATE_DIR="/opt/solo-pool/install/files/config"

# =============================================================================
# 1. INSTALL MONEROD
# =============================================================================
log "1. Installing Monero v${MONERO_VERSION}..."

# Create standardized directory structure
log "  Creating directory structure..."
mkdir -p ${MONERO_DIR}/bin
mkdir -p ${MONERO_DIR}/config
mkdir -p ${MONERO_DIR}/data
mkdir -p ${MONERO_DIR}/logs

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

# Create monerod.conf from template
log "  Creating monerod configuration from template..."

# Determine P2P settings based on inbound config
if [ "${ENABLE_INBOUND_P2P}" = "true" ]; then
    export XMR_P2P_BIND="0.0.0.0"
    export XMR_IN_PEERS=""
else
    export XMR_P2P_BIND="0.0.0.0"
    export XMR_IN_PEERS="in-peers=0"
fi

# Determine network mode settings
if [ "${NETWORK_MODE}" = "testnet" ]; then
    export NETWORK_FLAG="stagenet=1"
    export EFFECTIVE_RPC_PORT="38081"
    export XMR_P2P_PORT="38080"
    export XMR_WALLET_ADDR_REGEX='^5[0-9A-Za-z]{94}'
    log "  Network mode: STAGENET"
else
    export NETWORK_FLAG=""
    export EFFECTIVE_RPC_PORT="${MONERO_RPC_PORT}"
    export XMR_P2P_PORT="18080"
    export XMR_WALLET_ADDR_REGEX='^4[0-9A-Za-z]{94}'
    log "  Network mode: MAINNET"
fi

# Export variables for template
export MONERO_DIR MONERO_RPC_PORT MONERO_ZMQ_PORT NETWORK_FLAG XMR_P2P_PORT

# Generate config from template
envsubst < "${TEMPLATE_DIR}/monerod.conf.template" > ${MONERO_DIR}/config/monerod.conf

# Set permissions
chown -R ${POOL_USER}:${POOL_USER} ${MONERO_DIR}
chmod 600 ${MONERO_DIR}/config/monerod.conf

log "  monerod installed"

# =============================================================================
# 2. CREATE POOL WALLET
# =============================================================================
log "2. Creating Monero pool wallet..."

# Create standardized wallet directory structure
mkdir -p ${MONERO_DIR}/wallet/keys
mkdir -p ${MONERO_DIR}/wallet/data
mkdir -p ${MONERO_DIR}/wallet/logs

# Generate a secure wallet password
XMR_WALLET_PASSWORD=$(apg -a 1 -m 32 -M NCL -n 1)

# Save the password securely
echo "${XMR_WALLET_PASSWORD}" > ${MONERO_DIR}/wallet/keys/pool-wallet.password
chmod 600 ${MONERO_DIR}/wallet/keys/pool-wallet.password

# Wait for monerod to be available (we need it to create the wallet)
# For now, create the wallet without daemon connection (offline creation)
# The wallet will sync when monero-wallet-rpc starts

log "  Generating new pool wallet..."

# Create wallet using monero-wallet-cli in non-interactive mode
# This generates a new wallet with a random seed
# Add --stagenet flag if in testnet mode
if [ "${NETWORK_MODE}" = "testnet" ]; then
    WALLET_NETWORK_FLAG="--stagenet"
else
    WALLET_NETWORK_FLAG=""
fi

# Generate wallet - the --command flag runs the specified command then exits
# Using "address" to generate wallet and display address, then exits automatically
${MONERO_DIR}/bin/monero-wallet-cli ${WALLET_NETWORK_FLAG} \
    --generate-new-wallet=${MONERO_DIR}/wallet/keys/pool-wallet \
    --password="${XMR_WALLET_PASSWORD}" \
    --mnemonic-language=English \
    --command "address" 2>/dev/null

# Extract the wallet address from the wallet file
log "  Extracting wallet address..."
export XMR_POOL_WALLET_ADDRESS=$(${MONERO_DIR}/bin/monero-wallet-cli ${WALLET_NETWORK_FLAG} \
    --wallet-file=${MONERO_DIR}/wallet/keys/pool-wallet \
    --password="${XMR_WALLET_PASSWORD}" \
    --command address 2>/dev/null | grep -oP "${XMR_WALLET_ADDR_REGEX}" | head -1)

if [ -z "${XMR_POOL_WALLET_ADDRESS}" ]; then
    log_error "Failed to extract wallet address"
    exit 1
fi

# Save the wallet address
echo "${XMR_POOL_WALLET_ADDRESS}" > ${MONERO_DIR}/wallet/keys/pool-wallet.address
chmod 644 ${MONERO_DIR}/wallet/keys/pool-wallet.address

# Export the mnemonic seed for backup (CRITICAL!)
log "  Exporting mnemonic seed for backup..."
${MONERO_DIR}/bin/monero-wallet-cli ${WALLET_NETWORK_FLAG} \
    --wallet-file=${MONERO_DIR}/wallet/keys/pool-wallet \
    --password="${XMR_WALLET_PASSWORD}" \
    --command "seed" 2>/dev/null | grep -A 25 "NOTE:" > ${MONERO_DIR}/wallet/keys/SEED_BACKUP.txt

# Also try to get just the seed words
SEED_WORDS=$(${MONERO_DIR}/bin/monero-wallet-cli ${WALLET_NETWORK_FLAG} \
    --wallet-file=${MONERO_DIR}/wallet/keys/pool-wallet \
    --password="${XMR_WALLET_PASSWORD}" \
    --command "seed" 2>/dev/null | grep -E '^[a-z]+ [a-z]+' | head -1)

if [ -n "${SEED_WORDS}" ]; then
    echo "" >> ${MONERO_DIR}/wallet/keys/SEED_BACKUP.txt
    echo "Mnemonic Seed:" >> ${MONERO_DIR}/wallet/keys/SEED_BACKUP.txt
    echo "${SEED_WORDS}" >> ${MONERO_DIR}/wallet/keys/SEED_BACKUP.txt
fi

chmod 600 ${MONERO_DIR}/wallet/keys/SEED_BACKUP.txt

# Create monero-wallet-rpc start script from template
log "  Creating monero-wallet-rpc start script from template..."
export MONERO_WALLET_RPC_PORT
envsubst < "${TEMPLATE_DIR}/start-wallet-rpc.sh.template" > ${MONERO_DIR}/bin/start-wallet-rpc.sh
chmod +x ${MONERO_DIR}/bin/start-wallet-rpc.sh

# Set ownership
chown -R ${POOL_USER}:${POOL_USER} ${MONERO_DIR}/wallet

log_success "Pool wallet created"
log "  Address: ${XMR_POOL_WALLET_ADDRESS}"
log "  Wallet file: ${MONERO_DIR}/wallet/keys/pool-wallet"
log "  Password file: ${MONERO_DIR}/wallet/keys/pool-wallet.password"
log "  *** BACKUP ${MONERO_DIR}/wallet/keys/SEED_BACKUP.txt IMMEDIATELY! ***"

# =============================================================================
# 3. INSTALL MONERO-POOL
# =============================================================================
# Only install monero-pool if mode is "monero_only"
# For merge mining, the Tari proxy handles stratum

if [ "${ENABLE_MONERO_TARI_POOL}" = "monero_only" ]; then
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
    mkdir -p ${XMR_MONERO_POOL_DIR}/config
    mkdir -p ${XMR_MONERO_POOL_DIR}/data
    mkdir -p ${XMR_MONERO_POOL_DIR}/logs
    cp build/release/monero-pool ${XMR_MONERO_POOL_DIR}/bin/
    chmod +x ${XMR_MONERO_POOL_DIR}/bin/monero-pool

    # Cleanup build files
    cd /tmp
    rm -rf monero monero-pool

    # Create pool.conf configuration from template
    log "  Creating monero-pool configuration from template..."
    # Map config variable to template variable name
    export XMR_STARTING_DIFF="${XMR_START_DIFFICULTY:-4500}"
    export XMR_STRATUM_PORT XMR_MONERO_POOL_DIR MONERO_RPC_PORT MONERO_WALLET_RPC_PORT
    export XMR_POOL_WALLET_ADDRESS
    envsubst < "${TEMPLATE_DIR}/monero-pool.conf.template" > ${XMR_MONERO_POOL_DIR}/config/pool.conf
    chmod 600 ${XMR_MONERO_POOL_DIR}/config/pool.conf

    # Create start script from template
    log "  Creating monero-pool start script from template..."
    envsubst < "${TEMPLATE_DIR}/start-monero-pool.sh.template" > ${XMR_MONERO_POOL_DIR}/bin/start-monero-pool.sh
    chmod +x ${XMR_MONERO_POOL_DIR}/bin/start-monero-pool.sh

    # Create setup notes
    cat > ${XMR_MONERO_POOL_DIR}/SETUP_NOTES.txt << EOF
monero-pool Setup Notes
=======================

monero-pool is a Monero mining pool with PPLNS payouts and share tracking.
https://github.com/jtgrassie/monero-pool

POOL WALLET (AUTO-GENERATED):
- Wallet Address: ${XMR_POOL_WALLET_ADDRESS}
- Wallet File: ${MONERO_DIR}/wallet/keys/pool-wallet
- Password File: ${MONERO_DIR}/wallet/keys/pool-wallet.password
- Seed Backup: ${MONERO_DIR}/wallet/keys/SEED_BACKUP.txt

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
- Pool config: ${XMR_MONERO_POOL_DIR}/config/pool.conf
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
    log "  Wallet: ${MONERO_DIR}/wallet/keys/pool-wallet"
    log "  *** BACKUP ${MONERO_DIR}/wallet/keys/SEED_BACKUP.txt IMMEDIATELY! ***"
fi
