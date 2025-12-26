#!/bin/bash
# =============================================================================
# 20-configure-services.sh
# Configure systemd services for all nodes and pools using templates
#
# Service naming convention:
#   node-<coin>-<software>  (e.g., node-btc-bitcoind)
#   pool-<coin>-<software>  (e.g., pool-btc-ckpool)
#   pool-<coin>-<coin>-<software>  (e.g., pool-xmr-xtm-merge-proxy)
# =============================================================================

set -e

# Source configuration
source /opt/solo-pool/install/config.sh

# Validate config was loaded successfully
if [ "${CONFIG_LOADED:-}" != "true" ]; then
    echo "ERROR: Failed to load configuration from config.sh" >&2
    exit 1
fi

log "Configuring systemd services..."

# Template directory
TEMPLATE_DIR="/opt/solo-pool/install/files/systemd"

# =============================================================================
# Helper function to install service from template
# Usage: install_service <template_name> <service_name>
# =============================================================================
install_service() {
    local template_name="$1"
    local service_name="$2"
    local template_file="${TEMPLATE_DIR}/${template_name}.service.template"
    local service_file="/etc/systemd/system/${service_name}.service"

    if [ ! -f "${template_file}" ]; then
        log_error "Template not found: ${template_file}"
        return 1
    fi

    # Use envsubst to expand variables
    envsubst < "${template_file}" > "${service_file}"
    chmod 644 "${service_file}"

    log "  Created ${service_name}.service"
}

# =============================================================================
# BITCOIN SERVICES
# =============================================================================
if [ "${ENABLE_BITCOIN_POOL}" = "true" ]; then
    log "Creating Bitcoin services..."

    # Export variables needed for templates
    export POOL_USER BITCOIN_DIR BTC_CKPOOL_DIR BTC_CKPOOL_SOCKET_DIR

    install_service "node-btc-bitcoind" "node-btc-bitcoind"
    install_service "pool-btc-ckpool" "pool-btc-ckpool"

    log "  Bitcoin services created"
fi

# =============================================================================
# BITCOIN CASH SERVICES
# =============================================================================
if [ "${ENABLE_BCH_POOL}" = "true" ]; then
    log "Creating Bitcoin Cash services..."

    # Export variables needed for templates
    export POOL_USER BCHN_DIR BCH_CKPOOL_DIR BCH_CKPOOL_SOCKET_DIR

    install_service "node-bch-bchn" "node-bch-bchn"
    install_service "pool-bch-ckpool" "pool-bch-ckpool"

    log "  Bitcoin Cash services created"
fi

# =============================================================================
# DIGIBYTE SERVICES
# =============================================================================
if [ "${ENABLE_DGB_POOL}" = "true" ]; then
    log "Creating DigiByte services..."

    # Export variables needed for templates
    export POOL_USER DIGIBYTE_DIR DGB_CKPOOL_DIR DGB_CKPOOL_SOCKET_DIR

    install_service "node-dgb-digibyted" "node-dgb-digibyted"
    install_service "pool-dgb-ckpool" "pool-dgb-ckpool"

    log "  DigiByte services created"
fi

# =============================================================================
# MONERO SERVICES (for merge, merged, or monero_only modes)
# =============================================================================
case "${ENABLE_MONERO_TARI_POOL}" in
    merge|merged|monero_only)
        log "Creating Monero services..."

        # Export variables needed for templates
        export POOL_USER MONERO_DIR XMR_MONERO_POOL_DIR

        install_service "node-xmr-monerod" "node-xmr-monerod"
        install_service "wallet-xmr-rpc" "wallet-xmr-rpc"
        log "  Monero wallet-rpc service created"

        # pool-xmr-monero-pool service (only for monero_only mode)
        if [ "${ENABLE_MONERO_TARI_POOL}" = "monero_only" ]; then
            install_service "pool-xmr-monero-pool" "pool-xmr-monero-pool"
            log "  monero-pool service created"
        fi

        log "  Monero services created"
        ;;
esac

# =============================================================================
# TARI SERVICES (for merge, merged, or tari_only modes)
# =============================================================================
case "${ENABLE_MONERO_TARI_POOL}" in
    merge|merged|tari_only)
        log "Creating Tari services..."

        # Determine Tari network based on NETWORK_MODE
        if [ "${NETWORK_MODE}" = "testnet" ]; then
            export TARI_NETWORK="esmeralda"
        else
            export TARI_NETWORK="mainnet"
        fi

        # Export variables needed for templates
        export POOL_USER TARI_DIR XMR_XTM_MERGE_DIR XTM_MINER_DIR TARI_NETWORK

        install_service "node-xtm-minotari" "node-xtm-minotari"
        install_service "wallet-xtm" "wallet-xtm"
        log "  Tari wallet service created"

        if [ "${ENABLE_MONERO_TARI_POOL}" = "merge" ] || [ "${ENABLE_MONERO_TARI_POOL}" = "merged" ]; then
            install_service "pool-xmr-xtm-merge-proxy" "pool-xmr-xtm-merge-proxy"
            log "  Merge mining proxy service created"

        elif [ "${ENABLE_MONERO_TARI_POOL}" = "tari_only" ]; then
            install_service "pool-xtm-minotari-miner" "pool-xtm-minotari-miner"
            log "  Tari miner service created"
        fi

        log "  Tari services created"
        ;;
esac

# =============================================================================
# ALEO SERVICES
# =============================================================================
if [ "${ENABLE_ALEO_POOL}" = "true" ]; then
    log "Creating ALEO services..."

    # Export variables needed for templates
    export POOL_USER ALEO_DIR ALEO_POOL_DIR

    install_service "node-aleo-snarkos" "node-aleo-snarkos"
    install_service "pool-aleo" "pool-aleo"

    log "  ALEO node and pool services created"
fi

# =============================================================================
# WEBUI SERVICE
# =============================================================================
if [ "${ENABLE_WEBUI}" = "true" ]; then
    log "Creating WebUI service..."

    # Export variables needed for template
    export POOL_USER WEBUI_DIR

    install_service "solo-pool-webui" "solo-pool-webui"

    log "  WebUI service created"
fi

# =============================================================================
# PAYMENT PROCESSOR SERVICE
# =============================================================================
NEED_PAYMENTS="false"
case "${ENABLE_MONERO_TARI_POOL}" in
    merge|merged|monero_only|tari_only) NEED_PAYMENTS="true" ;;
esac
[ "${ENABLE_ALEO_POOL}" = "true" ] && NEED_PAYMENTS="true"

if [ "${NEED_PAYMENTS}" = "true" ]; then
    log "Creating Payment Processor service..."

    # Export variables needed for template
    export POOL_USER PAYMENTS_DIR

    install_service "solo-pool-payments" "solo-pool-payments"

    log "  Payment Processor service created"
fi

# =============================================================================
# MASTER SOLO-POOL SERVICE
# =============================================================================
log "Creating master solo-pool service..."

# Export variables needed for template
export BIN_DIR

install_service "solo-pool" "solo-pool"

log "  Master solo-pool service created"

# =============================================================================
# RELOAD AND ENABLE MASTER SERVICE ONLY
# =============================================================================
log "Reloading systemd..."
run_cmd systemctl daemon-reload

# Only enable the master solo-pool service
# Individual services (nodes, pools, wallets, webui, payments) are NOT enabled
# on boot. The solo-pool master service manages them all via start-all.sh/stop-all.sh
log "Enabling master solo-pool service..."
systemctl enable solo-pool >/dev/null 2>&1

log_success "Systemd services configured"
log ""
log "IMPORTANT: Only the master 'solo-pool' service is enabled on boot."
log "All other services (nodes, pools, wallets, webui, payments) are managed by it."
log ""
log "Manage all services:"
log "  sudo systemctl start solo-pool     # Start all services"
log "  sudo systemctl stop solo-pool      # Stop all services"
log "  sudo systemctl restart solo-pool   # Restart all services"
log "  sudo systemctl status solo-pool    # Check master service status"
log ""
log "Check detailed status:"
log "  ${BIN_DIR}/status.sh"
