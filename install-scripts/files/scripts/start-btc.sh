#!/bin/bash
# =============================================================================
# start-btc.sh - Bitcoin startup sequence
# Starts node, waits for sync, then starts stratum
# =============================================================================

source /opt/solo-pool/install-scripts/config.sh

if [ "${CONFIG_LOADED:-}" != "true" ]; then
    echo "[BTC] ERROR: Failed to load configuration" >&2
    exit 1
fi

if [ "${ENABLE_BITCOIN_POOL}" != "true" ]; then
    echo "[BTC] Bitcoin pool not enabled, skipping"
    exit 0
fi

log() {
    echo "[BTC] $(date '+%H:%M:%S') $1"
}

# =============================================================================
# 1. START NODE
# =============================================================================
log "Starting Bitcoin node..."
sudo systemctl start node-btc-bitcoind

# Wait for node to be responsive
log "Waiting for node to be responsive..."
for i in $(seq 1 60); do
    if ${BITCOIN_DIR}/bin/bitcoin-cli -conf=${BITCOIN_DIR}/bitcoin.conf getblockchaininfo &>/dev/null; then
        break
    fi
    sleep 5
done

# =============================================================================
# 2. WAIT FOR SYNC
# =============================================================================
log "Waiting for blockchain sync..."

while true; do
    # Get sync progress
    SYNC_INFO=$(${BITCOIN_DIR}/bin/bitcoin-cli -conf=${BITCOIN_DIR}/bitcoin.conf getblockchaininfo 2>/dev/null)

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
sudo systemctl start pool-btc-ckpool

# Verify stratum is running
sleep 5
if systemctl is-active --quiet pool-btc-ckpool; then
    log "CKPool stratum started successfully"
    log "Stratum port: ${BTC_STRATUM_PORT:-3333}"
else
    log "ERROR: Failed to start CKPool stratum"
    exit 1
fi

log "Bitcoin startup complete!"
