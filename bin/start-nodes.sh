#!/bin/bash
# Start all enabled node and wallet services
source /opt/solopool/install/config.sh

# Validate config was loaded
if [ "${CONFIG_LOADED:-}" != "true" ]; then
    echo "ERROR: Failed to load configuration" >&2
    exit 1
fi

echo "Starting node services..."

[ "${ENABLE_BITCOIN_POOL}" = "true" ] && sudo systemctl start node-btc-bitcoind && echo "  Started node-btc-bitcoind"
[ "${ENABLE_BCH_POOL}" = "true" ] && sudo systemctl start node-bch-bchn && echo "  Started node-bch-bchn"
[ "${ENABLE_DGB_POOL}" = "true" ] && sudo systemctl start node-dgb-digibyted && echo "  Started node-dgb-digibyted"
case "${ENABLE_MONERO_TARI_POOL}" in
    merge|merged|monero_only) sudo systemctl start node-xmr-monerod && echo "  Started node-xmr-monerod" ;;
esac
case "${ENABLE_MONERO_TARI_POOL}" in
    merge|merged|tari_only) sudo systemctl start node-xtm-minotari && echo "  Started node-xtm-minotari" ;;
esac
[ "${ENABLE_ALEO_POOL}" = "true" ] && sudo systemctl start node-aleo-snarkos && echo "  Started node-aleo-snarkos"

echo ""
echo "Starting wallet services (for payment processing)..."

case "${ENABLE_MONERO_TARI_POOL}" in
    merge|merged|monero_only) sudo systemctl start wallet-xmr-rpc && echo "  Started wallet-xmr-rpc" ;;
esac
case "${ENABLE_MONERO_TARI_POOL}" in
    merge|merged|tari_only) sudo systemctl start wallet-xtm && echo "  Started wallet-xtm" ;;
esac

echo ""
echo "Done. Wait for nodes to sync before starting pools."
