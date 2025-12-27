#!/bin/bash
# Stop all enabled wallet and node services
source /opt/solopool/install/config.sh

# Validate config was loaded
if [ "${CONFIG_LOADED:-}" != "true" ]; then
    echo "ERROR: Failed to load configuration" >&2
    exit 1
fi

echo "Stopping wallet services..."

case "${ENABLE_MONERO_TARI_POOL}" in
    merge|merged|tari_only) sudo systemctl stop wallet-xtm && echo "  Stopped wallet-xtm" ;;
esac
case "${ENABLE_MONERO_TARI_POOL}" in
    merge|merged|monero_only) sudo systemctl stop wallet-xmr-rpc && echo "  Stopped wallet-xmr-rpc" ;;
esac

echo ""
echo "Stopping node services..."

[ "${ENABLE_ALEO_POOL}" = "true" ] && sudo systemctl stop node-aleo-snarkos && echo "  Stopped node-aleo-snarkos"
case "${ENABLE_MONERO_TARI_POOL}" in
    merge|merged|tari_only) sudo systemctl stop node-xtm-minotari && echo "  Stopped node-xtm-minotari" ;;
esac
case "${ENABLE_MONERO_TARI_POOL}" in
    merge|merged|monero_only) sudo systemctl stop node-xmr-monerod && echo "  Stopped node-xmr-monerod" ;;
esac
[ "${ENABLE_DGB_POOL}" = "true" ] && sudo systemctl stop node-dgb-digibyted && echo "  Stopped node-dgb-digibyted"
[ "${ENABLE_BCH_POOL}" = "true" ] && sudo systemctl stop node-bch-bchn && echo "  Stopped node-bch-bchn"
[ "${ENABLE_BITCOIN_POOL}" = "true" ] && sudo systemctl stop node-btc-bitcoind && echo "  Stopped node-btc-bitcoind"

echo ""
echo "Done."
