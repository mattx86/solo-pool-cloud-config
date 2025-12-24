#!/bin/bash
# Stop all enabled pool services
source /opt/solo-pool/install/config.sh

# Validate config was loaded
if [ "${CONFIG_LOADED:-}" != "true" ]; then
    echo "ERROR: Failed to load configuration" >&2
    exit 1
fi

echo "Stopping pool services..."

# Stop Payment Processor first (depends on pools)
PAYMENTS_DIR="${BASE_DIR}/payments"
NEED_PAYMENTS="false"
[ "${ENABLE_MONERO_POOL}" = "true" ] && NEED_PAYMENTS="true"
[ "${ENABLE_TARI_POOL}" = "true" ] && NEED_PAYMENTS="true"
[ "${ENABLE_ALEO_POOL}" = "true" ] && NEED_PAYMENTS="true"

if [ "${NEED_PAYMENTS}" = "true" ]; then
    sudo systemctl stop solo-pool-payments 2>/dev/null && echo "  Stopped solo-pool-payments"
fi

# Stop WebUI dashboard
[ "${ENABLE_WEBUI}" = "true" ] && sudo systemctl stop solo-pool-webui && echo "  Stopped solo-pool-webui"

[ "${ENABLE_ALEO_POOL}" = "true" ] && sudo systemctl stop pool-aleo && echo "  Stopped pool-aleo"

if [ "${MONERO_TARI_MODE}" = "monero_only" ]; then
    sudo systemctl stop pool-xmr-monero-pool && echo "  Stopped pool-xmr-monero-pool"
elif [ "${MONERO_TARI_MODE}" = "merge" ]; then
    sudo systemctl stop pool-xmr-xtm-merge-proxy && echo "  Stopped pool-xmr-xtm-merge-proxy"
elif [ "${MONERO_TARI_MODE}" = "tari_only" ]; then
    sudo systemctl stop pool-xtm-minotari-miner && echo "  Stopped pool-xtm-minotari-miner"
fi

[ "${ENABLE_DGB_POOL}" = "true" ] && sudo systemctl stop pool-dgb-ckpool && echo "  Stopped pool-dgb-ckpool"
[ "${ENABLE_BCH_POOL}" = "true" ] && sudo systemctl stop pool-bch-ckpool && echo "  Stopped pool-bch-ckpool"
[ "${ENABLE_BITCOIN_POOL}" = "true" ] && sudo systemctl stop pool-btc-ckpool && echo "  Stopped pool-btc-ckpool"

echo "Done."
