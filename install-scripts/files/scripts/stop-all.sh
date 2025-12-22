#!/bin/bash
# Stop all enabled services (pools first, then nodes)
source /opt/solo-pool/install-scripts/config.sh

echo "Stopping all services..."
echo ""
${BASE_DIR}/stop-pools.sh
echo ""
${BASE_DIR}/stop-nodes.sh
echo ""
echo "All services stopped."
