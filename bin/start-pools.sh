#!/bin/bash
# Start all enabled pool services
source /opt/solo-pool/install/config.sh

# Validate config was loaded
if [ "${CONFIG_LOADED:-}" != "true" ]; then
    echo "ERROR: Failed to load configuration" >&2
    exit 1
fi

echo "Starting pool services..."

[ "${ENABLE_BITCOIN_POOL}" = "true" ] && sudo systemctl start pool-btc-ckpool && echo "  Started pool-btc-ckpool"
[ "${ENABLE_BCH_POOL}" = "true" ] && sudo systemctl start pool-bch-ckpool && echo "  Started pool-bch-ckpool"
[ "${ENABLE_DGB_POOL}" = "true" ] && sudo systemctl start pool-dgb-ckpool && echo "  Started pool-dgb-ckpool"

case "${ENABLE_MONERO_TARI_POOL}" in
    monero_only)
        sudo systemctl start pool-xmr-monero-pool && echo "  Started pool-xmr-monero-pool"
        ;;
    merge|merged)
        sudo systemctl start pool-xmr-xtm-merge-proxy && echo "  Started pool-xmr-xtm-merge-proxy"
        ;;
    tari_only)
        sudo systemctl start pool-xtm-minotari-miner && echo "  Started pool-xtm-minotari-miner"
        ;;
esac

[ "${ENABLE_ALEO_POOL}" = "true" ] && sudo systemctl start pool-aleo && echo "  Started pool-aleo"

# Start WebUI dashboard (if binary exists)
if [ "${ENABLE_WEBUI}" = "true" ]; then
    if [ -x "${WEBUI_DIR}/bin/solo-pool-webui" ]; then
        sudo systemctl start solo-pool-webui && echo "  Started solo-pool-webui"
    else
        echo "  [SKIP] WebUI binary not found at ${WEBUI_DIR}/bin/solo-pool-webui"
    fi
fi

# Start Payment Processor (if binary exists and needed)
PAYMENTS_DIR="${BASE_DIR}/payments"
NEED_PAYMENTS="false"
case "${ENABLE_MONERO_TARI_POOL}" in
    merge|merged|monero_only|tari_only) NEED_PAYMENTS="true" ;;
esac
[ "${ENABLE_ALEO_POOL}" = "true" ] && NEED_PAYMENTS="true"

if [ "${NEED_PAYMENTS}" = "true" ]; then
    if [ -x "${PAYMENTS_DIR}/bin/solo-pool-payments" ]; then
        sudo systemctl start solo-pool-payments && echo "  Started solo-pool-payments"
    else
        echo "  [SKIP] Payment processor binary not found at ${PAYMENTS_DIR}/bin/solo-pool-payments"
    fi
fi

echo "Done."
