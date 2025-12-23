#!/bin/bash
# =============================================================================
# 05-install-dependencies.sh
# Install build dependencies for all pool software
#
# Build tools installed here will be removed in 99-finalize.sh to keep
# the system clean. Only runtime dependencies are kept.
# =============================================================================

set -e

# Source configuration
source /opt/solo-pool/install-scripts/config.sh

# Validate config was loaded successfully
if [ "${CONFIG_LOADED:-}" != "true" ]; then
    echo "ERROR: Failed to load configuration from config.sh" >&2
    exit 1
fi

log "Installing build dependencies..."

export DEBIAN_FRONTEND=noninteractive

# Wait for apt locks
while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1; do
    sleep 5
done

# =============================================================================
# 1. RUNTIME DEPENDENCIES (kept after build)
# =============================================================================
log "1. Installing runtime dependencies..."

run_cmd apt-get -y install \
    wget \
    curl \
    git \
    jq \
    apg \
    openssl \
    libssl3 \
    libzmq5 \
    libsodium23 \
    libminiupnpc17 \
    libnatpmp1 \
    libsqlite3-0 \
    libreadline8 \
    zlib1g \
    liblzma5 \
    libbz2-1.0 \
    libjansson4

# =============================================================================
# 2. BUILD DEPENDENCIES (removed after build in 99-finalize.sh)
# =============================================================================
log "2. Installing build tools..."

# Track build packages for later removal
BUILD_PACKAGES=(
    build-essential
    autoconf
    automake
    libtool
    pkg-config
    cmake
    ninja-build
    libssl-dev
    libcurl4-openssl-dev
    libevent-dev
    libboost-all-dev
    libzmq3-dev
    libsodium-dev
    libunwind-dev
    libminiupnpc-dev
    libnatpmp-dev
    libsqlite3-dev
    libhidapi-dev
    libusb-1.0-0-dev
    libprotobuf-dev
    protobuf-compiler
    libreadline-dev
    libncurses5-dev
    zlib1g-dev
    liblzma-dev
    libbz2-dev
    libjansson-dev
)

# Save build package list for removal later
echo "${BUILD_PACKAGES[@]}" > ${INSTALL_DIR}/build-packages.txt

run_cmd apt-get -y install "${BUILD_PACKAGES[@]}"

log "  Build tools installed"

# =============================================================================
# 3. SNARKOS BUILD DEPENDENCIES (if ALEO enabled)
# =============================================================================
if [ "${ENABLE_ALEO_POOL}" = "true" ]; then
    log "3. Installing snarkOS build dependencies..."

    SNARKOS_BUILD_PACKAGES=(
        clang
        libclang-dev
        llvm
        llvm-dev
    )

    # Append to build packages list
    echo "${SNARKOS_BUILD_PACKAGES[@]}" >> ${INSTALL_DIR}/build-packages.txt

    run_cmd apt-get -y install "${SNARKOS_BUILD_PACKAGES[@]}"

    log "  snarkOS build dependencies installed"
fi

# =============================================================================
# 4. RUST TOOLCHAIN (needed for snarkOS build)
# =============================================================================
if [ "${ENABLE_ALEO_POOL}" = "true" ]; then
    log "4. Installing Rust toolchain..."

    # Install Rust for root (for building snarkOS)
    if [ ! -d "/root/.cargo" ]; then
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y >/dev/tty1 2>&1
        source /root/.cargo/env
        log "  Rust installed for root"
    else
        source /root/.cargo/env
        log "  Rust already installed"
    fi

    # Update to stable
    rustup default stable >/dev/tty1 2>&1
    rustup update stable >/dev/tty1 2>&1
    log "  Rust stable toolchain ready"
else
    log "4. Skipping Rust (ALEO not enabled)"
fi

log_success "Build dependencies installed"
