#!/bin/bash
# Check blockchain sync status
source /opt/solo-pool/install-scripts/config.sh

echo "=== Blockchain Sync Status ==="
echo ""

if [ "${ENABLE_BITCOIN_POOL}" = "true" ]; then
    echo "Bitcoin:"
    ${BITCOIN_DIR}/bin/bitcoin-cli -conf=${BITCOIN_DIR}/bitcoin.conf getblockchaininfo 2>/dev/null | jq -r '"  Blocks: \(.blocks), Headers: \(.headers), Progress: \(.verificationprogress * 100 | floor)%"' || echo "  Not running or syncing"
fi

if [ "${ENABLE_BCH_POOL}" = "true" ]; then
    echo "Bitcoin Cash:"
    ${BCHN_DIR}/bin/bitcoin-cli -conf=${BCHN_DIR}/bitcoin.conf getblockchaininfo 2>/dev/null | jq -r '"  Blocks: \(.blocks), Headers: \(.headers), Progress: \(.verificationprogress * 100 | floor)%"' || echo "  Not running or syncing"
fi

if [ "${ENABLE_DGB_POOL}" = "true" ]; then
    echo "DigiByte:"
    ${DIGIBYTE_DIR}/bin/digibyte-cli -conf=${DIGIBYTE_DIR}/digibyte.conf getblockchaininfo 2>/dev/null | jq -r '"  Blocks: \(.blocks), Headers: \(.headers), Progress: \(.verificationprogress * 100 | floor)%"' || echo "  Not running or syncing"
fi

if [ "${ENABLE_MONERO_POOL}" = "true" ]; then
    echo "Monero:"
    curl -s http://127.0.0.1:18081/json_rpc -d '{"jsonrpc":"2.0","id":"0","method":"get_info"}' -H 'Content-Type: application/json' 2>/dev/null | jq -r '"  Height: \(.result.height), Target: \(.result.target_height), Sync: \(if .result.synchronized then "Yes" else "No" end)"' || echo "  Not running or syncing"
fi

echo ""
