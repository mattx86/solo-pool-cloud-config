#!/bin/bash
# Check status of all services
source /opt/solo-pool/install-scripts/config.sh

echo "=== Node Services ==="
[ "${ENABLE_BITCOIN_POOL}" = "true" ] && systemctl status node-btc-bitcoind --no-pager -l | head -5
[ "${ENABLE_BCH_POOL}" = "true" ] && systemctl status node-bch-bchn --no-pager -l | head -5
[ "${ENABLE_DGB_POOL}" = "true" ] && systemctl status node-dgb-digibyted --no-pager -l | head -5
[ "${ENABLE_MONERO_POOL}" = "true" ] && systemctl status node-xmr-monerod --no-pager -l | head -5
[ "${ENABLE_TARI_POOL}" = "true" ] && [ "${MONERO_TARI_MODE}" != "monero_only" ] && systemctl status node-xtm-minotari --no-pager -l | head -5
[ "${ENABLE_ALEO_POOL}" = "true" ] && systemctl status node-aleo-snarkos --no-pager -l | head -5

echo ""
echo "=== Pool Services ==="
[ "${ENABLE_BITCOIN_POOL}" = "true" ] && systemctl status pool-btc-ckpool --no-pager -l | head -5
[ "${ENABLE_BCH_POOL}" = "true" ] && systemctl status pool-bch-ckpool --no-pager -l | head -5
[ "${ENABLE_DGB_POOL}" = "true" ] && systemctl status pool-dgb-ckpool --no-pager -l | head -5

if [ "${MONERO_TARI_MODE}" = "monero_only" ]; then
    systemctl status pool-xmr-p2pool --no-pager -l | head -5
elif [ "${MONERO_TARI_MODE}" = "merge" ]; then
    systemctl status pool-xmr-xtm-merge-proxy --no-pager -l | head -5
elif [ "${MONERO_TARI_MODE}" = "tari_only" ]; then
    systemctl status pool-xtm-minotari-miner --no-pager -l | head -5
fi

[ "${ENABLE_ALEO_POOL}" = "true" ] && systemctl status pool-aleo --no-pager -l | head -5

echo ""
echo "=== Web Dashboard ==="
[ "${ENABLE_WEBUI}" = "true" ] && systemctl status solo-pool-webui --no-pager -l | head -5
