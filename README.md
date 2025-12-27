# Solo Pool

> **ALPHA SOFTWARE WARNING**
>
> This project is in **alpha stage** and under **heavy active development**.
>
> - Scripts and configurations may change significantly without notice
> - Not all features have been thoroughly tested in production
> - Use at your own risk and always review scripts before deploying
>
> **Do not use in production without thorough testing and review.**

---

Solo Pool is a multi-cryptocurrency solo mining pool server for Ubuntu 24.04. It supports multiple blockchain networks with automatic wallet generation, payment processing, and a web dashboard.

## Supported Pools

| Cryptocurrency | Node Software | Pool Software | Algorithm |
|----------------|---------------|---------------|-----------|
| Bitcoin (BTC) | bitcoind | CKPool | SHA256 |
| Bitcoin Cash (BCH) | BCHN | CKPool | SHA256 |
| DigiByte (DGB) | digibyted | CKPool | SHA256 only |
| Monero (XMR) | monerod | monero-pool | RandomX |
| Tari (XTM) | minotari_node | minotari_miner | RandomX |
| Monero+Tari | monerod + minotari_node | minotari_merge_mining_proxy | RandomX |
| ALEO | snarkOS | aleo-pool-server | AleoBFT/PoSW |

## Quick Start (Git Clone)

The recommended installation method is to clone the repository and run the installer:

```bash
# Clone the repository
git clone https://github.com/mattx86/solopool.git
cd solopool

# Copy and edit configuration
cp config.sh.example config.sh
nano config.sh  # Edit configuration options

# Run the installer (as root)
sudo ./install.sh
```

### Configuration Options

Edit `config.sh` before running the installer:

```bash
# Network Mode: "mainnet" (production) or "testnet" (testing)
NETWORK_MODE="mainnet"

# Sync Mode: "initial" (fast sync) or "production" (mining-ready)
SYNC_MODE="initial"

# Mount Point (optional) - leave empty for /opt/solopool
MOUNT_POINT=""

# Enable/disable pools
ENABLE_BITCOIN_POOL="true"
ENABLE_BCH_POOL="true"
ENABLE_DGB_POOL="true"
ENABLE_ALEO_POOL="true"

# Monero/Tari: "merge", "monero_only", "tari_only", or "false"
ENABLE_MONERO_TARI_POOL="merge"

# Web Dashboard
ENABLE_WEBUI="true"
```

### Post-Installation

```bash
# Check sync status
/opt/solopool/bin/sync-status.sh

# When sync is complete, switch to production mode
/opt/solopool/bin/switch-mode.sh production

# View login credentials
sudo cat /opt/solopool/.credentials
```

## Alternative: Cloud-Config Deployment

For cloud providers (Hetzner, AWS, GCP, Azure, DigitalOcean, Vultr, Linode, OVH):

1. Edit `cloud-config.yaml` with your desired configuration
2. Paste into your cloud provider's user-data/cloud-config field
3. Launch your server

## Software Versions

| Software | Version | Source |
|----------|---------|--------|
| Bitcoin Core | 30.0 | [bitcoin/bitcoin](https://github.com/bitcoin/bitcoin) |
| Bitcoin Cash Node (BCHN) | 28.0.1 | [bitcoin-cash-node/bitcoin-cash-node](https://gitlab.com/bitcoin-cash-node/bitcoin-cash-node) |
| DigiByte Core | 8.26.1 | [DigiByte-Core/digibyte](https://github.com/DigiByte-Core/digibyte) |
| Monero | 0.18.4.4 | [monero-project/monero](https://github.com/monero-project/monero) |
| Tari (minotari) | 5.1.0 | [tari-project/tari](https://github.com/tari-project/tari) |
| snarkOS | 4.4.0 | [ProvableHQ/snarkOS](https://github.com/ProvableHQ/snarkOS) |
| CKPool | commit 590fb2a | [ckolivas/ckpool](https://bitbucket.org/ckolivas/ckpool) |
| monero-pool | master | [jtgrassie/monero-pool](https://github.com/jtgrassie/monero-pool) |
| aleo-pool-server | commit 992792e | [foxpy/aleo-pool-server](https://github.com/foxpy/aleo-pool-server) |

## Web Dashboard

A built-in web dashboard provides real-time statistics for all enabled pools:

### Pool Stats Tab
- **Pool status** - Online/offline status for each pool
- **Hashrate** - Current hashrate across all workers
- **Workers** - Connected miners with hashrate, accepted/rejected shares, and blocks found
- **Blocks found** - Block discovery history
- **Zero fees** - All pools are fee-free (0% pool fee)

Worker statistics are persisted in an SQLite database (`/opt/solopool/webui/data/stats.db`) and survive WebUI restarts. Offline workers can be deleted from the database via the dashboard.

### Payments Tab
- **Payment Stats** - Overview of pending and paid balances per coin (XMR, XTM, ALEO)
- **Recent Payments** - List of recent payments with status, amount, and transaction hash
- **Miner Lookup** - Look up individual miner balances and payment history by wallet address

### Authentication

The dashboard is protected by username/password authentication. Credentials are auto-generated during installation:

- **Username**: Configurable via `WEBUI_USER` (default: `admin`)
- **Password**: Auto-generated 16-character password
- **Credentials file**: `/opt/solopool/.credentials`

```bash
# View your credentials after installation
sudo cat /opt/solopool/.credentials
```

### Access URLs

- HTTPS: `https://YOUR_SERVER_IP:8443` (self-signed certificate, enabled by default)
- HTTP: `http://YOUR_SERVER_IP:8080` (disabled by default)

## Pool Wallets

For XMR, XTM, and ALEO pools, the installation script automatically generates pool wallets to receive block rewards.

**Note:** BTC, BCH, and DGB pools use CKPool's BTCSOLO mode, where miners receive rewards directly to their wallet address (specified as their stratum username).

### Generated Wallets

| Pool | Wallet Location | Backup File | Service |
|------|-----------------|-------------|---------|
| XMR | `/opt/solopool/node/xmr/wallet/keys/` | `SEED_BACKUP.txt` | `wallet-xmr-rpc` |
| XTM | `/opt/solopool/node/xtm/wallet/keys/` | `SEED_BACKUP.txt` | `wallet-xtm` |
| ALEO | `/opt/solopool/node/aleo/wallet/keys/` | `pool-wallet.privatekey` | N/A |

### Critical Backup Warning

**BACKUP these files immediately after installation:**

```bash
# XMR seed phrase (24 words)
/opt/solopool/node/xmr/wallet/keys/SEED_BACKUP.txt

# XTM seed phrase (24 words)
/opt/solopool/node/xtm/wallet/keys/SEED_BACKUP.txt

# ALEO private key
/opt/solopool/node/aleo/wallet/keys/pool-wallet.privatekey
```

**If you lose these backup files and the server is lost, your pool funds are UNRECOVERABLE.**

## Payment Processor

The payment processor (`solopool-payments`) handles share tracking and reward distribution for XMR, XTM, and ALEO pools.

### Features
- Share tracking from pool APIs
- Proportional reward distribution
- Automatic payments to miner wallets
- RESTful API for stats and history
- Integration with WebUI payments tab

### API Endpoints

| Endpoint | Description |
|----------|-------------|
| `GET /api/health` | Health check |
| `GET /api/payments/stats` | All payment stats |
| `GET /api/payments/stats/:coin` | Stats for specific coin (xmr, xtm, aleo) |
| `GET /api/payments/miner/:coin/:address` | Miner balance and history |
| `GET /api/payments/coin/:coin` | Recent payments |

## Resource Requirements

### All Pools Enabled (Merge Mining Mode for XMR/XTM)

| Resource | Minimum | Recommended | Notes |
|----------|---------|-------------|-------|
| **CPU Cores** | 16 | 24+ | ALEO is very CPU-intensive |
| **RAM** | 32 GB | 64 GB | Allows headroom for blockchain sync |
| **Disk** | 1.5 TB | 2 TB+ | SSD strongly recommended |
| **Network** | 100 Mbps | 1 Gbps | High bandwidth for blockchain sync |

### Without ALEO

| Resource | Minimum | Recommended |
|----------|---------|-------------|
| **CPU Cores** | 8 | 12+ |
| **RAM** | 16 GB | 32 GB |
| **Disk** | 1.4 TB | 2 TB |

### Minimal Setup (BTC + XMR/XTM Merge Only)

| Resource | Minimum | Recommended |
|----------|---------|-------------|
| **CPU Cores** | 6 | 8+ |
| **RAM** | 12 GB | 16 GB |
| **Disk** | 900 GB | 1 TB |

## Network Ports

### Ports to Open (When Ready to Mine)

| Service | Port | Protocol | Notes |
|---------|------|----------|-------|
| SSH | 22 | TCP | Always open (configurable) |
| CKPool Stratum (BTC) | 3333 | TCP | Miner connections |
| CKPool Stratum (BCH) | 3334 | TCP | Miner connections |
| CKPool Stratum (DGB) | 3335 | TCP | Miner connections |
| monero-pool Stratum | 3336 | TCP | Miner connections |
| minotari_miner Stratum | 3337 | TCP | Miner connections |
| Merge proxy Stratum | 3338 | TCP | Merge mining stratum |
| aleo-pool-server Stratum | 3339 | TCP | Miner connections |
| WebUI HTTPS | 8443 | TCP | Secure dashboard access |

P2P ports are **not** opened by default to reduce attack surface. Nodes work fine with outbound-only connections.

## Directory Structure

All components use coin codes for directories:

```
/opt/solopool/
├── .credentials                     # WebUI login credentials
├── .payments_api_token              # API token for payments service
├── bin/                             # Management scripts
│   ├── start-all.sh                 # Start all chains (parallel)
│   ├── stop-all.sh                  # Stop all services
│   ├── restart-all.sh               # Restart all services
│   ├── start-btc.sh                 # Bitcoin: node → sync → stratum
│   ├── start-bch.sh                 # Bitcoin Cash: node → sync → stratum
│   ├── start-dgb.sh                 # DigiByte: node → sync → stratum
│   ├── start-xmr.sh                 # Monero: node → sync → wallet → stratum
│   ├── start-xtm.sh                 # Tari: node → sync → wallet → stratum
│   ├── start-aleo.sh                # ALEO: node → sync → stratum
│   ├── status.sh                    # Check service status
│   ├── sync-status.sh               # Check blockchain sync progress
│   ├── switch-mode.sh               # Switch between initial/production modes
│   ├── maintenance.sh               # Daily maintenance
│   └── backup.sh                    # Create compressed backup
├── install/                         # Installation scripts and config
│   └── config.sh                    # Configuration variables
├── node/
│   ├── btc/                         # Bitcoin Core
│   │   ├── bin/
│   │   ├── config/
│   │   ├── data/
│   │   └── logs/
│   ├── bch/                         # Bitcoin Cash Node
│   ├── dgb/                         # DigiByte Core
│   ├── xmr/                         # Monero
│   │   └── wallet/keys/             # Pool wallet
│   ├── xtm/                         # Tari
│   │   └── wallet/keys/             # Pool wallet
│   └── aleo/                        # ALEO snarkOS
│       └── wallet/keys/             # Pool wallet
├── pool/
│   ├── btc/                         # CKPool for Bitcoin
│   ├── bch/                         # CKPool for Bitcoin Cash
│   ├── dgb/                         # CKPool for DigiByte
│   ├── xmr/                         # monero-pool
│   ├── xtm/                         # minotari_miner
│   ├── xmr-xtm/                     # Merge mining proxy
│   └── aleo/                        # aleo-pool-server
├── webui/                           # Web dashboard
│   ├── bin/solopool-webui           # Dashboard binary
│   ├── config/config.toml
│   ├── data/stats.db
│   └── certs/
└── payments/                        # Payment processor
    ├── bin/solopool-payments
    ├── config/config.toml
    └── data/payments.db
```

## Sync Mode

The pool supports a two-phase deployment for faster initial sync:

### SYNC_MODE Options

| Mode | Bitcoin/BCH/DGB | Monero | Use Case |
|------|-----------------|--------|----------|
| `initial` | `blocksonly=1` | `db-sync-mode=fast` | Fast blockchain sync |
| `production` | Full mempool | `db-sync-mode=safe` | Mining-ready |

### Deployment Workflow

1. Deploy with `SYNC_MODE="initial"` (default) for fast sync
2. Monitor sync progress: `/opt/solopool/bin/sync-status.sh`
3. When sync is complete, switch to production mode:
   ```bash
   /opt/solopool/bin/switch-mode.sh production
   ```
4. Start mining! Pool services will automatically restart.

**Never mine with `SYNC_MODE="initial"`** - Nodes won't receive transactions, resulting in empty blocks.

## Testing Mode (Testnet)

Set `NETWORK_MODE="testnet"` for testing without real funds:

| Coin | Mainnet | Testnet |
|------|---------|---------|
| Bitcoin (BTC) | mainnet | testnet4 |
| Bitcoin Cash (BCH) | mainnet | testnet4 |
| DigiByte (DGB) | mainnet | testnet |
| Monero (XMR) | mainnet | stagenet |
| Tari (XTM) | mainnet | esmeralda |
| ALEO | mainnet | testnet |

## Service Management

### Master Service

```bash
# Start all services via systemd
sudo systemctl start solopool

# Stop all services
sudo systemctl stop solopool

# Check status
sudo systemctl status solopool
```

### Management Scripts

```bash
# Check service status
/opt/solopool/bin/status.sh

# Check blockchain sync progress
/opt/solopool/bin/sync-status.sh

# Start/stop all services
/opt/solopool/bin/start-all.sh
/opt/solopool/bin/stop-all.sh

# Start individual coins
/opt/solopool/bin/start-btc.sh
/opt/solopool/bin/start-xmr.sh
```

### Individual Services

```bash
# Node services
sudo systemctl status node-btc-bitcoind
sudo systemctl status node-bch-bchn
sudo systemctl status node-dgb-digibyted
sudo systemctl status node-xmr-monerod
sudo systemctl status node-xtm-minotari
sudo systemctl status node-aleo-snarkos

# Pool services
sudo systemctl status pool-btc-ckpool
sudo systemctl status pool-bch-ckpool
sudo systemctl status pool-dgb-ckpool
sudo systemctl status pool-xmr-monero-pool
sudo systemctl status pool-xtm-minotari-miner
sudo systemctl status pool-xmr-xtm-merge-proxy
sudo systemctl status pool-aleo

# WebUI and Payments
sudo systemctl status solopool-webui
sudo systemctl status solopool-payments
```

## Maintenance

### Automated Daily Maintenance

A cron job runs daily (default: 2:15 AM) to perform:
- SQLite optimization (VACUUM and ANALYZE)
- Log rotation and compression
- Backup creation (excluding blockchain data)
- Cleanup of old logs and backups

### Manual Operations

```bash
# Run maintenance manually
/opt/solopool/bin/maintenance.sh

# Run backup only
/opt/solopool/bin/backup.sh

# View maintenance logs
cat /opt/solopool/logs/maintenance.log
```

### Configuration

```bash
MAINTENANCE_HOUR="2"           # Hour (0-23)
MAINTENANCE_MINUTE="15"        # Minute (0-59)
LOG_RETENTION_DAYS="30"        # Delete logs older than this
LOG_COMPRESS_AFTER_DAYS="14"   # Compress logs older than this
BACKUP_RETENTION_DAYS="30"     # Delete backups older than this
```

## Troubleshooting

### Node Not Syncing

1. Check disk space: `df -h`
2. Check network: `curl -I https://api.github.com`
3. Check firewall: `sudo ufw status`
4. Check logs: `sudo journalctl -u node-btc-bitcoind -n 100`

### Pool Not Accepting Connections

1. Verify node is fully synced
2. Check stratum port is open: `sudo ufw status | grep 333`
3. Check pool service: `sudo systemctl status pool-btc-ckpool`

### WebUI Not Accessible

1. Check service: `sudo systemctl status solopool-webui`
2. Check firewall: `sudo ufw status | grep 808`
3. Check logs: `sudo journalctl -u solopool-webui -n 50`
4. View credentials: `sudo cat /opt/solopool/.credentials`

### Payment Processor Issues

1. Check service: `sudo systemctl status solopool-payments`
2. Check logs: `sudo journalctl -u solopool-payments -n 50`
3. Check database: `sqlite3 /opt/solopool/payments/data/payments.db ".tables"`

## Security

### CIS Ubuntu 24.04 Hardening

The deployment automatically applies CIS hardening benchmarks:
- Filesystem hardening
- Kernel parameter hardening
- SSH hardening (key-only auth)
- Audit logging
- File permission hardening

### Firewall

UFW is automatically configured to:
- **Allow SSH** - Port 22 (or custom SSH_PORT)
- **Allow stratum ports** - Only for enabled pools
- **Allow WebUI** - HTTP/HTTPS ports if enabled
- **Deny all other incoming traffic**

## License

MIT License - Use at your own risk. Solo mining is inherently high-variance.

## Disclaimer

Solo mining has extremely high variance. You may mine for extended periods without finding a block. This configuration is provided as-is without warranty. Always secure your wallet addresses and keep backups.
