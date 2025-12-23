#!/bin/bash
# =============================================================================
# 01-system-update.sh
# Full system update for Ubuntu 24.04
# =============================================================================

set -e

# Source configuration
source /opt/solo-pool/install-scripts/config.sh

# Validate config was loaded successfully
if [ "${CONFIG_LOADED:-}" != "true" ]; then
    echo "ERROR: Failed to load configuration from config.sh" >&2
    exit 1
fi

log "Starting system update..."

# Wait for apt locks to be released (cloud-init may be using apt)
log "Waiting for apt locks..."
while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1; do
    sleep 5
done
while fuser /var/lib/apt/lists/lock >/dev/null 2>&1; do
    sleep 5
done

# Configure apt for non-interactive mode
export DEBIAN_FRONTEND=noninteractive

log "Running apt-get update..."
run_cmd apt-get update

log "Running apt-get upgrade..."
run_cmd apt-get -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" upgrade

log "Running apt-get dist-upgrade..."
run_cmd apt-get -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" dist-upgrade

log "Running apt-get autoclean..."
run_cmd apt-get -y autoclean

log "Running apt-get autoremove..."
run_cmd apt-get -y autoremove

# Install essential packages
log "Installing essential packages..."
run_cmd apt-get -y install \
    curl \
    wget \
    git \
    htop \
    iotop \
    net-tools \
    jq \
    unzip \
    software-properties-common \
    apt-transport-https \
    ca-certificates \
    gnupg \
    lsb-release

log_success "System update complete"
