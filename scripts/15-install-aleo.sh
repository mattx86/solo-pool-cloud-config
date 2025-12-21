#!/bin/bash
# =============================================================================
# 15-install-aleo.sh
# Install ALEO snarkOS for Solo Proving
#
# ALEO uses proof-of-succinct-work where "miners" are actually "provers"
# that generate zero-knowledge proofs. The snarkOS software serves as
# both the node and the prover.
#
# IMPORTANT: ALEO proving is very CPU-intensive and benefits significantly
# from GPUs. This script installs the CPU version.
# =============================================================================

set -e

# Source configuration
source /opt/solo-pool/config.sh

# Check if ALEO pool is enabled
if [ "${ENABLE_ALEO_POOL}" != "true" ]; then
    log "ALEO pool is disabled, skipping..."
    exit 0
fi

log "Installing ALEO snarkOS..."

# =============================================================================
# 1. PREREQUISITES
# =============================================================================
log "1. Installing ALEO prerequisites..."

export DEBIAN_FRONTEND=noninteractive

# Additional dependencies for ALEO
run_cmd apt-get -y install \
    clang \
    libclang-dev \
    llvm \
    llvm-dev

# Ensure Rust is available
if [ -f "/root/.cargo/env" ]; then
    source /root/.cargo/env
fi

# Update Rust to latest stable
log "  Updating Rust..."
rustup update stable >/dev/tty1 2>&1 || true

log "  Prerequisites installed"

# =============================================================================
# 2. BUILD SNARKOS FROM SOURCE
# =============================================================================
log "2. Building snarkOS from source..."
log "  This may take 10-20 minutes..."

cd /tmp

# Clone snarkOS
log "  Cloning snarkOS repository..."
rm -rf snarkOS
run_cmd git clone --depth 1 https://github.com/AleoHQ/snarkOS.git

cd snarkOS

# Build snarkOS
log "  Building snarkOS (this takes a while)..."
run_cmd cargo build --release

# Install binaries
log "  Installing binaries..."
cp target/release/snarkos ${ALEO_DIR}/bin/

# Cleanup (build artifacts are large)
cd /tmp
rm -rf snarkOS

log "  snarkOS built and installed"

# =============================================================================
# 3. CONFIGURE SNARKOS
# =============================================================================
log "3. Configuring snarkOS..."

# Create data directory
mkdir -p ${ALEO_DIR}/data
mkdir -p ${ALEO_DIR}/logs

# Create configuration
# Note: snarkOS uses command-line arguments primarily, but we can create
# a wrapper script with the configuration

cat > ${ALEO_DIR}/start-prover.sh << EOF
#!/bin/bash
# ALEO Prover Start Script

# Your ALEO address (private key should be kept secure)
ALEO_ADDRESS="${ALEO_WALLET_ADDRESS}"

# Configuration
DATA_DIR="${ALEO_DIR}/data"
LOG_FILE="${ALEO_DIR}/logs/snarkos.log"

# Start snarkOS as a prover
# Note: You need your private key to actually prove/mine
# The address here is for reference

exec ${ALEO_DIR}/bin/snarkos start \\
    --nodisplay \\
    --prover \${ALEO_ADDRESS} \\
    --log \${LOG_FILE} \\
    --verbosity 1

# Alternative: Run as a client (sync-only, no proving)
# exec ${ALEO_DIR}/bin/snarkos start --client --nodisplay --log \${LOG_FILE}
EOF

chmod +x ${ALEO_DIR}/start-prover.sh

# Create a note file about ALEO setup
cat > ${ALEO_DIR}/SETUP_NOTES.txt << EOF
ALEO Setup Notes
================

IMPORTANT: ALEO proving requires your PRIVATE KEY, not just your address.

To start proving (mining) on ALEO:

1. Generate a new account (if needed):
   ${ALEO_DIR}/bin/snarkos account new

2. Save your private key securely!

3. Edit the systemd service or start-prover.sh to include your private key:
   --prover YOUR_PRIVATE_KEY

4. Start the prover:
   sudo systemctl start snarkos

Resource Requirements:
- CPU: 8+ cores recommended (proving is CPU-intensive)
- RAM: 16GB+ recommended
- GPU: Highly recommended for competitive proving

The current configuration is set up for CPU proving only.
For GPU proving, you'll need to install CUDA and rebuild snarkOS with GPU support.

Network Ports:
- P2P: 4130 (must be open for network connectivity)
- REST API: 3030 (optional, for monitoring)

Commands:
- Check status: snarkos --help
- View peers: curl http://localhost:3030/testnet/peers/count
EOF

# Set permissions
chown -R ${POOL_USER}:${POOL_USER} ${ALEO_DIR}
chmod 600 ${ALEO_DIR}/start-prover.sh

log_success "ALEO snarkOS installed"
log "  Directory: ${ALEO_DIR}"
log "  Binary: ${ALEO_DIR}/bin/snarkos"
log ""
log "  IMPORTANT: Read ${ALEO_DIR}/SETUP_NOTES.txt"
log "  You need your PRIVATE KEY to start proving"
