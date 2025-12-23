#!/bin/bash
# =============================================================================
# start-xmr.sh - Monero startup sequence
# Starts node, waits for sync, initializes wallet, starts wallet-rpc, starts stratum
# =============================================================================

source /opt/solo-pool/install-scripts/config.sh

if [ "${CONFIG_LOADED:-}" != "true" ]; then
    echo "[XMR] ERROR: Failed to load configuration" >&2
    exit 1
fi

if [ "${ENABLE_MONERO_POOL}" != "true" ]; then
    echo "[XMR] Monero pool not enabled, skipping"
    exit 0
fi

log() {
    echo "[XMR] $(date '+%H:%M:%S') $1"
}

# =============================================================================
# 1. START NODE
# =============================================================================
log "Starting Monero node..."
sudo systemctl start node-xmr-monerod

# Wait for node to be responsive
log "Waiting for node to be responsive..."
for i in $(seq 1 60); do
    if ${MONERO_DIR}/bin/monerod --rpc-bind-port=${MONERO_RPC_PORT:-18081} status &>/dev/null; then
        break
    fi
    sleep 5
done

# =============================================================================
# 2. WAIT FOR SYNC
# =============================================================================
log "Waiting for blockchain sync..."

while true; do
    # Get sync status from monerod
    STATUS=$(${MONERO_DIR}/bin/monerod --rpc-bind-port=${MONERO_RPC_PORT:-18081} status 2>/dev/null)

    if [ -n "${STATUS}" ]; then
        # Check for "Height:" line which indicates current block
        HEIGHT=$(echo "${STATUS}" | grep -oP 'Height: \K[0-9]+' | head -1)
        TARGET=$(echo "${STATUS}" | grep -oP 'target: \K[0-9]+' | head -1)

        # Alternative: check sync_info via RPC
        SYNC_INFO=$(curl -s -X POST http://127.0.0.1:${MONERO_RPC_PORT:-18081}/json_rpc \
            -d '{"jsonrpc":"2.0","id":"0","method":"sync_info"}' \
            -H 'Content-Type: application/json' 2>/dev/null)

        if [ -n "${SYNC_INFO}" ]; then
            HEIGHT=$(echo "${SYNC_INFO}" | grep -o '"height":[0-9]*' | head -1 | cut -d':' -f2)
            TARGET_HEIGHT=$(echo "${SYNC_INFO}" | grep -o '"target_height":[0-9]*' | head -1 | cut -d':' -f2)

            if [ -n "${HEIGHT}" ] && [ -n "${TARGET_HEIGHT}" ] && [ "${TARGET_HEIGHT}" -gt 0 ]; then
                PERCENT=$((HEIGHT * 100 / TARGET_HEIGHT))
                log "Sync progress: ${PERCENT}% (blocks: ${HEIGHT}/${TARGET_HEIGHT})"

                # Check if synced
                if [ "${HEIGHT}" -ge "${TARGET_HEIGHT}" ] || [ "${TARGET_HEIGHT}" -eq 0 ]; then
                    # Double-check: target_height of 0 or equal means synced
                    log "Blockchain synced!"
                    break
                fi
            fi
        fi

        # Also check if "synchronized" appears in status
        if echo "${STATUS}" | grep -qi "synchronized"; then
            log "Blockchain synced!"
            break
        fi
    else
        log "Waiting for node..."
    fi

    sleep 30
done

# =============================================================================
# 3. INITIALIZE WALLET (if not already done)
# =============================================================================
WALLET_DIR="${MONERO_DIR}/wallet"
WALLET_FILE="${WALLET_DIR}/pool-wallet"
WALLET_INITIALIZED="${WALLET_DIR}/.initialized"

if [ ! -f "${WALLET_INITIALIZED}" ]; then
    log "Initializing pool wallet..."

    # Check if wallet files already exist (created during install)
    if [ -f "${WALLET_FILE}" ]; then
        log "Wallet files exist, marking as initialized"
    else
        log "Creating new wallet..."
        WALLET_PASSWORD=$(cat "${WALLET_DIR}/pool-wallet.password" 2>/dev/null)

        if [ -z "${WALLET_PASSWORD}" ]; then
            log "ERROR: Wallet password file not found"
            exit 1
        fi

        # Create wallet
        ${MONERO_DIR}/bin/monero-wallet-cli \
            --daemon-address 127.0.0.1:${MONERO_RPC_PORT:-18081} \
            --generate-new-wallet "${WALLET_FILE}" \
            --password "${WALLET_PASSWORD}" \
            --mnemonic-language English \
            --command "exit" 2>/dev/null

        if [ ! -f "${WALLET_FILE}" ]; then
            log "ERROR: Failed to create wallet"
            exit 1
        fi

        # Export seed for backup
        log "Exporting seed words for backup..."
        ${MONERO_DIR}/bin/monero-wallet-cli \
            --wallet-file "${WALLET_FILE}" \
            --password "${WALLET_PASSWORD}" \
            --command "seed" > "${WALLET_DIR}/SEED_BACKUP.txt" 2>/dev/null

        chmod 600 "${WALLET_DIR}/SEED_BACKUP.txt"

        # Get wallet address
        WALLET_ADDRESS=$(${MONERO_DIR}/bin/monero-wallet-cli \
            --wallet-file "${WALLET_FILE}" \
            --password "${WALLET_PASSWORD}" \
            --command "address" 2>/dev/null | grep -oP '^4[0-9A-Za-z]{94}' | head -1)

        if [ -n "${WALLET_ADDRESS}" ]; then
            echo "${WALLET_ADDRESS}" > "${WALLET_DIR}/pool-wallet.address"
            chmod 644 "${WALLET_DIR}/pool-wallet.address"
            log "Wallet address: ${WALLET_ADDRESS:0:20}..."
        fi
    fi

    touch "${WALLET_INITIALIZED}"
    log "Wallet initialized"
    log "*** BACKUP ${WALLET_DIR}/SEED_BACKUP.txt immediately! ***"
else
    log "Wallet already initialized"
fi

# =============================================================================
# 4. START WALLET RPC
# =============================================================================
log "Starting wallet RPC..."
sudo systemctl start wallet-xmr-rpc

sleep 5
if systemctl is-active --quiet wallet-xmr-rpc; then
    log "Wallet RPC started successfully"
else
    log "WARNING: Wallet RPC may not have started correctly"
fi

# =============================================================================
# 5. START STRATUM (only for monero_only mode)
# =============================================================================
if [ "${MONERO_TARI_MODE}" = "monero_only" ]; then
    log "Starting monero-pool stratum..."
    sudo systemctl start pool-xmr-monero-pool

    sleep 5
    if systemctl is-active --quiet pool-xmr-monero-pool; then
        log "monero-pool stratum started successfully"
        log "Stratum port: ${XMR_STRATUM_PORT:-3336}"
    else
        log "ERROR: Failed to start monero-pool stratum"
        exit 1
    fi
else
    log "Merge mining mode - stratum handled by XTM startup"
fi

log "Monero startup complete!"
