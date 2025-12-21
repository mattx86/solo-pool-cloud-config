#!/bin/bash
# =============================================================================
# 05-install-dependencies.sh
# Install build dependencies for all pool software
# =============================================================================

set -e

# Source configuration
source /opt/solo-pool/config.sh

log "Installing build dependencies..."

export DEBIAN_FRONTEND=noninteractive

# Wait for apt locks
while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1; do
    sleep 5
done

# Build essentials
log "Installing build essentials..."
run_cmd apt-get -y install \
    build-essential \
    autoconf \
    automake \
    libtool \
    pkg-config \
    cmake \
    ninja-build

# Libraries needed for various builds
log "Installing required libraries..."
run_cmd apt-get -y install \
    libssl-dev \
    libcurl4-openssl-dev \
    libevent-dev \
    libboost-all-dev \
    libzmq3-dev \
    libsodium-dev \
    libunwind-dev \
    libminiupnpc-dev \
    libnatpmp-dev \
    libsqlite3-dev \
    libhidapi-dev \
    libusb-1.0-0-dev \
    libprotobuf-dev \
    protobuf-compiler \
    libreadline-dev \
    libncurses5-dev \
    zlib1g-dev \
    liblzma-dev \
    libbz2-dev

# Go (needed for monero-stratum)
log "Installing Go..."
GO_VERSION="1.22.0"
if [ ! -d "/usr/local/go" ]; then
    cd /tmp
    run_cmd wget -q "https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz"
    run_cmd tar -C /usr/local -xzf "go${GO_VERSION}.linux-amd64.tar.gz"
    rm -f "go${GO_VERSION}.linux-amd64.tar.gz"

    # Add to system-wide PATH
    echo 'export PATH=$PATH:/usr/local/go/bin' > /etc/profile.d/go.sh
    chmod +x /etc/profile.d/go.sh
    export PATH=$PATH:/usr/local/go/bin
    log "Go ${GO_VERSION} installed"
else
    log "Go already installed"
fi

# Rust (needed for Tari and ALEO)
log "Installing Rust..."
if [ ! -d "/home/${POOL_USER}/.cargo" ]; then
    # Install Rust as pool user
    su - ${POOL_USER} -c 'curl --proto "=https" --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y' >/dev/tty1 2>&1
    log "Rust installed for user ${POOL_USER}"
else
    log "Rust already installed"
fi

# Also install Rust for root (for building)
if [ ! -d "/root/.cargo" ]; then
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y >/dev/tty1 2>&1
    source /root/.cargo/env
    log "Rust installed for root"
fi

log_success "Build dependencies installed"
