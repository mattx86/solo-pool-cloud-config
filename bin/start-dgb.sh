#!/bin/bash
# =============================================================================
# start-dgb.sh - DigiByte startup sequence
# Starts node, waits for sync, then starts stratum
# =============================================================================

source /opt/solo-pool/install/config.sh

if [ "${CONFIG_LOADED:-}" != "true" ]; then
    echo "[DGB] ERROR: Failed to load configuration" >&2
    exit 1
fi

if [ "${ENABLE_DGB_POOL}" != "true" ]; then
    echo "[DGB] DigiByte pool not enabled, skipping"
    exit 0
fi

log() {
    echo "[DGB] $(date '+%H:%M:%S') $1"
}

# =============================================================================
# 1. START NODE
# =============================================================================
log "Starting DigiByte node..."

# Check if digibyted binary exists
if [ ! -x "${DIGIBYTE_DIR}/bin/digibyted" ]; then
    log "ERROR: digibyted not found at ${DIGIBYTE_DIR}/bin/digibyted"
    exit 1
fi

sudo systemctl start node-dgb-digibyted

# Verify service started
sleep 2
if ! systemctl is-active --quiet node-dgb-digibyted; then
    log "ERROR: Failed to start node-dgb-digibyted service"
    log "Check: sudo journalctl -u node-dgb-digibyted -n 50"
    exit 1
fi

# Wait for node to be responsive
log "Waiting for node to be responsive..."
NODE_READY=false
for i in $(seq 1 60); do
    if ${DIGIBYTE_DIR}/bin/digibyte-cli -conf=${DIGIBYTE_DIR}/config/digibyte.conf getblockchaininfo &>/dev/null; then
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
    SYNC_INFO=$(${DIGIBYTE_DIR}/bin/digibyte-cli -conf=${DIGIBYTE_DIR}/config/digibyte.conf getblockchaininfo 2>/dev/null)

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
sudo systemctl start pool-dgb-ckpool

# Verify stratum is running
sleep 5
if systemctl is-active --quiet pool-dgb-ckpool; then
    log "CKPool stratum started successfully"
    log "Stratum port: ${DGB_STRATUM_PORT:-3335}"
else
    log "ERROR: Failed to start CKPool stratum"
    exit 1
fi

log "DigiByte startup complete!"
