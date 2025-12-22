#!/bin/bash
# Start all enabled node services
source /opt/solo-pool/install-scripts/config.sh

echo "Starting node services..."

[ "${ENABLE_BITCOIN_POOL}" = "true" ] && sudo systemctl start node-btc-bitcoind && echo "  Started node-btc-bitcoind"
[ "${ENABLE_BCH_POOL}" = "true" ] && sudo systemctl start node-bch-bchn && echo "  Started node-bch-bchn"
[ "${ENABLE_DGB_POOL}" = "true" ] && sudo systemctl start node-dgb-digibyted && echo "  Started node-dgb-digibyted"
[ "${ENABLE_MONERO_POOL}" = "true" ] && sudo systemctl start node-xmr-monerod && echo "  Started node-xmr-monerod"
[ "${ENABLE_TARI_POOL}" = "true" ] && [ "${MONERO_TARI_MODE}" != "monero_only" ] && sudo systemctl start node-xtm-minotari && echo "  Started node-xtm-minotari"
[ "${ENABLE_ALEO_POOL}" = "true" ] && sudo systemctl start node-aleo-snarkos && echo "  Started node-aleo-snarkos"

echo "Done. Wait for nodes to sync before starting pools."
