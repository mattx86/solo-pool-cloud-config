#!/bin/bash
# =============================================================================
# switch-mode.sh - Switch between initial sync and production modes
#
# Usage: switch-mode.sh <mode>
#   mode: "initial" for fast sync (blocksonly, db-sync-mode=fast)
#         "production" for mining-ready (full mempool, db-sync-mode=safe)
#
# This script:
# 1. Updates SYNC_MODE in config.sh
# 2. Regenerates node configuration files
# 3. Restarts affected node services
#
# WORKFLOW:
#   1. Deploy with SYNC_MODE="initial" for fast blockchain sync
#   2. Wait for all nodes to sync (use sync-status.sh to monitor)
#   3. Run: switch-mode.sh production
#   4. Start mining!
# =============================================================================

set -e

source /opt/solopool/install/config.sh

if [ "${CONFIG_LOADED:-}" != "true" ]; then
    echo "ERROR: Failed to load configuration" >&2
    exit 1
fi

# Check argument
if [ -z "$1" ]; then
    echo "Usage: $0 <mode>"
    echo "  mode: initial    - Fast sync (blocksonly, db-sync-mode=fast)"
    echo "        production - Mining-ready (full mempool, db-sync-mode=safe)"
    exit 1
fi

MODE="$1"

if [ "${MODE}" != "initial" ] && [ "${MODE}" != "production" ]; then
    echo "ERROR: Invalid mode '${MODE}'"
    echo "Valid modes: initial, production"
    exit 1
fi

echo "=============================================="
echo "  Solo Pool - Switching to ${MODE^^} mode"
echo "=============================================="
echo ""

# Update SYNC_MODE in config.sh
echo "1. Updating SYNC_MODE in config.sh..."
sed -i "s/^      SYNC_MODE=\".*\"/      SYNC_MODE=\"${MODE}\"/" /opt/solopool/install/config.sh

# Re-source config to get new setting
source /opt/solopool/install/config.sh

# Template directory
TEMPLATE_DIR="/opt/solopool/install/files/config"

# Regenerate Bitcoin config if enabled
if [ "${ENABLE_BITCOIN_POOL}" = "true" ]; then
    echo "2. Regenerating Bitcoin node configuration..."

    # Set up variables for template
    if [ "${ENABLE_INBOUND_P2P}" = "true" ]; then
        export BTC_LISTEN=1
    else
        export BTC_LISTEN=0
    fi

    if [ "${NETWORK_MODE}" = "testnet" ]; then
        export NETWORK_FLAG="testnet4=1"
        export NETWORK_SECTION="[testnet4]"
        export EFFECTIVE_RPC_PORT="48332"
    else
        export NETWORK_FLAG=""
        export NETWORK_SECTION="[main]"
        export EFFECTIVE_RPC_PORT="${BITCOIN_RPC_PORT}"
    fi

    if [ "${SYNC_MODE}" = "initial" ]; then
        export BLOCKSONLY_SETTING="blocksonly=1"
        echo "   Sync mode: INITIAL (blocksonly for faster sync)"
    else
        export BLOCKSONLY_SETTING="# blocksonly disabled - mining requires mempool"
        echo "   Sync mode: PRODUCTION (mempool enabled for mining)"
    fi

    # Get existing RPC password from current config
    export BTC_RPC_PASSWORD=$(grep "^rpcpassword=" ${BITCOIN_DIR}/config/bitcoin.conf | cut -d= -f2)

    export BITCOIN_DIR BITCOIN_RPC_PORT BITCOIN_ZMQ_BLOCK_PORT BITCOIN_ZMQ_TX_PORT
    envsubst < "${TEMPLATE_DIR}/bitcoin.conf.template" > ${BITCOIN_DIR}/config/bitcoin.conf
    chown ${POOL_USER}:${POOL_USER} ${BITCOIN_DIR}/config/bitcoin.conf
    chmod 600 ${BITCOIN_DIR}/config/bitcoin.conf
    echo "   Bitcoin config updated"
fi

# Regenerate BCH config if enabled
if [ "${ENABLE_BCH_POOL}" = "true" ]; then
    echo "3. Regenerating Bitcoin Cash node configuration..."

    if [ "${ENABLE_INBOUND_P2P}" = "true" ]; then
        export BCH_LISTEN=1
    else
        export BCH_LISTEN=0
    fi

    if [ "${NETWORK_MODE}" = "testnet" ]; then
        export NETWORK_FLAG="testnet4=1"
        export NETWORK_SECTION="[testnet4]"
        export EFFECTIVE_RPC_PORT="48334"
    else
        export NETWORK_FLAG=""
        export NETWORK_SECTION="[main]"
        export EFFECTIVE_RPC_PORT="${BCH_RPC_PORT}"
    fi

    if [ "${SYNC_MODE}" = "initial" ]; then
        export BLOCKSONLY_SETTING="blocksonly=1"
    else
        export BLOCKSONLY_SETTING="# blocksonly disabled - mining requires mempool"
    fi

    export BCH_RPC_PASSWORD=$(grep "^rpcpassword=" ${BCHN_DIR}/config/bitcoin.conf | cut -d= -f2)

    export BCHN_DIR BCH_RPC_PORT BCH_ZMQ_BLOCK_PORT BCH_ZMQ_TX_PORT
    envsubst < "${TEMPLATE_DIR}/bchn.conf.template" > ${BCHN_DIR}/config/bitcoin.conf
    chown ${POOL_USER}:${POOL_USER} ${BCHN_DIR}/config/bitcoin.conf
    chmod 600 ${BCHN_DIR}/config/bitcoin.conf
    echo "   BCH config updated"
fi

# Regenerate DigiByte config if enabled
if [ "${ENABLE_DGB_POOL}" = "true" ]; then
    echo "4. Regenerating DigiByte node configuration..."

    if [ "${ENABLE_INBOUND_P2P}" = "true" ]; then
        export DGB_LISTEN=1
    else
        export DGB_LISTEN=0
    fi

    if [ "${NETWORK_MODE}" = "testnet" ]; then
        export NETWORK_FLAG="testnet=1"
        export NETWORK_SECTION="[test]"
        export EFFECTIVE_RPC_PORT="14023"
    else
        export NETWORK_FLAG=""
        export NETWORK_SECTION="[main]"
        export EFFECTIVE_RPC_PORT="${DGB_RPC_PORT}"
    fi

    if [ "${SYNC_MODE}" = "initial" ]; then
        export BLOCKSONLY_SETTING="blocksonly=1"
    else
        export BLOCKSONLY_SETTING="# blocksonly disabled - mining requires mempool"
    fi

    export DGB_RPC_PASSWORD=$(grep "^rpcpassword=" ${DIGIBYTE_DIR}/config/digibyte.conf | cut -d= -f2)

    export DIGIBYTE_DIR DGB_RPC_PORT DGB_ZMQ_BLOCK_PORT DGB_ZMQ_TX_PORT
    envsubst < "${TEMPLATE_DIR}/digibyte.conf.template" > ${DIGIBYTE_DIR}/config/digibyte.conf
    chown ${POOL_USER}:${POOL_USER} ${DIGIBYTE_DIR}/config/digibyte.conf
    chmod 600 ${DIGIBYTE_DIR}/config/digibyte.conf
    echo "   DigiByte config updated"
fi

# Regenerate Monero config if enabled
case "${ENABLE_MONERO_TARI_POOL}" in
    merge|merged|monero_only)
        echo "5. Regenerating Monero node configuration..."

        if [ "${ENABLE_INBOUND_P2P}" = "true" ]; then
            export XMR_P2P_BIND="0.0.0.0"
            export XMR_IN_PEERS=""
        else
            export XMR_P2P_BIND="0.0.0.0"
            export XMR_IN_PEERS="in-peers=0"
        fi

        if [ "${NETWORK_MODE}" = "testnet" ]; then
            export NETWORK_FLAG="stagenet=1"
            export EFFECTIVE_RPC_PORT="38081"
            export XMR_P2P_PORT="38080"
        else
            export NETWORK_FLAG=""
            export EFFECTIVE_RPC_PORT="${MONERO_RPC_PORT}"
            export XMR_P2P_PORT="18080"
        fi

        if [ "${SYNC_MODE}" = "initial" ]; then
            export DB_SYNC_MODE="fast"
            echo "   Sync mode: INITIAL (db-sync-mode=fast)"
        else
            export DB_SYNC_MODE="safe"
            echo "   Sync mode: PRODUCTION (db-sync-mode=safe)"
        fi

        export MONERO_DIR MONERO_RPC_PORT MONERO_ZMQ_PORT
        envsubst < "${TEMPLATE_DIR}/monerod.conf.template" > ${MONERO_DIR}/config/monerod.conf
        chown ${POOL_USER}:${POOL_USER} ${MONERO_DIR}/config/monerod.conf
        chmod 600 ${MONERO_DIR}/config/monerod.conf
        echo "   Monero config updated"
        ;;
esac

echo ""
echo "6. Restarting node services..."
echo ""

# Restart nodes (not pools - they don't need to restart for sync mode change)
systemctl restart node-btc-bitcoind 2>/dev/null || true
systemctl restart node-bch-bchn 2>/dev/null || true
systemctl restart node-dgb-digibyted 2>/dev/null || true
systemctl restart node-xmr-monerod 2>/dev/null || true

echo ""
echo "=============================================="
echo "  Mode switched to: ${MODE^^}"
echo "=============================================="
echo ""

if [ "${MODE}" = "initial" ]; then
    echo "Initial sync mode is now active."
    echo "Nodes will sync faster but CANNOT mine."
    echo ""
    echo "When sync is complete, run:"
    echo "  ${BIN_DIR}/switch-mode.sh production"
else
    echo "Production mode is now active."
    echo "Nodes are ready for mining operations."
    echo ""
    echo "You can now start the pool services:"
    echo "  ${BIN_DIR}/start-pools.sh"
fi
echo ""
