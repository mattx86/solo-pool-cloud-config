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
                echo "$RESULT" | jq -r '"  Height: \(.result.height) / Target: \(.result.target_height)\n  Synced: \(if .result.synchronized then "Yes" else "No (\(.result.height * 100 / .result.target_height | floor)%)" end)\n  Network: \(if .result.stagenet then "stagenet" elif .result.testnet then "testnet" else "mainnet" end)"'
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
            # Check if gRPC port is listening (Tari uses gRPC, not HTTP)
            if ss -tlnp 2>/dev/null | grep -q ":${TARI_NODE_GRPC_PORT}" || \
               netstat -tlnp 2>/dev/null | grep -q ":${TARI_NODE_GRPC_PORT}"; then
                echo "  Node running (gRPC port ${TARI_NODE_GRPC_PORT} listening)"
                echo "  Network: ${TARI_NETWORK:-mainnet}"
                # Try to get height from logs
                LAST_HEIGHT=$(journalctl -u node-xtm-minotari --no-pager -n 50 2>/dev/null | \
                    grep -oP 'height[=: ]+\K[0-9]+' | tail -1)
                if [ -n "$LAST_HEIGHT" ]; then
                    echo "  Last seen height: ${LAST_HEIGHT}"
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
        # Note: snarkOS v4.x uses JWT auth for protected endpoints (balance queries)
        # but sync status and block height are public endpoints - no auth needed here
        # JWT token for protected endpoints: ${ALEO_DIR}/config/jwt.token

        # Check sync status endpoint first (public)
        SYNC_STATUS=$(curl -s --max-time 5 \
            "http://127.0.0.1:${ALEO_REST_PORT}/${ALEO_NETWORK}/node/sync/status" 2>/dev/null)

        if [ -n "$SYNC_STATUS" ]; then
            echo "  Sync Mode: ${SYNC_STATUS}"
        fi

        # Get latest height
        HEIGHT=$(curl -s --max-time 5 \
            "http://127.0.0.1:${ALEO_REST_PORT}/${ALEO_NETWORK}/block/height/latest" 2>/dev/null)

        if [ -n "$HEIGHT" ] && [ "$HEIGHT" != "null" ]; then
            echo "  Latest Height: ${HEIGHT}"
            echo "  Network: ${ALEO_NETWORK}"
        else
            echo "  Node running but REST API not responding (still starting?)"
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
