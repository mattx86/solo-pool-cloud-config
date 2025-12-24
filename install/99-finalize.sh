#!/bin/bash
# =============================================================================
# 99-finalize.sh
# Final setup, verification, and build tool cleanup
# =============================================================================

set -e

# Source configuration
source /opt/solo-pool/install/config.sh

# Validate config was loaded successfully
if [ "${CONFIG_LOADED:-}" != "true" ]; then
    echo "ERROR: Failed to load configuration from config.sh" >&2
    exit 1
fi

log "Finalizing installation..."

# =============================================================================
# 1. VERIFY INSTALLATIONS
# =============================================================================
log "1. Verifying installations..."

verify_binary() {
    local name="$1"
    local path="$2"
    if [ -x "$path" ]; then
        log "  [OK] $name"
        return 0
    else
        log "  [MISSING] $name: $path"
        return 1
    fi
}

ERRORS=0

if [ "${ENABLE_BITCOIN_POOL}" = "true" ]; then
    verify_binary "bitcoind" "${BITCOIN_DIR}/bin/bitcoind" || ((ERRORS++))
    verify_binary "ckpool-btc" "${BTC_CKPOOL_DIR}/bin/ckpool" || ((ERRORS++))
fi

if [ "${ENABLE_BCH_POOL}" = "true" ]; then
    verify_binary "bchn" "${BCHN_DIR}/bin/bitcoind" || ((ERRORS++))
    verify_binary "ckpool-bch" "${BCH_CKPOOL_DIR}/bin/ckpool" || ((ERRORS++))
fi

if [ "${ENABLE_DGB_POOL}" = "true" ]; then
    verify_binary "digibyted" "${DIGIBYTE_DIR}/bin/digibyted" || ((ERRORS++))
    verify_binary "ckpool-dgb" "${DGB_CKPOOL_DIR}/bin/ckpool" || ((ERRORS++))
fi

if [ "${ENABLE_MONERO_POOL}" = "true" ]; then
    verify_binary "monerod" "${MONERO_DIR}/bin/monerod" || ((ERRORS++))
    if [ "${MONERO_TARI_MODE}" = "monero_only" ]; then
        verify_binary "monero-pool" "${XMR_MONERO_POOL_DIR}/bin/monero-pool" || ((ERRORS++))
    fi
fi

if [ "${ENABLE_TARI_POOL}" = "true" ] && [ "${MONERO_TARI_MODE}" != "monero_only" ]; then
    verify_binary "minotari_node" "${TARI_DIR}/bin/minotari_node" || ((ERRORS++))
    if [ "${MONERO_TARI_MODE}" = "merge" ]; then
        verify_binary "minotari_merge_mining_proxy" "${TARI_DIR}/bin/minotari_merge_mining_proxy" || ((ERRORS++))
    else
        verify_binary "minotari_miner" "${TARI_DIR}/bin/minotari_miner" || ((ERRORS++))
    fi
fi

if [ "${ENABLE_ALEO_POOL}" = "true" ]; then
    verify_binary "snarkos" "${ALEO_DIR}/bin/snarkos" || ((ERRORS++))
    verify_binary "aleo-pool-server" "${ALEO_POOL_DIR}/bin/aleo-pool-server" || ((ERRORS++))
fi

# =============================================================================
# 1b. VERIFY GENERATED POOL WALLETS
# =============================================================================
log ""
log "1b. Checking generated pool wallets..."

WALLET_WARNINGS=0

check_pool_wallet() {
    local coin="$1"
    local wallet_file="$2"
    local enabled="$3"

    if [ "${enabled}" = "true" ]; then
        if [ -f "${wallet_file}" ] && [ -s "${wallet_file}" ]; then
            local address=$(cat "${wallet_file}")
            log "  [OK] ${coin}: ${address:0:12}...${address: -8}"
        else
            log "  [WARNING] ${coin}: Pool wallet not found: ${wallet_file}"
            ((WALLET_WARNINGS++))
        fi
    fi
}

# BTC/BCH/DGB use CKPool BTCSOLO mode - miners provide their own wallet address
# No pool wallet needed for these coins
log "  [INFO] BTC/BCH/DGB: Miners use their own wallet (BTCSOLO mode)"

# Check pool wallets for XMR/XTM/ALEO (auto-generated during install)
if [ "${ENABLE_MONERO_POOL}" = "true" ] && [ "${MONERO_TARI_MODE}" != "tari_only" ]; then
    check_pool_wallet "XMR" "${MONERO_DIR}/wallet/keys/pool-wallet.address" "true"
fi

if [ "${ENABLE_TARI_POOL}" = "true" ] && [ "${MONERO_TARI_MODE}" != "monero_only" ]; then
    check_pool_wallet "XTM" "${TARI_DIR}/wallet/keys/pool-wallet.address" "true"
fi

if [ "${ENABLE_ALEO_POOL}" = "true" ]; then
    check_pool_wallet "ALEO" "${ALEO_DIR}/wallet/keys/pool-wallet.address" "true"
fi

if [ ${WALLET_WARNINGS} -gt 0 ]; then
    log ""
    log "  *** ${WALLET_WARNINGS} pool wallet(s) missing! ***"
    log "  Pool wallets should have been generated during installation."
    log "  Check the install logs for errors."
fi

# =============================================================================
# 2. REMOVE BUILD DEPENDENCIES
# =============================================================================
log "2. Removing build dependencies..."

export DEBIAN_FRONTEND=noninteractive

# Read the list of build packages that were installed
if [ -f "${INSTALL_DIR}/build-packages.txt" ]; then
    BUILD_PACKAGES=$(cat ${INSTALL_DIR}/build-packages.txt)

    log "  Removing build packages..."
    # Use apt-get remove with --auto-remove to clean up
    run_cmd apt-get -y remove ${BUILD_PACKAGES} || true

    # Clean up any orphaned packages
    run_cmd apt-get -y autoremove || true

    # Clean apt cache
    run_cmd apt-get -y clean

    # Remove the build packages list file
    rm -f ${INSTALL_DIR}/build-packages.txt

    log "  Build packages removed"
else
    log "  No build packages list found, skipping"
fi

# Remove Rust if it was installed (only needed for building snarkOS)
if [ "${ENABLE_ALEO_POOL}" = "true" ]; then
    log "  Removing Rust toolchain..."
    if [ -d "/root/.cargo" ]; then
        rm -rf /root/.cargo
        rm -rf /root/.rustup
        log "  Rust removed"
    fi
fi

# Clean up /tmp
log "  Cleaning /tmp..."
rm -rf /tmp/ckpool-* /tmp/snarkOS /tmp/monero-pool* /tmp/tari* /tmp/bitcoin* /tmp/bchn* /tmp/digibyte* /tmp/monero* 2>/dev/null || true

log "  Cleanup complete"

# =============================================================================
# 3. INSTALL CONVENIENCE SCRIPTS
# =============================================================================
log "3. Installing convenience scripts..."

# Base URLs for downloading additional files
# SCRIPTS_BASE_URL points to install/, so we derive parent paths
REPO_BASE_URL="${SCRIPTS_BASE_URL%/install}"
BIN_SCRIPTS_URL="${REPO_BASE_URL}/bin"
FILES_URL="${SCRIPTS_BASE_URL}/files"

# Create bin directory for management scripts
mkdir -p ${BIN_DIR}

# Download and install convenience scripts
for script in start-nodes.sh stop-nodes.sh start-pools.sh stop-pools.sh \
              start-all.sh stop-all.sh restart-all.sh status.sh sync-status.sh \
              start-btc.sh start-bch.sh start-dgb.sh start-xmr.sh start-xtm.sh start-aleo.sh \
              maintenance.sh backup.sh; do
    log "  Downloading ${script}..."
    if wget -q "${BIN_SCRIPTS_URL}/${script}" -O "${BIN_DIR}/${script}" 2>/dev/null; then
        chmod +x "${BIN_DIR}/${script}"
        log "  Installed ${script}"
    else
        log_error "  Failed to download: ${script}"
    fi
done

# Set ownership
chown -R ${POOL_USER}:${POOL_USER} ${BIN_DIR}

# =============================================================================
# 4. INSTALL MOTD
# =============================================================================
log "4. Installing login message..."

log "  Downloading MOTD..."
if wget -q "${FILES_URL}/motd/99-solo-pool" -O "/etc/update-motd.d/99-solo-pool" 2>/dev/null; then
    chmod +x /etc/update-motd.d/99-solo-pool
    log "  Installed MOTD"
else
    log_error "  Failed to download MOTD"
fi

# =============================================================================
# 5. CONFIGURE MAINTENANCE
# =============================================================================
log "5. Configuring daily maintenance..."

# Create directories
mkdir -p ${BASE_DIR}/config
mkdir -p ${BASE_DIR}/logs
mkdir -p ${INSTALL_DIR}/files/config

TEMPLATE_DIR="${INSTALL_DIR}/files/config"
CONFIG_TEMPLATES_URL="${FILES_URL}/config"

# Download maintenance templates
log "  Downloading maintenance templates..."
wget -q "${CONFIG_TEMPLATES_URL}/logrotate.conf.template" -O "${TEMPLATE_DIR}/logrotate.conf.template" 2>/dev/null || true
wget -q "${CONFIG_TEMPLATES_URL}/solo-pool.cron.template" -O "${TEMPLATE_DIR}/solo-pool.cron.template" 2>/dev/null || true

# Export variables for template substitution
export BASE_DIR BIN_DIR BITCOIN_DIR BCHN_DIR DIGIBYTE_DIR MONERO_DIR TARI_DIR ALEO_DIR
export BTC_CKPOOL_DIR BCH_CKPOOL_DIR DGB_CKPOOL_DIR XMR_MONERO_POOL_DIR
export XTM_MINER_DIR XMR_XTM_MERGE_DIR ALEO_POOL_DIR WEBUI_DIR PAYMENTS_DIR
export MAINTENANCE_HOUR MAINTENANCE_MINUTE POOL_USER BACKUP_DIR BACKUP_RETENTION_DAYS

# Install logrotate configuration from template
log "  Installing logrotate configuration..."
if [ -f "${TEMPLATE_DIR}/logrotate.conf.template" ]; then
    envsubst < "${TEMPLATE_DIR}/logrotate.conf.template" > ${BASE_DIR}/config/logrotate.conf
    chmod 644 ${BASE_DIR}/config/logrotate.conf
    log "  Logrotate config: ${BASE_DIR}/config/logrotate.conf"
else
    log_error "  Logrotate template not found"
fi

# Install cron job from template
log "  Installing cron job..."
if [ -f "${TEMPLATE_DIR}/solo-pool.cron.template" ]; then
    envsubst < "${TEMPLATE_DIR}/solo-pool.cron.template" > /etc/cron.d/solo-pool
    chmod 644 /etc/cron.d/solo-pool
    log "  Cron job: /etc/cron.d/solo-pool"
    log "  Schedule: ${MAINTENANCE_MINUTE} ${MAINTENANCE_HOUR} * * * (daily)"
else
    log_error "  Cron template not found"
fi

# Set ownership
chown -R ${POOL_USER}:${POOL_USER} ${BASE_DIR}/config
chown -R ${POOL_USER}:${POOL_USER} ${BASE_DIR}/logs

log "  Maintenance configured"

# =============================================================================
# 6. SUMMARY
# =============================================================================
log ""
log "=============================================="
log "           INSTALLATION SUMMARY"
log "=============================================="
log ""
log "Configuration: ${INSTALL_DIR}/config.sh"
log ""
log "Enabled Pools:"
[ "${ENABLE_BITCOIN_POOL}" = "true" ] && log "  - Bitcoin (BTC) on port ${BTC_STRATUM_PORT}"
[ "${ENABLE_BCH_POOL}" = "true" ] && log "  - Bitcoin Cash (BCH) on port ${BCH_STRATUM_PORT}"
[ "${ENABLE_DGB_POOL}" = "true" ] && log "  - DigiByte (DGB) on port ${DGB_STRATUM_PORT}"
if [ "${ENABLE_MONERO_POOL}" = "true" ] || [ "${ENABLE_TARI_POOL}" = "true" ]; then
    if [ "${MONERO_TARI_MODE}" = "merge" ]; then
        log "  - Monero + Tari (merge mining) on port ${XMR_XTM_MERGE_STRATUM_PORT}"
    elif [ "${MONERO_TARI_MODE}" = "monero_only" ]; then
        log "  - Monero (XMR) via monero-pool on port ${XMR_STRATUM_PORT}"
    elif [ "${MONERO_TARI_MODE}" = "tari_only" ]; then
        log "  - Tari (XTM) on port ${XTM_STRATUM_PORT}"
    fi
fi
[ "${ENABLE_ALEO_POOL}" = "true" ] && log "  - ALEO on port ${ALEO_STRATUM_PORT}"
log ""
log "Installation Errors: ${ERRORS}"
log ""
log "NEXT STEPS:"
log "1. Start nodes: ${BIN_DIR}/start-nodes.sh"
log "2. Wait for sync: ${BIN_DIR}/sync-status.sh"
log "3. Open firewall ports when ready"
log "4. Start pools: ${BIN_DIR}/start-pools.sh"
log ""
log "IMPORTANT: Backup all pool wallet keys immediately!"
log "  XMR: ${MONERO_DIR}/wallet/keys/SEED_BACKUP.txt"
log "  XTM: ${TARI_DIR}/wallet/keys/SEED_BACKUP.txt"
log "  ALEO: ${ALEO_DIR}/wallet/keys/pool-wallet.privatekey"
log ""
log "=============================================="

log_success "Installation complete!"
