#!/bin/bash
# =============================================================================
# 04-user-setup.sh
# Create pool user and directory structure
# =============================================================================

set -e

# Source configuration
source /opt/solopool/install/config.sh

# Validate config was loaded successfully
if [ "${CONFIG_LOADED:-}" != "true" ]; then
    echo "ERROR: Failed to load configuration from config.sh" >&2
    exit 1
fi

log "Creating pool user and directory structure..."

# Create pool user if it doesn't exist
if ! id "${POOL_USER}" &>/dev/null; then
    log "Creating user '${POOL_USER}'..."
    run_cmd useradd -r -m -s /bin/bash -d /home/${POOL_USER} ${POOL_USER}
    log "User '${POOL_USER}' created"
else
    log "User '${POOL_USER}' already exists"
fi

# Create base directories
log "Creating directory structure..."

# Node directories
run_cmd mkdir -p ${BITCOIN_DIR}/{bin,data}
run_cmd mkdir -p ${BCHN_DIR}/{bin,data}
run_cmd mkdir -p ${DIGIBYTE_DIR}/{bin,data}
run_cmd mkdir -p ${MONERO_DIR}/{bin,data}
run_cmd mkdir -p ${TARI_DIR}/{bin,data}
run_cmd mkdir -p ${ALEO_DIR}/{bin,data}

# Pool directories
run_cmd mkdir -p ${BTC_CKPOOL_DIR}/{bin,logs}
run_cmd mkdir -p ${BCH_CKPOOL_DIR}/{bin,logs}
run_cmd mkdir -p ${DGB_CKPOOL_DIR}/{bin,logs}
run_cmd mkdir -p ${XMR_MONERO_POOL_DIR}/{bin,data,logs}
run_cmd mkdir -p ${XTM_MINER_DIR}/{config,logs}
run_cmd mkdir -p ${XMR_XTM_MERGE_DIR}/{config,logs}

# Set ownership
log "Setting ownership to ${POOL_USER}..."
run_cmd chown -R ${POOL_USER}:${POOL_USER} ${NODE_DIR}
run_cmd chown -R ${POOL_USER}:${POOL_USER} ${POOL_DIR}

# Set permissions
log "Setting permissions..."
run_cmd chmod -R 750 ${NODE_DIR}
run_cmd chmod -R 750 ${POOL_DIR}

# Create symlinks in /usr/local/bin for convenience (optional)
log "Directory structure created:"
log "  Nodes: ${NODE_DIR}"
log "  Pools: ${POOL_DIR}"

log_success "User and directory setup complete"
