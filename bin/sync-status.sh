#!/bin/bash
# Check blockchain sync status
source /opt/solo-pool/install/config.sh

# Validate config was loaded
if [ "${CONFIG_LOADED:-}" != "true" ]; then
    echo "ERROR: Failed to load configuration" >&2
    exit 1
fi

echo "=== Blockchain Sync Status ==="
echo ""

if [ "${ENABLE_BITCOIN_POOL}" = "true" ]; then
    echo "Bitcoin:"
    ${BITCOIN_DIR}/bin/bitcoin-cli -conf=${BITCOIN_DIR}/config/bitcoin.conf getblockchaininfo 2>/dev/null | jq -r '"  Blocks: \(.blocks), Headers: \(.headers), Progress: \(.verificationprogress * 100 | floor)%"' || echo "  Not running or syncing"
fi

if [ "${ENABLE_BCH_POOL}" = "true" ]; then
    echo "Bitcoin Cash:"
    ${BCHN_DIR}/bin/bitcoin-cli -conf=${BCHN_DIR}/config/bitcoin.conf getblockchaininfo 2>/dev/null | jq -r '"  Blocks: \(.blocks), Headers: \(.headers), Progress: \(.verificationprogress * 100 | floor)%"' || echo "  Not running or syncing"
fi

if [ "${ENABLE_DGB_POOL}" = "true" ]; then
    echo "DigiByte:"
    ${DIGIBYTE_DIR}/bin/digibyte-cli -conf=${DIGIBYTE_DIR}/config/digibyte.conf getblockchaininfo 2>/dev/null | jq -r '"  Blocks: \(.blocks), Headers: \(.headers), Progress: \(.verificationprogress * 100 | floor)%"' || echo "  Not running or syncing"
fi

case "${ENABLE_MONERO_TARI_POOL}" in
    merge|merged|monero_only)
        echo "Monero:"
        curl -s http://127.0.0.1:${MONERO_RPC_PORT}/json_rpc -d '{"jsonrpc":"2.0","id":"0","method":"get_info"}' -H 'Content-Type: application/json' 2>/dev/null | jq -r '"  Height: \(.result.height), Target: \(.result.target_height), Sync: \(if .result.synchronized then "Yes" else "No" end)"' || echo "  Not running or syncing"
        ;;
esac

case "${ENABLE_MONERO_TARI_POOL}" in
    merge|merged|tari_only)
        echo "Tari:"
        # Tari uses gRPC, check via node status
        curl -s http://127.0.0.1:${TARI_NODE_GRPC_PORT}/status 2>/dev/null | jq -r '"  Height: \(.height), Sync: \(.sync_status)"' || echo "  Not running or syncing"
        ;;
esac

if [ "${ENABLE_ALEO_POOL}" = "true" ]; then
    echo "Aleo:"
    curl -s http://127.0.0.1:${ALEO_REST_PORT}/testnet/latest/height 2>/dev/null && echo " (latest height)" || echo "  Not running or syncing"
fi

echo ""
