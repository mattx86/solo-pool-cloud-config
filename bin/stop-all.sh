#!/bin/bash
# =============================================================================
# stop-all.sh - Stop all services in reverse order
#
# Stop order (reverse of start):
#   1. Pools (stop accepting miners)
#   2. Nodes (stop blockchain services)
#   3. Payments (stop payment processor)
#   4. WebUI (stop dashboard last)
# =============================================================================

source /opt/solo-pool/install/config.sh

if [ "${CONFIG_LOADED:-}" != "true" ]; then
    echo "ERROR: Failed to load configuration" >&2
    exit 1
fi

echo "=============================================="
echo "  Solo Pool - Stopping All Services"
echo "=============================================="
echo ""

# 1. Stop pools first (stop accepting miners)
echo "[1/4] Stopping pool services..."
${BIN_DIR}/stop-pools.sh
echo ""

# 2. Stop nodes
echo "[2/4] Stopping node services..."
${BIN_DIR}/stop-nodes.sh
echo ""

# 3. Stop payments processor
echo "[3/4] Stopping payment processor..."
sudo systemctl stop solo-pool-payments 2>/dev/null && echo "  Stopped solo-pool-payments" || true
echo ""

# 4. Stop WebUI last (keep dashboard visible during shutdown)
echo "[4/4] Stopping WebUI..."
if [ "${ENABLE_WEBUI}" = "true" ]; then
    sudo systemctl stop solo-pool-webui 2>/dev/null && echo "  Stopped solo-pool-webui" || true
fi
echo ""

echo "=============================================="
echo "  All services stopped"
echo "=============================================="
