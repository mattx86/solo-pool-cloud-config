#!/bin/bash
# =============================================================================
# start-xtm.sh - Tari startup sequence
# Starts node, waits for sync, initializes wallet, starts wallet, starts stratum
# For merge mode: waits for XMR to be synced first, then starts merge proxy
# =============================================================================

source /opt/solo-pool/install/config.sh

if [ "${CONFIG_LOADED:-}" != "true" ]; then
    echo "[XTM] ERROR: Failed to load configuration" >&2
    exit 1
fi

# Check if Tari pool is enabled (merge, merged, or tari_only modes)
case "${ENABLE_MONERO_TARI_POOL}" in
    merge|merged|tari_only)
        ;;
    *)
        echo "[XTM] Tari pool not enabled, skipping"
        exit 0
        ;;
esac

# Determine network mode
if [ "${NETWORK_MODE}" = "testnet" ]; then
    TARI_NETWORK="esmeralda"
else
    TARI_NETWORK="mainnet"
fi

log() {
    echo "[XTM] $(date '+%H:%M:%S') $1"
}

# =============================================================================
# 1. START NODE
# =============================================================================
log "Starting Tari node..."

# Check if minotari_node binary exists
if [ ! -x "${TARI_DIR}/bin/minotari_node" ]; then
    log "ERROR: minotari_node not found at ${TARI_DIR}/bin/minotari_node"
    exit 1
fi

sudo systemctl start node-xtm-minotari

# Verify service started
sleep 2
if ! systemctl is-active --quiet node-xtm-minotari; then
    log "ERROR: Failed to start node-xtm-minotari service"
    log "Check: sudo journalctl -u node-xtm-minotari -n 50"
    exit 1
fi

# Wait for node to be responsive
log "Waiting for node to be responsive..."
NODE_READY=false
for i in $(seq 1 60); do
    # Check if gRPC port is listening
    if nc -z 127.0.0.1 ${TARI_NODE_GRPC_PORT:-18142} 2>/dev/null; then
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
    # Try to get sync status via gRPC (using grpcurl if available)
    # Fallback: check log files or use a simple connectivity test

    # For now, we'll check if the node reports synced via its logs
    # or use a timeout-based approach with connectivity checks

    # Check node logs for sync status
    SYNC_STATUS=$(journalctl -u node-xtm-minotari --no-pager -n 50 2>/dev/null | grep -i "sync" | tail -1)

    if echo "${SYNC_STATUS}" | grep -qi "synced\|synchronized\|100%"; then
        log "Blockchain synced!"
        break
    fi

    # Alternative: check if node is responsive and has been running for a while
    # This is a fallback - ideally we'd use gRPC to get proper sync status

    # Extract progress from logs if available
    PROGRESS=$(journalctl -u node-xtm-minotari --no-pager -n 20 2>/dev/null | \
        grep -oP '\d+\.?\d*%' | tail -1)

    if [ -n "${PROGRESS}" ]; then
        log "Sync progress: ${PROGRESS}"
    else
        log "Syncing... (checking logs for progress)"
    fi

    # Check if fully synced by looking for specific log messages
    if journalctl -u node-xtm-minotari --no-pager -n 10 2>/dev/null | grep -q "Listening for"; then
        # Node is listening, likely synced
        log "Node appears to be synced and listening"
        break
    fi

    sleep 30
done

# =============================================================================
# 3. INITIALIZE WALLET (if not already done)
# =============================================================================
WALLET_DIR="${TARI_DIR}/wallet"
WALLET_KEYS_DIR="${WALLET_DIR}/keys"
WALLET_CONFIG="${WALLET_DIR}/config/config.toml"
WALLET_INITIALIZED="${WALLET_DIR}/.initialized"

if [ ! -f "${WALLET_INITIALIZED}" ]; then
    log "Initializing pool wallet..."

    # Create keys directory if it doesn't exist
    mkdir -p "${WALLET_KEYS_DIR}"

    WALLET_PASSWORD=$(cat "${WALLET_KEYS_DIR}/pool-wallet.password" 2>/dev/null)

    if [ -z "${WALLET_PASSWORD}" ]; then
        log "ERROR: Wallet password file not found"
        exit 1
    fi

    # Check if wallet data already exists
    if [ -d "${WALLET_DIR}/data" ] && [ "$(ls -A ${WALLET_DIR}/data 2>/dev/null)" ]; then
        log "Wallet data exists, extracting address..."
    else
        log "Creating new wallet..."

        # Initialize wallet
        ${TARI_DIR}/bin/minotari_console_wallet \
            --config ${WALLET_CONFIG} \
            --password "${WALLET_PASSWORD}" \
            --network ${TARI_NETWORK} \
            --non-interactive \
            --command "get-balance" 2>/dev/null || true

        sleep 2
    fi

    # Export seed words for backup
    log "Exporting seed words for backup..."
    ${TARI_DIR}/bin/minotari_console_wallet \
        --config ${WALLET_CONFIG} \
        --password "${WALLET_PASSWORD}" \
        --network ${TARI_NETWORK} \
        --non-interactive \
        --command "export-seed-words" > "${WALLET_KEYS_DIR}/SEED_BACKUP.txt" 2>/dev/null || true

    chmod 600 "${WALLET_KEYS_DIR}/SEED_BACKUP.txt"

    # Get wallet address
    log "Extracting wallet address..."
    WALLET_ADDRESS=""
    for i in 1 2 3; do
        WALLET_ADDRESS=$(${TARI_DIR}/bin/minotari_console_wallet \
            --config ${WALLET_CONFIG} \
            --password "${WALLET_PASSWORD}" \
            --network ${TARI_NETWORK} \
            --non-interactive \
            --command "get-address" 2>/dev/null | grep -E '^[a-f0-9]{64}' | head -1)

        if [ -n "${WALLET_ADDRESS}" ]; then
            break
        fi
        sleep 2
    done

    if [ -n "${WALLET_ADDRESS}" ]; then
        echo "${WALLET_ADDRESS}" > "${WALLET_KEYS_DIR}/pool-wallet.address"
        chmod 644 "${WALLET_KEYS_DIR}/pool-wallet.address"
        log "Wallet address: ${WALLET_ADDRESS:0:20}..."
    else
        log "WARNING: Could not extract wallet address"
    fi

    touch "${WALLET_INITIALIZED}"
    log "Wallet initialized"
    log "*** BACKUP ${WALLET_KEYS_DIR}/SEED_BACKUP.txt immediately! ***"
else
    log "Wallet already initialized"
fi

# =============================================================================
# 4. START WALLET SERVICE
# =============================================================================
log "Starting wallet service..."
sudo systemctl start wallet-xtm

sleep 5
if systemctl is-active --quiet wallet-xtm; then
    log "Wallet service started successfully"
else
    log "WARNING: Wallet service may not have started correctly"
fi

# =============================================================================
# 5. START STRATUM
# =============================================================================
if [ "${ENABLE_MONERO_TARI_POOL}" = "merge" ] || [ "${ENABLE_MONERO_TARI_POOL}" = "merged" ]; then
    # For merge mode, wait for XMR to be ready first
    log "Merge mode: waiting for Monero node to be synced..."

    while true; do
        # Check if XMR wallet-rpc is running (indicates XMR is ready)
        if systemctl is-active --quiet wallet-xmr-rpc; then
            log "Monero ready, starting merge mining proxy..."
            break
        fi
        log "Waiting for Monero..."
        sleep 30
    done

    sudo systemctl start pool-xmr-xtm-merge-proxy

    sleep 5
    if systemctl is-active --quiet pool-xmr-xtm-merge-proxy; then
        log "Merge mining proxy started successfully"
        log "Stratum port: ${XMR_XTM_MERGE_STRATUM_PORT:-3338}"
    else
        log "ERROR: Failed to start merge mining proxy"
        exit 1
    fi

elif [ "${ENABLE_MONERO_TARI_POOL}" = "tari_only" ]; then
    log "Starting Tari miner stratum..."
    sudo systemctl start pool-xtm-minotari-miner

    sleep 5
    if systemctl is-active --quiet pool-xtm-minotari-miner; then
        log "Tari miner stratum started successfully"
        log "Stratum port: ${XTM_STRATUM_PORT:-3337}"
    else
        log "ERROR: Failed to start Tari miner stratum"
        exit 1
    fi
fi

log "Tari startup complete!"
