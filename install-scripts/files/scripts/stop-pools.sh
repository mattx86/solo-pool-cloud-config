#!/bin/bash
# Stop all enabled pool services
source /opt/solo-pool/install-scripts/config.sh

echo "Stopping pool services..."

# Stop WebUI dashboard first
[ "${ENABLE_WEBUI}" = "true" ] && sudo systemctl stop solo-pool-webui && echo "  Stopped solo-pool-webui"

[ "${ENABLE_ALEO_POOL}" = "true" ] && sudo systemctl stop pool-aleo && echo "  Stopped pool-aleo"

if [ "${MONERO_TARI_MODE}" = "monero_only" ]; then
    sudo systemctl stop pool-xmr-p2pool && echo "  Stopped pool-xmr-p2pool"
elif [ "${MONERO_TARI_MODE}" = "merge" ]; then
    sudo systemctl stop pool-xmr-xtm-merge-proxy && echo "  Stopped pool-xmr-xtm-merge-proxy"
elif [ "${MONERO_TARI_MODE}" = "tari_only" ]; then
    sudo systemctl stop pool-xtm-minotari-miner && echo "  Stopped pool-xtm-minotari-miner"
fi

[ "${ENABLE_DGB_POOL}" = "true" ] && sudo systemctl stop pool-dgb-ckpool && echo "  Stopped pool-dgb-ckpool"
[ "${ENABLE_BCH_POOL}" = "true" ] && sudo systemctl stop pool-bch-ckpool && echo "  Stopped pool-bch-ckpool"
[ "${ENABLE_BITCOIN_POOL}" = "true" ] && sudo systemctl stop pool-btc-ckpool && echo "  Stopped pool-btc-ckpool"

echo "Done."
