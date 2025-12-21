#!/bin/bash
# =============================================================================
# 20-configure-services.sh
# Configure systemd services for all nodes and pools
# =============================================================================

set -e

# Source configuration
source /opt/solo-pool/config.sh

log "Configuring systemd services..."

# =============================================================================
# BITCOIN SERVICES
# =============================================================================
if [ "${ENABLE_BITCOIN_POOL}" = "true" ]; then
    log "Creating Bitcoin services..."

    # bitcoind service
    cat > /etc/systemd/system/bitcoind.service << EOF
[Unit]
Description=Bitcoin Core Daemon
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=${POOL_USER}
Group=${POOL_USER}

ExecStart=${BITCOIN_DIR}/bin/bitcoind -conf=${BITCOIN_DIR}/bitcoin.conf -datadir=${BITCOIN_DIR}/data
ExecStop=${BITCOIN_DIR}/bin/bitcoin-cli -conf=${BITCOIN_DIR}/bitcoin.conf stop

Restart=on-failure
RestartSec=30
TimeoutStartSec=infinity
TimeoutStopSec=600

# Hardening
NoNewPrivileges=true
PrivateTmp=true
MemoryDenyWriteExecute=true

[Install]
WantedBy=multi-user.target
EOF

    # CKPool BTC service
    cat > /etc/systemd/system/ckpool-btc.service << EOF
[Unit]
Description=CKPool Bitcoin Stratum Server
After=bitcoind.service
Requires=bitcoind.service

[Service]
Type=simple
User=${POOL_USER}
Group=${POOL_USER}

WorkingDirectory=${CKPOOL_BTC_DIR}
ExecStart=${CKPOOL_BTC_DIR}/bin/ckpool -c ${CKPOOL_BTC_DIR}/ckpool.conf -l ${CKPOOL_BTC_DIR}/logs

Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

    log "  Bitcoin services created"
fi

# =============================================================================
# BITCOIN CASH SERVICES
# =============================================================================
if [ "${ENABLE_BCH_POOL}" = "true" ]; then
    log "Creating Bitcoin Cash services..."

    # BCHN service
    cat > /etc/systemd/system/bchn.service << EOF
[Unit]
Description=Bitcoin Cash Node Daemon
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=${POOL_USER}
Group=${POOL_USER}

ExecStart=${BCHN_DIR}/bin/bitcoind -conf=${BCHN_DIR}/bitcoin.conf -datadir=${BCHN_DIR}/data
ExecStop=${BCHN_DIR}/bin/bitcoin-cli -conf=${BCHN_DIR}/bitcoin.conf stop

Restart=on-failure
RestartSec=30
TimeoutStartSec=infinity
TimeoutStopSec=600

NoNewPrivileges=true
PrivateTmp=true
MemoryDenyWriteExecute=true

[Install]
WantedBy=multi-user.target
EOF

    # CKPool BCH service
    cat > /etc/systemd/system/ckpool-bch.service << EOF
[Unit]
Description=CKPool Bitcoin Cash Stratum Server
After=bchn.service
Requires=bchn.service

[Service]
Type=simple
User=${POOL_USER}
Group=${POOL_USER}

WorkingDirectory=${CKPOOL_BCH_DIR}
ExecStart=${CKPOOL_BCH_DIR}/bin/ckpool -c ${CKPOOL_BCH_DIR}/ckpool.conf -l ${CKPOOL_BCH_DIR}/logs

Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

    log "  Bitcoin Cash services created"
fi

# =============================================================================
# DIGIBYTE SERVICES
# =============================================================================
if [ "${ENABLE_DGB_POOL}" = "true" ]; then
    log "Creating DigiByte services..."

    # digibyted service
    cat > /etc/systemd/system/digibyted.service << EOF
[Unit]
Description=DigiByte Core Daemon
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=${POOL_USER}
Group=${POOL_USER}

ExecStart=${DIGIBYTE_DIR}/bin/digibyted -conf=${DIGIBYTE_DIR}/digibyte.conf -datadir=${DIGIBYTE_DIR}/data
ExecStop=${DIGIBYTE_DIR}/bin/digibyte-cli -conf=${DIGIBYTE_DIR}/digibyte.conf stop

Restart=on-failure
RestartSec=30
TimeoutStartSec=infinity
TimeoutStopSec=600

NoNewPrivileges=true
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF

    # CKPool DGB service
    cat > /etc/systemd/system/ckpool-dgb.service << EOF
[Unit]
Description=CKPool DigiByte Stratum Server
After=digibyted.service
Requires=digibyted.service

[Service]
Type=simple
User=${POOL_USER}
Group=${POOL_USER}

WorkingDirectory=${CKPOOL_DGB_DIR}
ExecStart=${CKPOOL_DGB_DIR}/bin/ckpool -c ${CKPOOL_DGB_DIR}/ckpool.conf -l ${CKPOOL_DGB_DIR}/logs

Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

    log "  DigiByte services created"
fi

# =============================================================================
# MONERO SERVICES
# =============================================================================
if [ "${ENABLE_MONERO_POOL}" = "true" ]; then
    log "Creating Monero services..."

    # monerod service
    cat > /etc/systemd/system/monerod.service << EOF
[Unit]
Description=Monero Daemon
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=${POOL_USER}
Group=${POOL_USER}

ExecStart=${MONERO_DIR}/bin/monerod --config-file=${MONERO_DIR}/monerod.conf --non-interactive
ExecStop=/bin/kill -SIGTERM \$MAINPID

Restart=on-failure
RestartSec=30
TimeoutStartSec=infinity
TimeoutStopSec=120

NoNewPrivileges=true
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF

    # monero-stratum service (only for monero_only mode)
    if [ "${MONERO_TARI_MODE}" = "monero_only" ]; then
        cat > /etc/systemd/system/monero-stratum.service << EOF
[Unit]
Description=Monero Stratum Server
After=monerod.service
Requires=monerod.service

[Service]
Type=simple
User=${POOL_USER}
Group=${POOL_USER}

WorkingDirectory=${MONERO_STRATUM_DIR}
ExecStart=${MONERO_STRATUM_DIR}/bin/monero-stratum ${MONERO_STRATUM_DIR}/config.json

Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
        log "  Monero stratum service created"
    fi

    log "  Monero services created"
fi

# =============================================================================
# TARI SERVICES
# =============================================================================
if [ "${ENABLE_TARI_POOL}" = "true" ] && [ "${MONERO_TARI_MODE}" != "monero_only" ]; then
    log "Creating Tari services..."

    # minotari_node service
    cat > /etc/systemd/system/minotari-node.service << EOF
[Unit]
Description=Minotari Node (Tari)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=${POOL_USER}
Group=${POOL_USER}

ExecStart=${TARI_DIR}/bin/minotari_node --config=${TARI_DIR}/config/config.toml --base-path=${TARI_DIR}/data
ExecStop=/bin/kill -SIGTERM \$MAINPID

Restart=on-failure
RestartSec=30
TimeoutStartSec=infinity

NoNewPrivileges=true
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF

    if [ "${MONERO_TARI_MODE}" = "merge" ]; then
        # Merge mining proxy service
        cat > /etc/systemd/system/minotari-merge-proxy.service << EOF
[Unit]
Description=Minotari Merge Mining Proxy (XMR+XTM)
After=monerod.service minotari-node.service
Requires=monerod.service minotari-node.service

[Service]
Type=simple
User=${POOL_USER}
Group=${POOL_USER}

ExecStart=${TARI_DIR}/bin/minotari_merge_mining_proxy --config=${TARI_MERGE_DIR}/config/config.toml
ExecStop=/bin/kill -SIGTERM \$MAINPID

Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
        log "  Merge mining proxy service created"

    elif [ "${MONERO_TARI_MODE}" = "tari_only" ]; then
        # Tari miner service
        cat > /etc/systemd/system/minotari-miner.service << EOF
[Unit]
Description=Minotari Miner (Tari Solo)
After=minotari-node.service
Requires=minotari-node.service

[Service]
Type=simple
User=${POOL_USER}
Group=${POOL_USER}

ExecStart=${TARI_DIR}/bin/minotari_miner --config=${TARI_MINER_DIR}/config/config.toml
ExecStop=/bin/kill -SIGTERM \$MAINPID

Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
        log "  Tari miner service created"
    fi

    log "  Tari services created"
fi

# =============================================================================
# ALEO SERVICES
# =============================================================================
if [ "${ENABLE_ALEO_POOL}" = "true" ]; then
    log "Creating ALEO services..."

    cat > /etc/systemd/system/snarkos.service << EOF
[Unit]
Description=ALEO snarkOS Prover
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=${POOL_USER}
Group=${POOL_USER}

# Note: You must edit this to add your private key!
# ExecStart=${ALEO_DIR}/bin/snarkos start --prover YOUR_PRIVATE_KEY --nodisplay
ExecStart=${ALEO_DIR}/start-prover.sh

Restart=on-failure
RestartSec=30
TimeoutStartSec=infinity

NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
EOF

    log "  ALEO service created"
    log "  NOTE: Edit /etc/systemd/system/snarkos.service to add your private key"
fi

# =============================================================================
# RELOAD AND ENABLE SERVICES
# =============================================================================
log "Reloading systemd..."
run_cmd systemctl daemon-reload

log "Enabling services..."

# Enable node services (but don't start - they need to sync)
[ "${ENABLE_BITCOIN_POOL}" = "true" ] && systemctl enable bitcoind >/dev/tty1 2>&1
[ "${ENABLE_BCH_POOL}" = "true" ] && systemctl enable bchn >/dev/tty1 2>&1
[ "${ENABLE_DGB_POOL}" = "true" ] && systemctl enable digibyted >/dev/tty1 2>&1
[ "${ENABLE_MONERO_POOL}" = "true" ] && systemctl enable monerod >/dev/tty1 2>&1
[ "${ENABLE_TARI_POOL}" = "true" ] && [ "${MONERO_TARI_MODE}" != "monero_only" ] && systemctl enable minotari-node >/dev/tty1 2>&1
[ "${ENABLE_ALEO_POOL}" = "true" ] && systemctl enable snarkos >/dev/tty1 2>&1

# Enable pool services (they depend on nodes)
[ "${ENABLE_BITCOIN_POOL}" = "true" ] && systemctl enable ckpool-btc >/dev/tty1 2>&1
[ "${ENABLE_BCH_POOL}" = "true" ] && systemctl enable ckpool-bch >/dev/tty1 2>&1
[ "${ENABLE_DGB_POOL}" = "true" ] && systemctl enable ckpool-dgb >/dev/tty1 2>&1

if [ "${MONERO_TARI_MODE}" = "monero_only" ]; then
    systemctl enable monero-stratum >/dev/tty1 2>&1
elif [ "${MONERO_TARI_MODE}" = "merge" ]; then
    systemctl enable minotari-merge-proxy >/dev/tty1 2>&1
elif [ "${MONERO_TARI_MODE}" = "tari_only" ]; then
    systemctl enable minotari-miner >/dev/tty1 2>&1
fi

log_success "Systemd services configured and enabled"
log ""
log "Services are ENABLED but NOT STARTED"
log "Start services manually after configuration:"
log "  sudo systemctl start <service-name>"
log ""
log "Or start all node services:"
log "  sudo systemctl start bitcoind bchn digibyted monerod minotari-node"
