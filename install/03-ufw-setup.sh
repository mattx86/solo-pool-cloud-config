#!/bin/bash
# =============================================================================
# 03-ufw-setup.sh
# UFW Firewall Configuration
# =============================================================================

set -e

# Source configuration
source /opt/solo-pool/install/config.sh

# Validate config was loaded successfully
if [ "${CONFIG_LOADED:-}" != "true" ]; then
    echo "ERROR: Failed to load configuration from config.sh" >&2
    exit 1
fi

log "Configuring UFW firewall..."

# Install UFW if not present
run_cmd apt-get -y install ufw

# Reset UFW to defaults
log "Resetting UFW to defaults..."
run_cmd ufw --force reset

# Set default policies
log "Setting default policies (deny incoming, allow outgoing)..."
run_cmd ufw default deny incoming
run_cmd ufw default allow outgoing

# Allow SSH
log "Allowing SSH on port ${SSH_PORT}..."
run_cmd ufw allow ${SSH_PORT}/tcp comment 'SSH'

# Allow stratum ports for enabled pools
log "Allowing stratum ports for enabled pools..."

if [ "${ENABLE_BITCOIN_POOL}" = "true" ]; then
    log "  Allowing BTC stratum port ${BTC_STRATUM_PORT}..."
    run_cmd ufw allow ${BTC_STRATUM_PORT}/tcp comment 'BTC Stratum'
fi

if [ "${ENABLE_BCH_POOL}" = "true" ]; then
    log "  Allowing BCH stratum port ${BCH_STRATUM_PORT}..."
    run_cmd ufw allow ${BCH_STRATUM_PORT}/tcp comment 'BCH Stratum'
fi

if [ "${ENABLE_DGB_POOL}" = "true" ]; then
    log "  Allowing DGB stratum port ${DGB_STRATUM_PORT}..."
    run_cmd ufw allow ${DGB_STRATUM_PORT}/tcp comment 'DGB Stratum'
fi

# Monero/Tari stratum ports based on mode
if [ "${ENABLE_MONERO_POOL}" = "true" ] || [ "${ENABLE_TARI_POOL}" = "true" ]; then
    if [ "${MONERO_TARI_MODE}" = "monero_only" ]; then
        log "  Allowing XMR stratum port ${XMR_STRATUM_PORT}..."
        run_cmd ufw allow ${XMR_STRATUM_PORT}/tcp comment 'XMR Stratum (monero-pool)'
    elif [ "${MONERO_TARI_MODE}" = "tari_only" ]; then
        log "  Allowing XTM stratum port ${XTM_STRATUM_PORT}..."
        run_cmd ufw allow ${XTM_STRATUM_PORT}/tcp comment 'XTM Stratum'
    elif [ "${MONERO_TARI_MODE}" = "merge" ]; then
        log "  Allowing XMR+XTM merge stratum port ${XMR_XTM_MERGE_STRATUM_PORT}..."
        run_cmd ufw allow ${XMR_XTM_MERGE_STRATUM_PORT}/tcp comment 'XMR+XTM Merge Stratum'
    fi
fi

if [ "${ENABLE_ALEO_POOL}" = "true" ]; then
    log "  Allowing ALEO stratum port ${ALEO_STRATUM_PORT}..."
    run_cmd ufw allow ${ALEO_STRATUM_PORT}/tcp comment 'ALEO Stratum'
fi

# Allow WebUI ports if enabled
if [ "${ENABLE_WEBUI}" = "true" ]; then
    if [ "${WEBUI_HTTP_ENABLED}" = "true" ]; then
        log "  Allowing WebUI HTTP port ${WEBUI_HTTP_PORT}..."
        run_cmd ufw allow ${WEBUI_HTTP_PORT}/tcp comment 'WebUI HTTP'
    fi
    if [ "${WEBUI_HTTPS_ENABLED}" = "true" ]; then
        log "  Allowing WebUI HTTPS port ${WEBUI_HTTPS_PORT}..."
        run_cmd ufw allow ${WEBUI_HTTPS_PORT}/tcp comment 'WebUI HTTPS'
    fi
fi

# Enable UFW
log "Enabling UFW..."
run_cmd ufw --force enable

# Show status
log "UFW Status:"
run_cmd ufw status verbose

log_success "UFW firewall configured"
log "Allowed ports: SSH (${SSH_PORT}), enabled stratum ports, WebUI (if enabled)"
