#!/bin/bash
# =============================================================================
# start-aleo.sh - ALEO startup sequence
# Starts node, waits for sync, then starts stratum
# Note: ALEO wallet (keypair) is generated during installation
# =============================================================================

source /opt/solo-pool/install/config.sh

if [ "${CONFIG_LOADED:-}" != "true" ]; then
    echo "[ALEO] ERROR: Failed to load configuration" >&2
    exit 1
fi

if [ "${ENABLE_ALEO_POOL}" != "true" ]; then
    echo "[ALEO] ALEO pool not enabled, skipping"
    exit 0
fi

log() {
    echo "[ALEO] $(date '+%H:%M:%S') $1"
}

# =============================================================================
# 1. START NODE
# =============================================================================
log "Starting ALEO node (snarkOS)..."
sudo systemctl start node-aleo-snarkos

# Wait for node to be responsive
log "Waiting for node to be responsive..."
for i in $(seq 1 60); do
    # Check if REST API is responding
    if curl -s http://127.0.0.1:${ALEO_REST_PORT:-3030}/testnet/latest/height &>/dev/null; then
        break
    fi
    sleep 5
done

# =============================================================================
# 2. WAIT FOR SYNC
# =============================================================================
log "Waiting for blockchain sync..."

# Get target height from a peer or known source (if available)
# For ALEO, we check if the node is synced by comparing heights

while true; do
    # Get current height
    CURRENT_HEIGHT=$(curl -s http://127.0.0.1:${ALEO_REST_PORT:-3030}/testnet/latest/height 2>/dev/null)

    if [ -n "${CURRENT_HEIGHT}" ] && [ "${CURRENT_HEIGHT}" -gt 0 ] 2>/dev/null; then
        # Check sync status from logs
        SYNC_STATUS=$(journalctl -u node-aleo-snarkos --no-pager -n 20 2>/dev/null)

        # Look for sync progress in logs
        if echo "${SYNC_STATUS}" | grep -qi "synced\|synchronized"; then
            log "Blockchain synced! Height: ${CURRENT_HEIGHT}"
            break
        fi

        # Check if node is making progress
        PROGRESS=$(echo "${SYNC_STATUS}" | grep -oP '\d+/\d+' | tail -1)
        if [ -n "${PROGRESS}" ]; then
            log "Sync progress: ${PROGRESS} (current height: ${CURRENT_HEIGHT})"
        else
            log "Current height: ${CURRENT_HEIGHT}"
        fi

        # If height is stable and node reports ready, consider synced
        # snarkOS typically logs "Node is ready" when synced
        if echo "${SYNC_STATUS}" | grep -qi "ready"; then
            log "Node reports ready! Height: ${CURRENT_HEIGHT}"
            break
        fi
    else
        log "Waiting for node..."
    fi

    sleep 30
done

# =============================================================================
# 3. VERIFY WALLET
# =============================================================================
WALLET_DIR="${ALEO_DIR}/wallet"
WALLET_KEYS_DIR="${WALLET_DIR}/keys"

if [ ! -f "${WALLET_KEYS_DIR}/pool-wallet.privatekey" ]; then
    log "ERROR: ALEO wallet private key not found"
    log "Expected at: ${WALLET_KEYS_DIR}/pool-wallet.privatekey"
    exit 1
fi

WALLET_ADDRESS=$(cat "${WALLET_KEYS_DIR}/pool-wallet.address" 2>/dev/null)
if [ -n "${WALLET_ADDRESS}" ]; then
    log "Wallet address: ${WALLET_ADDRESS:0:20}..."
else
    log "WARNING: Could not read wallet address file"
fi

# =============================================================================
# 4. START STRATUM
# =============================================================================
log "Starting ALEO pool stratum..."
sudo systemctl start pool-aleo

sleep 5
if systemctl is-active --quiet pool-aleo; then
    log "ALEO pool stratum started successfully"
    log "Stratum port: ${ALEO_STRATUM_PORT:-3339}"
else
    log "ERROR: Failed to start ALEO pool stratum"
    exit 1
fi

log "ALEO startup complete!"
