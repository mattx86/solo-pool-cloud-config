#!/bin/bash
# =============================================================================
# 99-finalize.sh
# Final setup and verification
# =============================================================================

set -e

# Source configuration
source /opt/solo-pool/config.sh

log "Finalizing installation..."

# =============================================================================
# 1. VERIFY INSTALLATIONS
# =============================================================================
log "1. Verifying installations..."

verify_binary() {
    local name="$1"
    local path="$2"
    if [ -x "$path" ]; then
        log "  [OK] $name"
        return 0
    else
        log "  [MISSING] $name: $path"
        return 1
    fi
}

ERRORS=0

if [ "${ENABLE_BITCOIN_POOL}" = "true" ]; then
    verify_binary "bitcoind" "${BITCOIN_DIR}/bin/bitcoind" || ((ERRORS++))
    verify_binary "ckpool-btc" "${CKPOOL_BTC_DIR}/bin/ckpool" || ((ERRORS++))
fi

if [ "${ENABLE_BCH_POOL}" = "true" ]; then
    verify_binary "bchn" "${BCHN_DIR}/bin/bitcoind" || ((ERRORS++))
    verify_binary "ckpool-bch" "${CKPOOL_BCH_DIR}/bin/ckpool" || ((ERRORS++))
fi

if [ "${ENABLE_DGB_POOL}" = "true" ]; then
    verify_binary "digibyted" "${DIGIBYTE_DIR}/bin/digibyted" || ((ERRORS++))
    verify_binary "ckpool-dgb" "${CKPOOL_DGB_DIR}/bin/ckpool" || ((ERRORS++))
fi

if [ "${ENABLE_MONERO_POOL}" = "true" ]; then
    verify_binary "monerod" "${MONERO_DIR}/bin/monerod" || ((ERRORS++))
    if [ "${MONERO_TARI_MODE}" = "monero_only" ]; then
        verify_binary "monero-stratum" "${MONERO_STRATUM_DIR}/bin/monero-stratum" || ((ERRORS++))
    fi
fi

if [ "${ENABLE_TARI_POOL}" = "true" ] && [ "${MONERO_TARI_MODE}" != "monero_only" ]; then
    verify_binary "minotari_node" "${TARI_DIR}/bin/minotari_node" || ((ERRORS++))
    if [ "${MONERO_TARI_MODE}" = "merge" ]; then
        verify_binary "minotari_merge_mining_proxy" "${TARI_DIR}/bin/minotari_merge_mining_proxy" || ((ERRORS++))
    else
        verify_binary "minotari_miner" "${TARI_DIR}/bin/minotari_miner" || ((ERRORS++))
    fi
fi

if [ "${ENABLE_ALEO_POOL}" = "true" ]; then
    verify_binary "snarkos" "${ALEO_DIR}/bin/snarkos" || ((ERRORS++))
fi

# =============================================================================
# 2. CREATE CONVENIENCE SCRIPTS
# =============================================================================
log "2. Creating convenience scripts..."

# Create start-all script
cat > /opt/solo-pool/start-nodes.sh << 'EOF'
#!/bin/bash
# Start all enabled node services
source /opt/solo-pool/config.sh

echo "Starting node services..."

[ "${ENABLE_BITCOIN_POOL}" = "true" ] && sudo systemctl start bitcoind && echo "  Started bitcoind"
[ "${ENABLE_BCH_POOL}" = "true" ] && sudo systemctl start bchn && echo "  Started bchn"
[ "${ENABLE_DGB_POOL}" = "true" ] && sudo systemctl start digibyted && echo "  Started digibyted"
[ "${ENABLE_MONERO_POOL}" = "true" ] && sudo systemctl start monerod && echo "  Started monerod"
[ "${ENABLE_TARI_POOL}" = "true" ] && [ "${MONERO_TARI_MODE}" != "monero_only" ] && sudo systemctl start minotari-node && echo "  Started minotari-node"
[ "${ENABLE_ALEO_POOL}" = "true" ] && sudo systemctl start snarkos && echo "  Started snarkos"

echo "Done. Wait for nodes to sync before starting pools."
EOF
chmod +x /opt/solo-pool/start-nodes.sh

# Create start-pools script
cat > /opt/solo-pool/start-pools.sh << 'EOF'
#!/bin/bash
# Start all enabled pool services
source /opt/solo-pool/config.sh

echo "Starting pool services..."

[ "${ENABLE_BITCOIN_POOL}" = "true" ] && sudo systemctl start ckpool-btc && echo "  Started ckpool-btc"
[ "${ENABLE_BCH_POOL}" = "true" ] && sudo systemctl start ckpool-bch && echo "  Started ckpool-bch"
[ "${ENABLE_DGB_POOL}" = "true" ] && sudo systemctl start ckpool-dgb && echo "  Started ckpool-dgb"

if [ "${MONERO_TARI_MODE}" = "monero_only" ]; then
    sudo systemctl start monero-stratum && echo "  Started monero-stratum"
elif [ "${MONERO_TARI_MODE}" = "merge" ]; then
    sudo systemctl start minotari-merge-proxy && echo "  Started minotari-merge-proxy"
elif [ "${MONERO_TARI_MODE}" = "tari_only" ]; then
    sudo systemctl start minotari-miner && echo "  Started minotari-miner"
fi

echo "Done."
EOF
chmod +x /opt/solo-pool/start-pools.sh

# Create status script
cat > /opt/solo-pool/status.sh << 'EOF'
#!/bin/bash
# Check status of all services
source /opt/solo-pool/config.sh

echo "=== Node Services ==="
[ "${ENABLE_BITCOIN_POOL}" = "true" ] && systemctl status bitcoind --no-pager -l | head -5
[ "${ENABLE_BCH_POOL}" = "true" ] && systemctl status bchn --no-pager -l | head -5
[ "${ENABLE_DGB_POOL}" = "true" ] && systemctl status digibyted --no-pager -l | head -5
[ "${ENABLE_MONERO_POOL}" = "true" ] && systemctl status monerod --no-pager -l | head -5
[ "${ENABLE_TARI_POOL}" = "true" ] && [ "${MONERO_TARI_MODE}" != "monero_only" ] && systemctl status minotari-node --no-pager -l | head -5
[ "${ENABLE_ALEO_POOL}" = "true" ] && systemctl status snarkos --no-pager -l | head -5

echo ""
echo "=== Pool Services ==="
[ "${ENABLE_BITCOIN_POOL}" = "true" ] && systemctl status ckpool-btc --no-pager -l | head -5
[ "${ENABLE_BCH_POOL}" = "true" ] && systemctl status ckpool-bch --no-pager -l | head -5
[ "${ENABLE_DGB_POOL}" = "true" ] && systemctl status ckpool-dgb --no-pager -l | head -5

if [ "${MONERO_TARI_MODE}" = "monero_only" ]; then
    systemctl status monero-stratum --no-pager -l | head -5
elif [ "${MONERO_TARI_MODE}" = "merge" ]; then
    systemctl status minotari-merge-proxy --no-pager -l | head -5
elif [ "${MONERO_TARI_MODE}" = "tari_only" ]; then
    systemctl status minotari-miner --no-pager -l | head -5
fi
EOF
chmod +x /opt/solo-pool/status.sh

# Create sync-status script
cat > /opt/solo-pool/sync-status.sh << 'EOF'
#!/bin/bash
# Check blockchain sync status
source /opt/solo-pool/config.sh

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
EOF
chmod +x /opt/solo-pool/sync-status.sh

# Set ownership
chown -R ${POOL_USER}:${POOL_USER} /opt/solo-pool/*.sh

# =============================================================================
# 3. CREATE MOTD
# =============================================================================
log "3. Creating login message..."

cat > /etc/update-motd.d/99-solo-pool << 'EOF'
#!/bin/bash
echo ""
echo "=========================================="
echo "     Solo Mining Pool Server"
echo "=========================================="
echo ""
echo "Quick Commands:"
echo "  /opt/solo-pool/start-nodes.sh  - Start all nodes"
echo "  /opt/solo-pool/start-pools.sh  - Start all pools"
echo "  /opt/solo-pool/status.sh       - Check service status"
echo "  /opt/solo-pool/sync-status.sh  - Check blockchain sync"
echo ""
echo "Configuration: /opt/solo-pool/config.sh"
echo "Nodes:         /opt/node/"
echo "Pools:         /opt/pool/"
echo ""
EOF
chmod +x /etc/update-motd.d/99-solo-pool

# =============================================================================
# 4. SUMMARY
# =============================================================================
log ""
log "=============================================="
log "           INSTALLATION SUMMARY"
log "=============================================="
log ""
log "Configuration: /opt/solo-pool/config.sh"
log ""
log "Enabled Pools:"
[ "${ENABLE_BITCOIN_POOL}" = "true" ] && log "  - Bitcoin (BTC) on port ${BTC_STRATUM_PORT}"
[ "${ENABLE_BCH_POOL}" = "true" ] && log "  - Bitcoin Cash (BCH) on port ${BCH_STRATUM_PORT}"
[ "${ENABLE_DGB_POOL}" = "true" ] && log "  - DigiByte (DGB) on port ${DGB_STRATUM_PORT}"
if [ "${ENABLE_MONERO_POOL}" = "true" ] || [ "${ENABLE_TARI_POOL}" = "true" ]; then
    if [ "${MONERO_TARI_MODE}" = "merge" ]; then
        log "  - Monero + Tari (merge mining) on port ${MERGE_STRATUM_PORT}"
    elif [ "${MONERO_TARI_MODE}" = "monero_only" ]; then
        log "  - Monero (XMR) on port ${XMR_STRATUM_PORT}"
    elif [ "${MONERO_TARI_MODE}" = "tari_only" ]; then
        log "  - Tari (XTM) on port ${XTM_STRATUM_PORT}"
    fi
fi
[ "${ENABLE_ALEO_POOL}" = "true" ] && log "  - ALEO (requires private key configuration)"
log ""
log "Installation Errors: ${ERRORS}"
log ""
log "NEXT STEPS:"
log "1. Start nodes: /opt/solo-pool/start-nodes.sh"
log "2. Wait for sync: /opt/solo-pool/sync-status.sh"
log "3. Open firewall ports when ready"
log "4. Start pools: /opt/solo-pool/start-pools.sh"
log ""
if [ "${ENABLE_ALEO_POOL}" = "true" ]; then
    log "ALEO IMPORTANT:"
    log "  Edit /etc/systemd/system/snarkos.service"
    log "  Add your private key to start proving"
    log ""
fi
log "=============================================="

log_success "Installation complete!"
