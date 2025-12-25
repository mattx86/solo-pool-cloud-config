#!/bin/bash
# Check status of all services
source /opt/solo-pool/install/config.sh

# Validate config was loaded
if [ "${CONFIG_LOADED:-}" != "true" ]; then
    echo "ERROR: Failed to load configuration" >&2
    exit 1
fi

echo "=== Node Services ==="
[ "${ENABLE_BITCOIN_POOL}" = "true" ] && systemctl status node-btc-bitcoind --no-pager -l | head -5
[ "${ENABLE_BCH_POOL}" = "true" ] && systemctl status node-bch-bchn --no-pager -l | head -5
[ "${ENABLE_DGB_POOL}" = "true" ] && systemctl status node-dgb-digibyted --no-pager -l | head -5
case "${ENABLE_MONERO_TARI_POOL}" in
    merge|merged|monero_only) systemctl status node-xmr-monerod --no-pager -l | head -5 ;;
esac
case "${ENABLE_MONERO_TARI_POOL}" in
    merge|merged|tari_only) systemctl status node-xtm-minotari --no-pager -l | head -5 ;;
esac
[ "${ENABLE_ALEO_POOL}" = "true" ] && systemctl status node-aleo-snarkos --no-pager -l | head -5

echo ""
echo "=== Wallet Services ==="
case "${ENABLE_MONERO_TARI_POOL}" in
    merge|merged|monero_only) systemctl status wallet-xmr-rpc --no-pager -l | head -5 ;;
esac
case "${ENABLE_MONERO_TARI_POOL}" in
    merge|merged|tari_only) systemctl status wallet-xtm --no-pager -l | head -5 ;;
esac

echo ""
echo "=== Pool Services ==="
[ "${ENABLE_BITCOIN_POOL}" = "true" ] && systemctl status pool-btc-ckpool --no-pager -l | head -5
[ "${ENABLE_BCH_POOL}" = "true" ] && systemctl status pool-bch-ckpool --no-pager -l | head -5
[ "${ENABLE_DGB_POOL}" = "true" ] && systemctl status pool-dgb-ckpool --no-pager -l | head -5

case "${ENABLE_MONERO_TARI_POOL}" in
    monero_only)
        systemctl status pool-xmr-monero-pool --no-pager -l | head -5
        ;;
    merge|merged)
        systemctl status pool-xmr-xtm-merge-proxy --no-pager -l | head -5
        ;;
    tari_only)
        systemctl status pool-xtm-minotari-miner --no-pager -l | head -5
        ;;
esac

[ "${ENABLE_ALEO_POOL}" = "true" ] && systemctl status pool-aleo --no-pager -l | head -5

echo ""
echo "=== Web Dashboard ==="
[ "${ENABLE_WEBUI}" = "true" ] && systemctl status solo-pool-webui --no-pager -l | head -5

echo ""
echo "=== Payment Processor ==="
NEED_PAYMENTS="false"
case "${ENABLE_MONERO_TARI_POOL}" in
    merge|merged|monero_only|tari_only) NEED_PAYMENTS="true" ;;
esac
[ "${ENABLE_ALEO_POOL}" = "true" ] && NEED_PAYMENTS="true"
[ "${NEED_PAYMENTS}" = "true" ] && systemctl status solo-pool-payments --no-pager -l | head -5
