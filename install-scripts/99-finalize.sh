#!/bin/bash
# =============================================================================
# 99-finalize.sh
# Final setup, verification, and build tool cleanup
# =============================================================================

set -e

# Source configuration
source /opt/solo-pool/install-scripts/config.sh

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
# 1b. VERIFY WALLET ADDRESSES
# =============================================================================
log ""
log "1b. Checking wallet address configuration..."

WALLET_WARNINGS=0

check_wallet() {
    local coin="$1"
    local address="$2"
    local enabled="$3"

    if [ "${enabled}" = "true" ]; then
        if [[ "${address}" == *"YOUR_"* ]] || [[ "${address}" == *"_HERE"* ]] || [[ -z "${address}" ]]; then
            log "  [WARNING] ${coin}: Wallet address not configured!"
            ((WALLET_WARNINGS++))
        else
            log "  [OK] ${coin}: ${address:0:12}...${address: -8}"
        fi
    fi
}

check_wallet "BTC" "${BTC_WALLET_ADDRESS}" "${ENABLE_BITCOIN_POOL}"
check_wallet "BCH" "${BCH_WALLET_ADDRESS}" "${ENABLE_BCH_POOL}"
check_wallet "DGB" "${DGB_WALLET_ADDRESS}" "${ENABLE_DGB_POOL}"
[ "${MONERO_TARI_MODE}" != "tari_only" ] && check_wallet "XMR" "${XMR_WALLET_ADDRESS}" "${ENABLE_MONERO_POOL}"
[ "${MONERO_TARI_MODE}" != "monero_only" ] && check_wallet "XTM" "${XTM_WALLET_ADDRESS}" "${ENABLE_TARI_POOL}"
check_wallet "ALEO" "${ALEO_WALLET_ADDRESS}" "${ENABLE_ALEO_POOL}"

if [ ${WALLET_WARNINGS} -gt 0 ]; then
    log ""
    log "  *** ${WALLET_WARNINGS} wallet address(es) need configuration! ***"
    log "  Edit ${INSTALL_DIR}/config.sh to set wallet addresses"
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

# Base URL for raw files (derived from SCRIPTS_BASE_URL)
FILES_BASE_URL="${SCRIPTS_BASE_URL}/files"

# Download and install convenience scripts
for script in start-nodes.sh stop-nodes.sh start-pools.sh stop-pools.sh \
              start-all.sh stop-all.sh status.sh sync-status.sh \
              start-btc.sh start-bch.sh start-dgb.sh start-xmr.sh start-xtm.sh start-aleo.sh; do
    log "  Downloading ${script}..."
    if wget -q "${FILES_BASE_URL}/scripts/${script}" -O "${BASE_DIR}/${script}" 2>/dev/null; then
        chmod +x "${BASE_DIR}/${script}"
        log "  Installed ${script}"
    else
        log_error "  Failed to download: ${script}"
    fi
done

# Set ownership
chown -R ${POOL_USER}:${POOL_USER} ${BASE_DIR}/*.sh

# =============================================================================
# 4. INSTALL MOTD
# =============================================================================
log "4. Installing login message..."

log "  Downloading MOTD..."
if wget -q "${FILES_BASE_URL}/motd/99-solo-pool" -O "/etc/update-motd.d/99-solo-pool" 2>/dev/null; then
    chmod +x /etc/update-motd.d/99-solo-pool
    log "  Installed MOTD"
else
    log_error "  Failed to download MOTD"
fi

# =============================================================================
# 5. SUMMARY
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
log "1. Start nodes: ${BASE_DIR}/start-nodes.sh"
log "2. Wait for sync: ${BASE_DIR}/sync-status.sh"
log "3. Open firewall ports when ready"
log "4. Start pools: ${BASE_DIR}/start-pools.sh"
log ""
if [ "${ENABLE_ALEO_POOL}" = "true" ]; then
    log "ALEO NOTE:"
    log "  Configure ALEO_WALLET_ADDRESS in config.sh"
    log "  before starting the pool!"
    log ""
fi
log "=============================================="

log_success "Installation complete!"
