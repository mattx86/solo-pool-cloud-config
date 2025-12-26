#!/bin/bash
# =============================================================================
# sync-status.sh - Check blockchain sync status for all enabled nodes
# =============================================================================

source /opt/solo-pool/install/config.sh

# Validate config was loaded
if [ "${CONFIG_LOADED:-}" != "true" ]; then
    echo "ERROR: Failed to load configuration" >&2
    exit 1
fi

echo "=============================================="
echo "       Blockchain Sync Status"
echo "=============================================="
echo ""

# Determine effective ports and network names based on network mode
if [ "${NETWORK_MODE}" = "testnet" ]; then
    BTC_EFFECTIVE_PORT="48332"
    BCH_EFFECTIVE_PORT="48334"
    DGB_EFFECTIVE_PORT="14023"
    XMR_EFFECTIVE_PORT="38081"
    TARI_NETWORK="esmeralda"
    ALEO_NETWORK="testnet"
    NETWORK_LABEL="TESTNET"
else
    BTC_EFFECTIVE_PORT="${BITCOIN_RPC_PORT}"
    BCH_EFFECTIVE_PORT="${BCH_RPC_PORT}"
    DGB_EFFECTIVE_PORT="${DGB_RPC_PORT}"
    XMR_EFFECTIVE_PORT="${MONERO_RPC_PORT}"
    TARI_NETWORK="mainnet"
    ALEO_NETWORK="mainnet"
    NETWORK_LABEL="MAINNET"
fi

echo "Network Mode: ${NETWORK_LABEL}"
echo "Sync Mode: ${SYNC_MODE:-production}"
echo ""

# Read Monero RPC credentials (for merge/merged modes with RPC auth)
XMR_RPC_USER=$(cat ${MONERO_DIR}/config/rpc.user 2>/dev/null || echo "")
XMR_RPC_PASSWORD=$(cat ${MONERO_DIR}/config/rpc.password 2>/dev/null || echo "")

# Helper function to check if service is running
check_service() {
    systemctl is-active --quiet "$1" 2>/dev/null
}

# Bitcoin
if [ "${ENABLE_BITCOIN_POOL}" = "true" ]; then
    echo "Bitcoin (BTC):"
    if check_service "node-btc-bitcoind"; then
        RESULT=$(${BITCOIN_DIR}/bin/bitcoin-cli \
            -datadir=${BITCOIN_DIR}/data \
            -conf=${BITCOIN_DIR}/config/bitcoin.conf \
            getblockchaininfo 2>/dev/null)
        if [ $? -eq 0 ] && [ -n "$RESULT" ]; then
            echo "$RESULT" | jq -r '"  Blocks: \(.blocks) / Headers: \(.headers)\n  Progress: \((.verificationprogress * 100 * 100 | floor) / 100)%\n  Chain: \(.chain)"'
        else
            echo "  Node running but RPC not responding (still starting?)"
        fi
    else
        echo "  Node service not running"
    fi
    echo ""
fi

# Bitcoin Cash
if [ "${ENABLE_BCH_POOL}" = "true" ]; then
    echo "Bitcoin Cash (BCH):"
    if check_service "node-bch-bchn"; then
        RESULT=$(${BCHN_DIR}/bin/bitcoin-cli \
            -datadir=${BCHN_DIR}/data \
            -conf=${BCHN_DIR}/config/bitcoin.conf \
            getblockchaininfo 2>/dev/null)
        if [ $? -eq 0 ] && [ -n "$RESULT" ]; then
            echo "$RESULT" | jq -r '"  Blocks: \(.blocks) / Headers: \(.headers)\n  Progress: \((.verificationprogress * 100 * 100 | floor) / 100)%\n  Chain: \(.chain)"'
        else
            echo "  Node running but RPC not responding (still starting?)"
        fi
    else
        echo "  Node service not running"
    fi
    echo ""
fi

# DigiByte
if [ "${ENABLE_DGB_POOL}" = "true" ]; then
    echo "DigiByte (DGB):"
    if check_service "node-dgb-digibyted"; then
        RESULT=$(${DIGIBYTE_DIR}/bin/digibyte-cli \
            -datadir=${DIGIBYTE_DIR}/data \
            -conf=${DIGIBYTE_DIR}/config/digibyte.conf \
            getblockchaininfo 2>/dev/null)
        if [ $? -eq 0 ] && [ -n "$RESULT" ]; then
            echo "$RESULT" | jq -r '"  Blocks: \(.blocks) / Headers: \(.headers)\n  Progress: \((.verificationprogress * 100 * 100 | floor) / 100)%\n  Chain: \(.chain)"'
        else
            echo "  Node running but RPC not responding (still starting?)"
        fi
    else
        echo "  Node service not running"
    fi
    echo ""
fi

# Monero
case "${ENABLE_MONERO_TARI_POOL}" in
    merge|merged|monero_only)
        echo "Monero (XMR):"
        if check_service "node-xmr-monerod"; then
            # Build curl auth options (digest auth for monerod)
            CURL_AUTH=""
            if [ -n "${XMR_RPC_PASSWORD}" ]; then
                CURL_AUTH="--digest -u ${XMR_RPC_USER}:${XMR_RPC_PASSWORD}"
            fi
            RESULT=$(curl -s --max-time 5 ${CURL_AUTH} \
                http://127.0.0.1:${XMR_EFFECTIVE_PORT}/json_rpc \
                -d '{"jsonrpc":"2.0","id":"0","method":"get_info"}' \
                -H 'Content-Type: application/json' 2>/dev/null)
            if [ $? -eq 0 ] && [ -n "$RESULT" ]; then
                echo "$RESULT" | jq -r '"  Height: \(.result.height) / Target: \(.result.target_height // 0)\n  Synced: \(if .result.synchronized then "Yes" elif (.result.target_height // 0) == 0 then "No (waiting for peers)" else "No (\(.result.height * 100 / .result.target_height | floor)%)" end)\n  Network: \(if .result.stagenet then "stagenet" elif .result.testnet then "testnet" else "mainnet" end)"'
            else
                echo "  Node running but RPC not responding (still starting?)"
            fi
        else
            echo "  Node service not running"
        fi
        echo ""
        ;;
esac

# Tari
case "${ENABLE_MONERO_TARI_POOL}" in
    merge|merged|tari_only)
        echo "Tari (XTM):"
        if check_service "node-xtm-minotari"; then
            # Check if gRPC port is listening
            if ss -tlnp 2>/dev/null | grep -q ":${TARI_NODE_GRPC_PORT}" || \
               netstat -tlnp 2>/dev/null | grep -q ":${TARI_NODE_GRPC_PORT}"; then
                echo "  Network: ${TARI_NETWORK:-mainnet}"

                # Read RPC credentials
                XTM_RPC_USER=$(cat ${TARI_DIR}/config/rpc.user 2>/dev/null || echo "")
                XTM_RPC_PASSWORD=$(cat ${TARI_DIR}/config/rpc.password 2>/dev/null || echo "")

                # Query sync progress via gRPC
                GRPC_RESULT=$(grpcurl -plaintext \
                    -H "authorization: Basic $(echo -n "${XTM_RPC_USER}:${XTM_RPC_PASSWORD}" | base64)" \
                    127.0.0.1:${TARI_NODE_GRPC_PORT} \
                    tari.rpc.BaseNode/GetSyncProgress 2>/dev/null)

                if [ -n "$GRPC_RESULT" ]; then
                    # Parse JSON response
                    TIP_HEIGHT=$(echo "$GRPC_RESULT" | jq -r '.tipHeight // 0' 2>/dev/null)
                    LOCAL_HEIGHT=$(echo "$GRPC_RESULT" | jq -r '.localHeight // 0' 2>/dev/null)
                    STATE=$(echo "$GRPC_RESULT" | jq -r '.state // "unknown"' 2>/dev/null)

                    echo "  Height: ${LOCAL_HEIGHT} / ${TIP_HEIGHT}"
                    if [ "$TIP_HEIGHT" -gt 0 ] 2>/dev/null; then
                        PERCENT=$((LOCAL_HEIGHT * 100 / TIP_HEIGHT))
                        echo "  Progress: ${PERCENT}%"
                    fi
                    echo "  State: ${STATE}"
                else
                    echo "  gRPC not responding (still starting?)"
                fi
            else
                echo "  Node running but gRPC not yet available (still starting?)"
            fi
        else
            echo "  Node service not running"
        fi
        echo ""
        ;;
esac

# ALEO
if [ "${ENABLE_ALEO_POOL}" = "true" ]; then
    echo "ALEO:"
    if check_service "node-aleo-snarkos"; then
        # snarkOS v4.x sync_status endpoint returns JSON with sync info
        SYNC_JSON=$(curl -s --max-time 5 \
            "http://127.0.0.1:${ALEO_REST_PORT}/${ALEO_NETWORK}/sync_status" 2>/dev/null)

        if [ -n "$SYNC_JSON" ] && echo "$SYNC_JSON" | jq -e . >/dev/null 2>&1; then
            # Parse sync status JSON
            LEDGER_HEIGHT=$(echo "$SYNC_JSON" | jq -r '.ledger_height // 0')
            IS_SYNCED=$(echo "$SYNC_JSON" | jq -r '.is_synced // false')
            SYNC_MODE=$(echo "$SYNC_JSON" | jq -r '.sync_mode // "unknown"')
            TARGET_HEIGHT=$(echo "$SYNC_JSON" | jq -r '.cdn_height // .p2p_height // 0')

            echo "  Height: ${LEDGER_HEIGHT} / ${TARGET_HEIGHT}"
            if [ "$IS_SYNCED" = "true" ]; then
                echo "  Synced: Yes"
            elif [ "$TARGET_HEIGHT" -gt 0 ] 2>/dev/null; then
                PERCENT=$((LEDGER_HEIGHT * 100 / TARGET_HEIGHT))
                echo "  Synced: No (${PERCENT}%)"
            else
                echo "  Synced: No (${SYNC_MODE})"
            fi
            echo "  Network: ${ALEO_NETWORK}"
        else
            # Fallback to simple height check if sync_status not available
            HEIGHT=$(curl -s --max-time 5 \
                "http://127.0.0.1:${ALEO_REST_PORT}/${ALEO_NETWORK}/block/height/latest" 2>/dev/null)
            if [ -n "$HEIGHT" ] && [ "$HEIGHT" != "null" ]; then
                echo "  Height: ${HEIGHT}"
                echo "  Network: ${ALEO_NETWORK}"
            else
                echo "  Node running but REST API not responding (still starting?)"
            fi
        fi
    else
        echo "  Node service not running"
    fi
    echo ""
fi

echo "=============================================="
echo ""

# Show quick summary
echo "Quick Tips:"
echo "  - Start all services: ${BIN_DIR}/start-all.sh"
echo "  - Check service logs: journalctl -u <service> -f"
echo "  - Switch to production: ${BIN_DIR}/switch-mode.sh production"
echo ""
