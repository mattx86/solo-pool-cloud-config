#!/bin/bash
# =============================================================================
# restart-all.sh - Restart all enabled services
#
# This script stops all services in the correct order, then starts them again.
# Useful after configuration changes or to recover from issues.
# =============================================================================

source /opt/solo-pool/install/config.sh

if [ "${CONFIG_LOADED:-}" != "true" ]; then
    echo "ERROR: Failed to load configuration" >&2
    exit 1
fi

echo "=============================================="
echo "  Solo Pool - Restarting All Services"
echo "=============================================="
echo ""

# Stop all services first
echo "Stopping all services..."
${BIN_DIR}/stop-all.sh

echo ""
echo "Waiting for services to stop completely..."
sleep 5

echo ""
# Start all services
${BIN_DIR}/start-all.sh "$@"
