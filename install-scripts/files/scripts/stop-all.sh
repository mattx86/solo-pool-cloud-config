#!/bin/bash
# Stop all enabled services (pools first, then nodes)
source /opt/solo-pool/install-scripts/config.sh

# Validate config was loaded
if [ "${CONFIG_LOADED:-}" != "true" ]; then
    echo "ERROR: Failed to load configuration" >&2
    exit 1
fi

echo "Stopping all services..."
echo ""
${BASE_DIR}/stop-pools.sh
echo ""
${BASE_DIR}/stop-nodes.sh
echo ""
echo "All services stopped."
