#!/bin/bash
# =============================================================================
# 15-install-aleo.sh
# Install ALEO snarkOS Node and ALEO Pool Server for Solo Mining
#
# This installs:
# - snarkOS: ALEO network node (connects to ALEO network)
# - aleo-pool-server: Stratum server for ASIC miners to connect to
#
# Architecture:
#   ASIC Miner --> aleo-pool-server (stratum) --> snarkOS (node) --> ALEO Network
#
# The pool server provides a stratum interface for ALEO ASICs (Goldshell, IceRiver, etc.)
# to connect and submit proofs. Rewards go to the auto-generated pool wallet.
# =============================================================================

set -e

# Source configuration
source /opt/solo-pool/install/config.sh

# Validate config was loaded successfully
if [ "${CONFIG_LOADED:-}" != "true" ]; then
    echo "ERROR: Failed to load configuration from config.sh" >&2
    exit 1
fi

# Check if ALEO pool is enabled
if [ "${ENABLE_ALEO_POOL}" != "true" ]; then
    log "ALEO pool is disabled, skipping..."
    exit 0
fi

log "Installing ALEO snarkOS v${SNARKOS_VERSION} and ALEO Pool Server..."

# Template directory
TEMPLATE_DIR="/opt/solo-pool/install/files/config"

# =============================================================================
# 1. PREREQUISITES
# =============================================================================
log "1. Verifying ALEO prerequisites..."

# Rust should already be installed by 05-install-dependencies.sh
if [ -f "/root/.cargo/env" ]; then
    source /root/.cargo/env
    log "  Rust toolchain ready"
else
    log_error "Rust not found. Ensure 05-install-dependencies.sh ran successfully."
    exit 1
fi

# Verify clang/llvm are installed (should be from 05-install-dependencies.sh)
if ! command -v clang &> /dev/null; then
    log_error "clang not found. Ensure 05-install-dependencies.sh ran successfully."
    exit 1
fi

log "  Prerequisites verified"

# =============================================================================
# 2. BUILD SNARKOS FROM SOURCE
# =============================================================================
log "2. Building snarkOS v${SNARKOS_VERSION} from source..."
log "  This may take 10-20 minutes..."

cd /tmp

# Clone snarkOS at specific version tag
log "  Cloning snarkOS v${SNARKOS_VERSION}..."
rm -rf snarkOS
run_cmd git clone --depth 1 --branch v${SNARKOS_VERSION} https://github.com/ProvableHQ/snarkOS.git

if [ $? -ne 0 ]; then
    log_error "Failed to clone snarkOS v${SNARKOS_VERSION}"
    exit 1
fi

cd snarkOS

# Build snarkOS
log "  Building snarkOS (this takes a while)..."
run_cmd cargo build --release

# Create standardized directory structure
log "  Creating directory structure..."
mkdir -p ${ALEO_DIR}/bin
mkdir -p ${ALEO_DIR}/config
mkdir -p ${ALEO_DIR}/data
mkdir -p ${ALEO_DIR}/logs

# Install binaries
log "  Installing snarkOS binary..."
cp target/release/snarkos ${ALEO_DIR}/bin/

# Cleanup (build artifacts are large)
cd /tmp
rm -rf snarkOS

log "  snarkOS v${SNARKOS_VERSION} built and installed"

# =============================================================================
# 3. BUILD ALEO POOL SERVER FROM SOURCE
# =============================================================================
log "3. Building ALEO Pool Server (commit ${ALEO_POOL_COMMIT:0:8})..."
log "  This may take 5-10 minutes..."

cd /tmp

# Clone aleo-pool-server at specific commit
log "  Cloning aleo-pool-server..."
rm -rf aleo-pool-server
run_cmd git clone https://github.com/HarukaMa/aleo-pool-server.git

if [ $? -ne 0 ]; then
    log_error "Failed to clone aleo-pool-server"
    exit 1
fi

cd aleo-pool-server

# Checkout specific commit for reproducibility
log "  Checking out commit ${ALEO_POOL_COMMIT:0:8}..."
run_cmd git checkout ${ALEO_POOL_COMMIT}

if [ $? -ne 0 ]; then
    log_error "Failed to checkout aleo-pool-server commit ${ALEO_POOL_COMMIT}"
    exit 1
fi

# Build aleo-pool-server
log "  Building aleo-pool-server..."
run_cmd cargo build --release

# Install binary
log "  Installing aleo-pool-server binary..."
mkdir -p ${ALEO_POOL_DIR}/bin
cp target/release/aleo-pool-server ${ALEO_POOL_DIR}/bin/

# Cleanup
cd /tmp
rm -rf aleo-pool-server

log "  ALEO Pool Server built and installed"

# =============================================================================
# 4. GENERATE POOL WALLET KEYPAIR
# =============================================================================
log "4. Generating ALEO pool wallet keypair..."

# Create standardized wallet directory structure
mkdir -p ${ALEO_DIR}/wallet/keys
mkdir -p ${ALEO_DIR}/wallet/data

# Generate new ALEO account using snarkos
log "  Creating new ALEO account..."
ACCOUNT_OUTPUT=$(${ALEO_DIR}/bin/snarkos account new 2>&1)

# Extract private key, view key, and address from output
ALEO_PRIVATE_KEY=$(echo "${ACCOUNT_OUTPUT}" | grep "Private Key" | awk '{print $NF}')
ALEO_VIEW_KEY=$(echo "${ACCOUNT_OUTPUT}" | grep "View Key" | awk '{print $NF}')
ALEO_POOL_ADDRESS=$(echo "${ACCOUNT_OUTPUT}" | grep "Address" | awk '{print $NF}')

if [ -z "${ALEO_PRIVATE_KEY}" ] || [ -z "${ALEO_POOL_ADDRESS}" ]; then
    log_error "Failed to generate ALEO account"
    log_error "Output: ${ACCOUNT_OUTPUT}"
    exit 1
fi

# Save keys securely
cat > ${ALEO_DIR}/wallet/keys/pool-wallet.keys << EOF
# ALEO Pool Wallet Keys
# *** KEEP THIS FILE SECURE - BACKUP IMMEDIATELY! ***
# Generated: $(date)

Private Key: ${ALEO_PRIVATE_KEY}
View Key: ${ALEO_VIEW_KEY}
Address: ${ALEO_POOL_ADDRESS}
EOF

chmod 600 ${ALEO_DIR}/wallet/keys/pool-wallet.keys

# Save just the address for easy reference
echo "${ALEO_POOL_ADDRESS}" > ${ALEO_DIR}/wallet/keys/pool-wallet.address
chmod 644 ${ALEO_DIR}/wallet/keys/pool-wallet.address

# Save private key separately for payment processor
echo "${ALEO_PRIVATE_KEY}" > ${ALEO_DIR}/wallet/keys/pool-wallet.privatekey
chmod 600 ${ALEO_DIR}/wallet/keys/pool-wallet.privatekey

log_success "ALEO pool wallet generated"
log "  Address: ${ALEO_POOL_ADDRESS}"
log "  Keys file: ${ALEO_DIR}/wallet/keys/pool-wallet.keys"
log "  *** BACKUP ${ALEO_DIR}/wallet/keys/pool-wallet.keys IMMEDIATELY! ***"

# =============================================================================
# 5. CONFIGURE SNARKOS NODE
# =============================================================================
log "5. Configuring snarkOS node..."

# Determine P2P listen address based on inbound config
if [ "${ENABLE_INBOUND_P2P}" = "true" ]; then
    export ALEO_LISTEN="0.0.0.0"
else
    export ALEO_LISTEN="127.0.0.1"
fi

# Export variables for template
export ALEO_DIR ALEO_REST_PORT

# Create snarkOS node start script from template
log "  Creating snarkOS start script from template..."
envsubst < "${TEMPLATE_DIR}/start-aleo-node.sh.template" > ${ALEO_DIR}/bin/start-node.sh
chmod +x ${ALEO_DIR}/bin/start-node.sh

log "  snarkOS node configured"

# =============================================================================
# 6. CONFIGURE ALEO POOL SERVER
# =============================================================================
log "6. Configuring ALEO Pool Server..."

# Create standardized directory structure (bin/ was created earlier during build)
mkdir -p ${ALEO_POOL_DIR}/bin
mkdir -p ${ALEO_POOL_DIR}/config
mkdir -p ${ALEO_POOL_DIR}/data
mkdir -p ${ALEO_POOL_DIR}/logs

# ALEO_POOL_ADDRESS was set during keypair generation
log "  Using generated pool address: ${ALEO_POOL_ADDRESS:0:30}..."

# Export variables for templates
export ALEO_STRATUM_PORT ALEO_REST_PORT ALEO_POOL_DIR ALEO_POOL_ADDRESS ALEO_PRIVATE_KEY

# Create pool server configuration from template
log "  Creating pool server configuration from template..."
envsubst < "${TEMPLATE_DIR}/aleo-pool.toml.template" > ${ALEO_POOL_DIR}/config/config.toml

# Create pool server start script from template
log "  Creating pool server start script from template..."
envsubst < "${TEMPLATE_DIR}/start-aleo-pool.sh.template" > ${ALEO_POOL_DIR}/bin/start-pool.sh
chmod +x ${ALEO_POOL_DIR}/bin/start-pool.sh

log "  ALEO Pool Server configured"

# =============================================================================
# 7. CREATE SETUP NOTES
# =============================================================================
log "7. Creating setup notes..."

cat > ${ALEO_DIR}/SETUP_NOTES.txt << EOF
ALEO Solo Mining Pool Setup Notes
==================================

This installation includes:
1. snarkOS - ALEO network node
2. aleo-pool-server - Stratum server for ASIC miners

Architecture:
  Your ASIC --> Pool Server (stratum:${ALEO_STRATUM_PORT}) --> snarkOS (node) --> ALEO Network

POOL WALLET (AUTO-GENERATED):
- Address: ${ALEO_POOL_ADDRESS}
- Private Key: ${ALEO_DIR}/wallet/keys/pool-wallet.privatekey
- Keys Backup: ${ALEO_DIR}/wallet/keys/pool-wallet.keys

*** IMPORTANT: BACKUP ${ALEO_DIR}/wallet/keys/pool-wallet.keys IMMEDIATELY! ***
This file contains your private key. If lost, you lose access to all pool funds.

DIRECTORIES:
- Node: ${ALEO_DIR}
- Pool: ${ALEO_POOL_DIR}

STARTING SERVICES:
1. Start the node first:
   sudo systemctl start node-aleo-snarkos

2. Wait for sync, then start the pool:
   sudo systemctl start pool-aleo

ASIC MINER CONFIGURATION:
- Stratum URL: stratum+tcp://YOUR_SERVER_IP:${ALEO_STRATUM_PORT}
- Worker: Your miner name (any identifier)
- Password: x (or leave blank)

NETWORK PORTS:
- P2P: 4130 (ALEO network connectivity)
- REST API: 3030 (internal, localhost only)
- Stratum: ${ALEO_STRATUM_PORT} (miners connect here)

FIREWALL:
To allow miners to connect:
  sudo ufw allow ${ALEO_STRATUM_PORT}/tcp

If you need inbound P2P (not required for mining):
  sudo ufw allow 4130/tcp

LOGS:
- Node: ${ALEO_DIR}/logs/snarkos.log
- Pool: ${ALEO_POOL_DIR}/logs/pool.log

SUPPORTED ASIC MINERS:
- Goldshell AEBOX / AEBOX PRO
- IceRiver AE2
- Other ALEO stratum-compatible miners
EOF

# Set permissions
chown -R ${POOL_USER}:${POOL_USER} ${ALEO_DIR}
chown -R ${POOL_USER}:${POOL_USER} ${ALEO_POOL_DIR}
chmod 700 ${ALEO_DIR}/bin/start-node.sh
chmod 700 ${ALEO_POOL_DIR}/bin/start-pool.sh
chmod 600 ${ALEO_POOL_DIR}/config/config.toml

log_success "ALEO snarkOS v${SNARKOS_VERSION} and Pool Server installed"
log "  Node: ${ALEO_DIR}"
log "  Pool: ${ALEO_POOL_DIR}"
log "  Stratum port: ${ALEO_STRATUM_PORT}"
log "  Pool address: ${ALEO_POOL_ADDRESS}"
log ""
log "  *** BACKUP ${ALEO_DIR}/wallet/keys/pool-wallet.keys IMMEDIATELY! ***"
