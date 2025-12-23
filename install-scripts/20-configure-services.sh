#!/bin/bash
# =============================================================================
# 20-configure-services.sh
# Configure systemd services for all nodes and pools
#
# Service naming convention:
#   node-<coin>-<software>  (e.g., node-btc-bitcoind)
#   pool-<coin>-<software>  (e.g., pool-btc-ckpool)
#   pool-<coin>-<coin>-<software>  (e.g., pool-xmr-xtm-merge-proxy)
# =============================================================================

set -e

# Source configuration
source /opt/solo-pool/install-scripts/config.sh

# Validate config was loaded successfully
if [ "${CONFIG_LOADED:-}" != "true" ]; then
    echo "ERROR: Failed to load configuration from config.sh" >&2
    exit 1
fi

log "Configuring systemd services..."

# =============================================================================
# BITCOIN SERVICES
# =============================================================================
if [ "${ENABLE_BITCOIN_POOL}" = "true" ]; then
    log "Creating Bitcoin services..."

    # node-btc-bitcoind service
    cat > /etc/systemd/system/node-btc-bitcoind.service << EOF
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

[Install]
WantedBy=multi-user.target
EOF

    # pool-btc-ckpool service
    # Each CKPool instance uses its own socket directory for API access
    cat > /etc/systemd/system/pool-btc-ckpool.service << EOF
[Unit]
Description=CKPool Bitcoin Stratum Server
After=node-btc-bitcoind.service
Requires=node-btc-bitcoind.service

[Service]
Type=simple
User=${POOL_USER}
Group=${POOL_USER}

WorkingDirectory=${BTC_CKPOOL_DIR}
# -B enables BTCSOLO mode: miners use their wallet address as username, pool pays directly to that address
# -s sets socket directory for API access (used by webui for live stats)
ExecStartPre=/bin/mkdir -p ${BTC_CKPOOL_SOCKET_DIR}
ExecStart=${BTC_CKPOOL_DIR}/bin/ckpool -B -c ${BTC_CKPOOL_DIR}/ckpool.conf -l ${BTC_CKPOOL_DIR}/logs -s ${BTC_CKPOOL_SOCKET_DIR}

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

    # node-bch-bchn service
    cat > /etc/systemd/system/node-bch-bchn.service << EOF
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

[Install]
WantedBy=multi-user.target
EOF

    # pool-bch-ckpool service
    # Each CKPool instance uses its own socket directory for API access
    cat > /etc/systemd/system/pool-bch-ckpool.service << EOF
[Unit]
Description=CKPool Bitcoin Cash Stratum Server
After=node-bch-bchn.service
Requires=node-bch-bchn.service

[Service]
Type=simple
User=${POOL_USER}
Group=${POOL_USER}

WorkingDirectory=${BCH_CKPOOL_DIR}
# -B enables BTCSOLO mode: miners use their wallet address as username, pool pays directly to that address
# -s sets socket directory for API access (used by webui for live stats)
ExecStartPre=/bin/mkdir -p ${BCH_CKPOOL_SOCKET_DIR}
ExecStart=${BCH_CKPOOL_DIR}/bin/ckpool -B -c ${BCH_CKPOOL_DIR}/ckpool.conf -l ${BCH_CKPOOL_DIR}/logs -s ${BCH_CKPOOL_SOCKET_DIR}

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

    # node-dgb-digibyted service
    cat > /etc/systemd/system/node-dgb-digibyted.service << EOF
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

    # pool-dgb-ckpool service
    # Each CKPool instance uses its own socket directory for API access
    cat > /etc/systemd/system/pool-dgb-ckpool.service << EOF
[Unit]
Description=CKPool DigiByte Stratum Server
After=node-dgb-digibyted.service
Requires=node-dgb-digibyted.service

[Service]
Type=simple
User=${POOL_USER}
Group=${POOL_USER}

WorkingDirectory=${DGB_CKPOOL_DIR}
# -B enables BTCSOLO mode: miners use their wallet address as username, pool pays directly to that address
# -s sets socket directory for API access (used by webui for live stats)
ExecStartPre=/bin/mkdir -p ${DGB_CKPOOL_SOCKET_DIR}
ExecStart=${DGB_CKPOOL_DIR}/bin/ckpool -B -c ${DGB_CKPOOL_DIR}/ckpool.conf -l ${DGB_CKPOOL_DIR}/logs -s ${DGB_CKPOOL_SOCKET_DIR}

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

    # node-xmr-monerod service
    cat > /etc/systemd/system/node-xmr-monerod.service << EOF
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

    # wallet-xmr-rpc service (required for payment processing)
    cat > /etc/systemd/system/wallet-xmr-rpc.service << EOF
[Unit]
Description=Monero Wallet RPC (Pool Payments)
After=network-online.target node-xmr-monerod.service
Wants=network-online.target
Requires=node-xmr-monerod.service

[Service]
Type=simple
User=${POOL_USER}
Group=${POOL_USER}

ExecStart=${MONERO_DIR}/start-wallet-rpc.sh
ExecStop=/bin/kill -SIGTERM \$MAINPID

Restart=on-failure
RestartSec=30
TimeoutStartSec=120
TimeoutStopSec=60

NoNewPrivileges=true
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF
    log "  Monero wallet-rpc service created"

    # pool-xmr-monero-pool service (only for monero_only mode)
    if [ "${MONERO_TARI_MODE}" = "monero_only" ]; then
        cat > /etc/systemd/system/pool-xmr-monero-pool.service << EOF
[Unit]
Description=monero-pool Monero Mining Pool
After=node-xmr-monerod.service wallet-xmr-rpc.service
Requires=node-xmr-monerod.service wallet-xmr-rpc.service

[Service]
Type=simple
User=${POOL_USER}
Group=${POOL_USER}

WorkingDirectory=${XMR_MONERO_POOL_DIR}
ExecStart=${XMR_MONERO_POOL_DIR}/start-monero-pool.sh

Restart=on-failure
RestartSec=10

NoNewPrivileges=true
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF
        log "  monero-pool service created"
    fi

    log "  Monero services created"
fi

# =============================================================================
# TARI SERVICES
# =============================================================================
if [ "${ENABLE_TARI_POOL}" = "true" ] && [ "${MONERO_TARI_MODE}" != "monero_only" ]; then
    log "Creating Tari services..."

    # node-xtm-minotari service
    cat > /etc/systemd/system/node-xtm-minotari.service << EOF
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
TimeoutStopSec=120

NoNewPrivileges=true
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF

    # wallet-xtm service (required for payment processing)
    cat > /etc/systemd/system/wallet-xtm.service << EOF
[Unit]
Description=Tari Wallet (Pool Payments)
After=network-online.target node-xtm-minotari.service
Wants=network-online.target
Requires=node-xtm-minotari.service

[Service]
Type=simple
User=${POOL_USER}
Group=${POOL_USER}

ExecStart=${TARI_DIR}/start-wallet.sh
ExecStop=/bin/kill -SIGTERM \$MAINPID

Restart=on-failure
RestartSec=30
TimeoutStartSec=120
TimeoutStopSec=60

NoNewPrivileges=true
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF
    log "  Tari wallet service created"

    if [ "${MONERO_TARI_MODE}" = "merge" ]; then
        # pool-xmr-xtm-merge-proxy service
        cat > /etc/systemd/system/pool-xmr-xtm-merge-proxy.service << EOF
[Unit]
Description=Minotari Merge Mining Proxy (XMR+XTM)
After=node-xmr-monerod.service node-xtm-minotari.service
Requires=node-xmr-monerod.service node-xtm-minotari.service

[Service]
Type=simple
User=${POOL_USER}
Group=${POOL_USER}

ExecStart=${TARI_DIR}/bin/minotari_merge_mining_proxy --config=${XMR_XTM_MERGE_DIR}/config/config.toml
ExecStop=/bin/kill -SIGTERM \$MAINPID

Restart=on-failure
RestartSec=10

NoNewPrivileges=true
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF
        log "  Merge mining proxy service created"

    elif [ "${MONERO_TARI_MODE}" = "tari_only" ]; then
        # pool-xtm-minotari-miner service
        cat > /etc/systemd/system/pool-xtm-minotari-miner.service << EOF
[Unit]
Description=Minotari Miner (Tari Solo)
After=node-xtm-minotari.service
Requires=node-xtm-minotari.service

[Service]
Type=simple
User=${POOL_USER}
Group=${POOL_USER}

ExecStart=${TARI_DIR}/bin/minotari_miner --config=${XTM_MINER_DIR}/config/config.toml
ExecStop=/bin/kill -SIGTERM \$MAINPID

Restart=on-failure
RestartSec=10

NoNewPrivileges=true
PrivateTmp=true

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

    # node-aleo-snarkos service (snarkOS network node)
    cat > /etc/systemd/system/node-aleo-snarkos.service << EOF
[Unit]
Description=ALEO snarkOS Node
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=${POOL_USER}
Group=${POOL_USER}

ExecStart=${ALEO_DIR}/start-node.sh

Restart=on-failure
RestartSec=30
TimeoutStartSec=infinity
TimeoutStopSec=120

NoNewPrivileges=true
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF

    # pool-aleo service (aleo-pool-server stratum)
    cat > /etc/systemd/system/pool-aleo.service << EOF
[Unit]
Description=ALEO Pool Server (Stratum)
After=network-online.target node-aleo-snarkos.service
Wants=network-online.target
Requires=node-aleo-snarkos.service

[Service]
Type=simple
User=${POOL_USER}
Group=${POOL_USER}

ExecStart=${ALEO_POOL_DIR}/start-pool.sh

Restart=on-failure
RestartSec=10
TimeoutStartSec=60
TimeoutStopSec=30

NoNewPrivileges=true
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF

    log "  ALEO node and pool services created"
fi

# =============================================================================
# PAYMENT PROCESSOR SERVICE
# =============================================================================
# Note: The payment processor systemd service is created by 17-install-payments.sh
# We only need to check if it needs to be enabled (for service dependency tracking)
NEED_PAYMENTS="false"
[ "${ENABLE_MONERO_POOL}" = "true" ] && NEED_PAYMENTS="true"
[ "${ENABLE_TARI_POOL}" = "true" ] && NEED_PAYMENTS="true"
[ "${ENABLE_ALEO_POOL}" = "true" ] && NEED_PAYMENTS="true"

# =============================================================================
# MASTER SOLO-POOL SERVICE
# =============================================================================
log "Creating master solo-pool service..."

cat > /etc/systemd/system/solo-pool.service << EOF
[Unit]
Description=Solo Mining Pool - All Services
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes

ExecStart=${BASE_DIR}/start-all.sh
ExecStop=${BASE_DIR}/stop-all.sh

TimeoutStartSec=infinity
TimeoutStopSec=600

[Install]
WantedBy=multi-user.target
EOF

log "  Master solo-pool service created"

# =============================================================================
# RELOAD AND ENABLE SERVICES
# =============================================================================
log "Reloading systemd..."
run_cmd systemctl daemon-reload

log "Enabling services..."

# Enable node services (but don't start - they need to sync)
[ "${ENABLE_BITCOIN_POOL}" = "true" ] && systemctl enable node-btc-bitcoind >/dev/tty1 2>&1
[ "${ENABLE_BCH_POOL}" = "true" ] && systemctl enable node-bch-bchn >/dev/tty1 2>&1
[ "${ENABLE_DGB_POOL}" = "true" ] && systemctl enable node-dgb-digibyted >/dev/tty1 2>&1
[ "${ENABLE_MONERO_POOL}" = "true" ] && systemctl enable node-xmr-monerod >/dev/tty1 2>&1
[ "${ENABLE_TARI_POOL}" = "true" ] && [ "${MONERO_TARI_MODE}" != "monero_only" ] && systemctl enable node-xtm-minotari >/dev/tty1 2>&1
[ "${ENABLE_ALEO_POOL}" = "true" ] && systemctl enable node-aleo-snarkos >/dev/tty1 2>&1

# Enable wallet services (required for payment processing)
[ "${ENABLE_MONERO_POOL}" = "true" ] && systemctl enable wallet-xmr-rpc >/dev/tty1 2>&1
if [ "${ENABLE_TARI_POOL}" = "true" ] && [ "${MONERO_TARI_MODE}" != "monero_only" ]; then
    systemctl enable wallet-xtm >/dev/tty1 2>&1
fi

# Enable pool services (they depend on nodes)
[ "${ENABLE_BITCOIN_POOL}" = "true" ] && systemctl enable pool-btc-ckpool >/dev/tty1 2>&1
[ "${ENABLE_BCH_POOL}" = "true" ] && systemctl enable pool-bch-ckpool >/dev/tty1 2>&1
[ "${ENABLE_DGB_POOL}" = "true" ] && systemctl enable pool-dgb-ckpool >/dev/tty1 2>&1

if [ "${MONERO_TARI_MODE}" = "monero_only" ]; then
    systemctl enable pool-xmr-monero-pool >/dev/tty1 2>&1
elif [ "${MONERO_TARI_MODE}" = "merge" ]; then
    systemctl enable pool-xmr-xtm-merge-proxy >/dev/tty1 2>&1
elif [ "${MONERO_TARI_MODE}" = "tari_only" ]; then
    systemctl enable pool-xtm-minotari-miner >/dev/tty1 2>&1
fi

[ "${ENABLE_ALEO_POOL}" = "true" ] && systemctl enable pool-aleo >/dev/tty1 2>&1

# Enable payment processor if needed
[ "${NEED_PAYMENTS}" = "true" ] && systemctl enable solo-pool-payments >/dev/tty1 2>&1

# Enable master solo-pool service
systemctl enable solo-pool >/dev/tty1 2>&1

log_success "Systemd services configured and enabled"
log ""
log "Services are ENABLED but NOT STARTED"
log "The master 'solo-pool' service will start all services on boot"
log ""
log "Start all services:"
log "  sudo systemctl start solo-pool"
log ""
log "Stop all services:"
log "  sudo systemctl stop solo-pool"
log ""
log "Check status:"
log "  sudo systemctl status solo-pool"
