#!/bin/bash
# Start all enabled services (nodes first, then pools, then dashboard)
source /opt/solo-pool/install-scripts/config.sh

echo "Starting all services..."
echo ""
${BASE_DIR}/start-nodes.sh
echo ""
${BASE_DIR}/start-pools.sh
echo ""
echo "All services started."

# Show WebUI URL if enabled
if [ "${ENABLE_WEBUI}" = "true" ]; then
    echo ""
    echo "Web Dashboard available at:"
    PUBLIC_IP=$(curl -s --connect-timeout 2 https://ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')
    [ "${WEBUI_HTTP_ENABLED}" = "true" ] && echo "  http://${PUBLIC_IP}:${WEBUI_HTTP_PORT:-8080}"
    [ "${WEBUI_HTTPS_ENABLED}" = "true" ] && echo "  https://${PUBLIC_IP}:${WEBUI_HTTPS_PORT:-8443}"
fi
