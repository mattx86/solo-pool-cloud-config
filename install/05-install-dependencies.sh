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
source /opt/solo-pool/install/config.sh

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
    # monero-pool build dependencies
    liblmdb-dev
    libjson-c-dev
    uuid-dev
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
        lld        # LLVM's linker - snarkOS uses -fuse-ld=lld
    )

    # Append to build packages list
    echo "${SNARKOS_BUILD_PACKAGES[@]}" >> ${INSTALL_DIR}/build-packages.txt

    run_cmd apt-get -y install "${SNARKOS_BUILD_PACKAGES[@]}"

    log "  snarkOS build dependencies installed"
fi

# =============================================================================
# 4. RUST TOOLCHAIN (needed for snarkOS, webui, payments processor)
# =============================================================================
# Determine if Rust is needed:
# - ALEO pool requires Rust (snarkOS, aleo-pool-server)
# - WebUI requires Rust
# - Payment processor requires Rust (if XMR/XTM/ALEO enabled)
NEED_RUST="false"
[ "${ENABLE_ALEO_POOL}" = "true" ] && NEED_RUST="true"
[ "${ENABLE_WEBUI}" = "true" ] && NEED_RUST="true"
case "${ENABLE_MONERO_TARI_POOL}" in
    merge|merged|monero_only|tari_only) NEED_RUST="true" ;;
esac

if [ "${NEED_RUST}" = "true" ]; then
    log "4. Installing Rust toolchain..."

    # Explicitly set PATH (don't rely on $HOME which may not be /root in cloud-init)
    export PATH="/root/.cargo/bin:$PATH"

    # Install Rust for root (for building Rust-based components)
    if [ ! -d "/root/.cargo" ]; then
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y >/dev/tty1 2>&1
        source /root/.cargo/env
        log "  Rust installed for root"
    else
        source /root/.cargo/env
        log "  Rust already installed"
    fi

    # Verify cargo is available
    if ! command -v cargo &> /dev/null; then
        log_error "cargo command not found after installation"
        exit 1
    fi

    # Update to stable
    rustup default stable >/dev/tty1 2>&1
    rustup update stable >/dev/tty1 2>&1
    log "  Rust stable toolchain ready"
else
    log "4. Skipping Rust (no Rust-based components enabled)"
fi

# =============================================================================
# 5. GRPCURL (for Tari gRPC status queries)
# =============================================================================
case "${ENABLE_MONERO_TARI_POOL}" in
    merge|merged|tari_only)
        log "5. Installing grpcurl for Tari gRPC queries..."

        GRPCURL_VERSION="1.9.1"
        cd /tmp
        wget -q "https://github.com/fullstorydev/grpcurl/releases/download/v${GRPCURL_VERSION}/grpcurl_${GRPCURL_VERSION}_linux_x86_64.tar.gz" -O grpcurl.tar.gz
        tar -xzf grpcurl.tar.gz grpcurl
        mv grpcurl /usr/local/bin/
        chmod +x /usr/local/bin/grpcurl
        rm -f grpcurl.tar.gz

        log "  grpcurl v${GRPCURL_VERSION} installed"
        ;;
    *)
        log "5. Skipping grpcurl (Tari not enabled)"
        ;;
esac

log_success "Build dependencies installed"
