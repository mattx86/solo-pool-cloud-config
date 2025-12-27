#!/bin/bash
# =============================================================================
# start-bch.sh - Bitcoin Cash startup sequence
# Starts node, waits for sync, then starts stratum
# =============================================================================

source /opt/solopool/install/config.sh

if [ "${CONFIG_LOADED:-}" != "true" ]; then
    echo "[BCH] ERROR: Failed to load configuration" >&2
    exit 1
fi

if [ "${ENABLE_BCH_POOL}" != "true" ]; then
    echo "[BCH] Bitcoin Cash pool not enabled, skipping"
    exit 0
fi

log() {
    echo "[BCH] $(date '+%H:%M:%S') $1"
}

# =============================================================================
# 1. START NODE
# =============================================================================
log "Starting Bitcoin Cash node..."

# Check if bchn binary exists
if [ ! -x "${BCHN_DIR}/bin/bitcoind" ]; then
    log "ERROR: BCHN not found at ${BCHN_DIR}/bin/bitcoind"
    exit 1
fi

sudo systemctl start node-bch-bchn

# Verify service started
sleep 2
if ! systemctl is-active --quiet node-bch-bchn; then
    log "ERROR: Failed to start node-bch-bchn service"
    log "Check: sudo journalctl -u node-bch-bchn -n 50"
    exit 1
fi

# Wait for node to be responsive
log "Waiting for node to be responsive..."
NODE_READY=false
for i in $(seq 1 60); do
    if ${BCHN_DIR}/bin/bitcoin-cli -conf=${BCHN_DIR}/config/bitcoin.conf getblockchaininfo &>/dev/null; then
        NODE_READY=true
        break
    fi
    sleep 5
done

if [ "${NODE_READY}" != "true" ]; then
    log "ERROR: Node not responding after 5 minutes"
    exit 1
fi

# =============================================================================
# 2. WAIT FOR SYNC
# =============================================================================
log "Waiting for blockchain sync..."

while true; do
    # Get sync progress
    SYNC_INFO=$(${BCHN_DIR}/bin/bitcoin-cli -conf=${BCHN_DIR}/config/bitcoin.conf getblockchaininfo 2>/dev/null)

    if [ -n "${SYNC_INFO}" ]; then
        PROGRESS=$(echo "${SYNC_INFO}" | grep -o '"verificationprogress":[^,]*' | cut -d':' -f2 | tr -d ' ')
        BLOCKS=$(echo "${SYNC_INFO}" | grep -o '"blocks":[^,]*' | cut -d':' -f2 | tr -d ' ')
        HEADERS=$(echo "${SYNC_INFO}" | grep -o '"headers":[^,]*' | cut -d':' -f2 | tr -d ' ')

        # Calculate percentage
        if [ -n "${PROGRESS}" ]; then
            PERCENT=$(echo "${PROGRESS} * 100" | bc -l 2>/dev/null | cut -d'.' -f1)
            [ -z "${PERCENT}" ] && PERCENT="0"

            log "Sync progress: ${PERCENT}% (blocks: ${BLOCKS}/${HEADERS})"

            # Check if synced (> 99.9%)
            if [ "$(echo "${PROGRESS} > 0.999" | bc -l 2>/dev/null)" = "1" ]; then
                log "Blockchain synced!"
                break
            fi
        fi
    else
        log "Waiting for node..."
    fi

    sleep 30
done

# =============================================================================
# 3. START STRATUM
# =============================================================================
log "Starting CKPool stratum..."
sudo systemctl start pool-bch-ckpool

# Verify stratum is running
sleep 5
if systemctl is-active --quiet pool-bch-ckpool; then
    log "CKPool stratum started successfully"
    log "Stratum port: ${BCH_STRATUM_PORT:-3334}"
else
    log "ERROR: Failed to start CKPool stratum"
    exit 1
fi

log "Bitcoin Cash startup complete!"
