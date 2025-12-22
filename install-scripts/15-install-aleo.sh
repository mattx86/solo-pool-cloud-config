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
# to connect and submit proofs. Rewards go to ALEO_WALLET_ADDRESS.
# =============================================================================

set -e

# Source configuration
source /opt/solo-pool/install-scripts/config.sh

# Check if ALEO pool is enabled
if [ "${ENABLE_ALEO_POOL}" != "true" ]; then
    log "ALEO pool is disabled, skipping..."
    exit 0
fi

log "Installing ALEO snarkOS v${SNARKOS_VERSION} and ALEO Pool Server..."

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

# Install binaries
log "  Installing snarkOS binary..."
mkdir -p ${ALEO_DIR}/bin
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
# 4. CONFIGURE SNARKOS NODE
# =============================================================================
log "4. Configuring snarkOS node..."

mkdir -p ${ALEO_DIR}/data
mkdir -p ${ALEO_DIR}/logs

# Determine P2P listen address based on inbound config
if [ "${ENABLE_INBOUND_P2P}" = "true" ]; then
    ALEO_LISTEN="0.0.0.0"
else
    ALEO_LISTEN="127.0.0.1"
fi

# Create snarkOS node start script
cat > ${ALEO_DIR}/start-node.sh << EOF
#!/bin/bash
# ALEO snarkOS Node Start Script
# Runs as a network node (not prover mode)

exec ${ALEO_DIR}/bin/snarkos start \\
    --nodisplay \\
    --node ${ALEO_LISTEN}:4130 \\
    --rest 127.0.0.1:3030 \\
    --log ${ALEO_DIR}/logs/snarkos.log \\
    --verbosity 1
EOF

chmod +x ${ALEO_DIR}/start-node.sh

log "  snarkOS node configured"

# =============================================================================
# 5. CONFIGURE ALEO POOL SERVER
# =============================================================================
log "5. Configuring ALEO Pool Server..."

mkdir -p ${ALEO_POOL_DIR}/config
mkdir -p ${ALEO_POOL_DIR}/data
mkdir -p ${ALEO_POOL_DIR}/logs

# Check if wallet address is configured
if [[ "${ALEO_WALLET_ADDRESS}" == *"YOUR_"* ]] || [[ "${ALEO_WALLET_ADDRESS}" == *"_HERE"* ]] || [[ -z "${ALEO_WALLET_ADDRESS}" ]]; then
    log "  WARNING: ALEO_WALLET_ADDRESS not configured!"
    log "  You must set a valid ALEO address in config.sh before starting the pool"
    ALEO_POOL_ADDRESS="CONFIGURE_YOUR_ALEO_ADDRESS"
else
    ALEO_POOL_ADDRESS="${ALEO_WALLET_ADDRESS}"
    log "  Pool address: ${ALEO_POOL_ADDRESS:0:20}..."
fi

# Create pool server configuration
# Note: aleo-pool-server configuration format may vary - this is a template
cat > ${ALEO_POOL_DIR}/config/config.toml << EOF
# ALEO Pool Server Configuration
# Solo mining pool for ALEO ASICs

[server]
# Stratum listener (ASICs connect here)
listen = "0.0.0.0:${ALEO_STRATUM_PORT}"

# snarkOS REST API connection
node_url = "http://127.0.0.1:3030"

[pool]
# Pool address - rewards go here
address = "${ALEO_POOL_ADDRESS}"

# Pool name (shown in stratum)
name = "Solo Pool"

# Difficulty settings
starting_difficulty = 100
minimum_difficulty = 1

[logging]
level = "info"
path = "${ALEO_POOL_DIR}/logs/pool.log"
EOF

# Create pool server start script
cat > ${ALEO_POOL_DIR}/start-pool.sh << EOF
#!/bin/bash
# ALEO Pool Server Start Script
# Provides stratum interface for ALEO ASICs

cd ${ALEO_POOL_DIR}
exec ${ALEO_POOL_DIR}/bin/aleo-pool-server \\
    --config ${ALEO_POOL_DIR}/config/config.toml
EOF

chmod +x ${ALEO_POOL_DIR}/start-pool.sh

log "  ALEO Pool Server configured"

# =============================================================================
# 6. CREATE SETUP NOTES
# =============================================================================
log "6. Creating setup notes..."

cat > ${ALEO_DIR}/SETUP_NOTES.txt << EOF
ALEO Solo Mining Pool Setup Notes
==================================

This installation includes:
1. snarkOS - ALEO network node
2. aleo-pool-server - Stratum server for ASIC miners

Architecture:
  Your ASIC --> Pool Server (stratum:${ALEO_STRATUM_PORT}) --> snarkOS (node) --> ALEO Network

Pool Address: ${ALEO_POOL_ADDRESS}
(All mining rewards go to this address)

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
chmod 700 ${ALEO_DIR}/start-node.sh
chmod 700 ${ALEO_POOL_DIR}/start-pool.sh
chmod 600 ${ALEO_POOL_DIR}/config/config.toml

log_success "ALEO snarkOS v${SNARKOS_VERSION} and Pool Server installed"
log "  Node: ${ALEO_DIR}"
log "  Pool: ${ALEO_POOL_DIR}"
log "  Stratum port: ${ALEO_STRATUM_PORT}"
log ""
log "  IMPORTANT: Configure ALEO_WALLET_ADDRESS in config.sh"
log "  before starting the pool!"
