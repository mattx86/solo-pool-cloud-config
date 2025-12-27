#!/bin/bash
# Stop all enabled pool services
source /opt/solopool/install/config.sh

# Validate config was loaded
if [ "${CONFIG_LOADED:-}" != "true" ]; then
    echo "ERROR: Failed to load configuration" >&2
    exit 1
fi

echo "Stopping pool services..."

# Stop Payment Processor first (depends on pools)
PAYMENTS_DIR="${BASE_DIR}/payments"
NEED_PAYMENTS="false"
case "${ENABLE_MONERO_TARI_POOL}" in
    merge|merged|monero_only|tari_only) NEED_PAYMENTS="true" ;;
esac
[ "${ENABLE_ALEO_POOL}" = "true" ] && NEED_PAYMENTS="true"

if [ "${NEED_PAYMENTS}" = "true" ]; then
    sudo systemctl stop solopool-payments 2>/dev/null && echo "  Stopped solopool-payments"
fi

# Stop WebUI dashboard
[ "${ENABLE_WEBUI}" = "true" ] && sudo systemctl stop solopool-webui && echo "  Stopped solopool-webui"

[ "${ENABLE_ALEO_POOL}" = "true" ] && sudo systemctl stop pool-aleo && echo "  Stopped pool-aleo"

case "${ENABLE_MONERO_TARI_POOL}" in
    monero_only)
        sudo systemctl stop pool-xmr-monero-pool && echo "  Stopped pool-xmr-monero-pool"
        ;;
    merge|merged)
        sudo systemctl stop pool-xmr-xtm-merge-proxy && echo "  Stopped pool-xmr-xtm-merge-proxy"
        ;;
    tari_only)
        sudo systemctl stop pool-xtm-minotari-miner && echo "  Stopped pool-xtm-minotari-miner"
        ;;
esac

[ "${ENABLE_DGB_POOL}" = "true" ] && sudo systemctl stop pool-dgb-ckpool && echo "  Stopped pool-dgb-ckpool"
[ "${ENABLE_BCH_POOL}" = "true" ] && sudo systemctl stop pool-bch-ckpool && echo "  Stopped pool-bch-ckpool"
[ "${ENABLE_BITCOIN_POOL}" = "true" ] && sudo systemctl stop pool-btc-ckpool && echo "  Stopped pool-btc-ckpool"

echo "Done."
