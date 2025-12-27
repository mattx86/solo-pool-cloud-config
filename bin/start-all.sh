#!/bin/bash
# =============================================================================
# start-all.sh - Start all enabled services
#
# This script starts each coin's full stack (node → sync → wallet → stratum)
# in parallel. Each coin runs independently, so faster-syncing chains don't
# wait for slower ones.
#
# Usage:
#   ./start-all.sh           # Run in foreground (see all output)
#   ./start-all.sh --daemon  # Run in background with logging
# =============================================================================

source /opt/solopool/install/config.sh

if [ "${CONFIG_LOADED:-}" != "true" ]; then
    echo "ERROR: Failed to load configuration" >&2
    exit 1
fi

DAEMON_MODE=false
if [ "$1" = "--daemon" ] || [ "$1" = "-d" ]; then
    DAEMON_MODE=true
fi

LOG_DIR="${BASE_DIR}/logs/startup"
mkdir -p "${LOG_DIR}"

echo "=============================================="
echo "  Solo Pool - Starting All Services"
echo "=============================================="
echo ""
echo "Each chain will:"
echo "  1. Start its node"
echo "  2. Wait for blockchain sync"
echo "  3. Initialize wallet (if applicable)"
echo "  4. Start stratum server"
echo ""
echo "Chains start in parallel for fastest startup."
echo ""

# Track PIDs for parallel execution
declare -A PIDS

# Start WebUI first (doesn't need sync)
if [ "${ENABLE_WEBUI}" = "true" ]; then
    echo "[WEBUI] Starting dashboard..."
    sudo systemctl start solopool-webui
    if systemctl is-active --quiet solopool-webui; then
        echo "[WEBUI] Dashboard started"
    fi
fi

# Start payment processor (doesn't need sync, will wait for wallets)
NEED_PAYMENTS="false"
case "${ENABLE_MONERO_TARI_POOL}" in
    merge|merged|monero_only|tari_only) NEED_PAYMENTS="true" ;;
esac
[ "${ENABLE_ALEO_POOL}" = "true" ] && NEED_PAYMENTS="true"
if [ "${NEED_PAYMENTS}" = "true" ]; then
    echo "[PAYMENTS] Starting payment processor..."
    sudo systemctl start solopool-payments 2>/dev/null || true
fi

echo ""
echo "Starting blockchain nodes in parallel..."
echo ""

# Start each enabled coin in parallel
if [ "${ENABLE_BITCOIN_POOL}" = "true" ]; then
    if [ "${DAEMON_MODE}" = "true" ]; then
        nohup ${BIN_DIR}/start-btc.sh >> "${LOG_DIR}/btc.log" 2>&1 &
    else
        ${BIN_DIR}/start-btc.sh &
    fi
    PIDS[btc]=$!
    echo "[BTC] Started (PID: ${PIDS[btc]})"
fi

if [ "${ENABLE_BCH_POOL}" = "true" ]; then
    if [ "${DAEMON_MODE}" = "true" ]; then
        nohup ${BIN_DIR}/start-bch.sh >> "${LOG_DIR}/bch.log" 2>&1 &
    else
        ${BIN_DIR}/start-bch.sh &
    fi
    PIDS[bch]=$!
    echo "[BCH] Started (PID: ${PIDS[bch]})"
fi

if [ "${ENABLE_DGB_POOL}" = "true" ]; then
    if [ "${DAEMON_MODE}" = "true" ]; then
        nohup ${BIN_DIR}/start-dgb.sh >> "${LOG_DIR}/dgb.log" 2>&1 &
    else
        ${BIN_DIR}/start-dgb.sh &
    fi
    PIDS[dgb]=$!
    echo "[DGB] Started (PID: ${PIDS[dgb]})"
fi

# Start XMR if merge, merged, or monero_only mode
case "${ENABLE_MONERO_TARI_POOL}" in
    merge|merged|monero_only)
        if [ "${DAEMON_MODE}" = "true" ]; then
            nohup ${BIN_DIR}/start-xmr.sh >> "${LOG_DIR}/xmr.log" 2>&1 &
        else
            ${BIN_DIR}/start-xmr.sh &
        fi
        PIDS[xmr]=$!
        echo "[XMR] Started (PID: ${PIDS[xmr]})"
        ;;
esac

# Start XTM if merge, merged, or tari_only mode
case "${ENABLE_MONERO_TARI_POOL}" in
    merge|merged|tari_only)
        if [ "${DAEMON_MODE}" = "true" ]; then
            nohup ${BIN_DIR}/start-xtm.sh >> "${LOG_DIR}/xtm.log" 2>&1 &
        else
            ${BIN_DIR}/start-xtm.sh &
        fi
        PIDS[xtm]=$!
        echo "[XTM] Started (PID: ${PIDS[xtm]})"
        ;;
esac

if [ "${ENABLE_ALEO_POOL}" = "true" ]; then
    if [ "${DAEMON_MODE}" = "true" ]; then
        nohup ${BIN_DIR}/start-aleo.sh >> "${LOG_DIR}/aleo.log" 2>&1 &
    else
        ${BIN_DIR}/start-aleo.sh &
    fi
    PIDS[aleo]=$!
    echo "[ALEO] Started (PID: ${PIDS[aleo]})"
fi

echo ""

if [ "${DAEMON_MODE}" = "true" ]; then
    echo "Running in daemon mode. Logs available at:"
    echo "  ${LOG_DIR}/"
    echo ""
    echo "Monitor progress:"
    echo "  tail -f ${LOG_DIR}/*.log"
    echo ""
    echo "Check service status:"
    echo "  ${BIN_DIR}/status.sh"
else
    echo "Waiting for all chains to complete startup..."
    echo "(Press Ctrl+C to stop waiting - services will continue in background)"
    echo ""

    # Wait for all background processes
    for coin in "${!PIDS[@]}"; do
        wait ${PIDS[$coin]} 2>/dev/null
        EXIT_CODE=$?
        if [ ${EXIT_CODE} -eq 0 ]; then
            echo "[${coin^^}] Startup complete"
        else
            echo "[${coin^^}] Startup finished with code ${EXIT_CODE}"
        fi
    done

    echo ""
    echo "=============================================="
    echo "  All chains have completed startup"
    echo "=============================================="
fi

# Show WebUI URL if enabled
if [ "${ENABLE_WEBUI}" = "true" ]; then
    echo ""
    echo "Web Dashboard available at:"
    PUBLIC_IP=$(curl -s --connect-timeout 2 https://ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')
    [ "${WEBUI_HTTP_ENABLED}" = "true" ] && echo "  http://${PUBLIC_IP}:${WEBUI_HTTP_PORT:-8080}"
    [ "${WEBUI_HTTPS_ENABLED}" = "true" ] && echo "  https://${PUBLIC_IP}:${WEBUI_HTTPS_PORT:-8443}"
fi

echo ""
echo "Check status: ${BIN_DIR}/status.sh"
echo "View logs:    journalctl -u <service-name> -f"
