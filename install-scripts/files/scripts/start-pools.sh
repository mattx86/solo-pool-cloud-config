#!/bin/bash
# Start all enabled pool services
source /opt/solo-pool/install-scripts/config.sh

echo "Starting pool services..."

[ "${ENABLE_BITCOIN_POOL}" = "true" ] && sudo systemctl start pool-btc-ckpool && echo "  Started pool-btc-ckpool"
[ "${ENABLE_BCH_POOL}" = "true" ] && sudo systemctl start pool-bch-ckpool && echo "  Started pool-bch-ckpool"
[ "${ENABLE_DGB_POOL}" = "true" ] && sudo systemctl start pool-dgb-ckpool && echo "  Started pool-dgb-ckpool"

if [ "${MONERO_TARI_MODE}" = "monero_only" ]; then
    sudo systemctl start pool-xmr-p2pool && echo "  Started pool-xmr-p2pool"
elif [ "${MONERO_TARI_MODE}" = "merge" ]; then
    sudo systemctl start pool-xmr-xtm-merge-proxy && echo "  Started pool-xmr-xtm-merge-proxy"
elif [ "${MONERO_TARI_MODE}" = "tari_only" ]; then
    sudo systemctl start pool-xtm-minotari-miner && echo "  Started pool-xtm-minotari-miner"
fi

[ "${ENABLE_ALEO_POOL}" = "true" ] && sudo systemctl start pool-aleo && echo "  Started pool-aleo"

# Start WebUI dashboard (if binary exists)
if [ "${ENABLE_WEBUI}" = "true" ]; then
    if [ -x "${WEBUI_DIR}/solo-pool-webui" ]; then
        sudo systemctl start solo-pool-webui && echo "  Started solo-pool-webui"
    else
        echo "  [SKIP] WebUI binary not found at ${WEBUI_DIR}/solo-pool-webui"
    fi
fi

echo "Done."
