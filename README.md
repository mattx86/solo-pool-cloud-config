# Solo Mining Pool Cloud Configuration

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

This repository contains a cloud-config for deploying a Ubuntu 24.04 system capable of running multiple solo cryptocurrency mining pools.

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

Worker statistics are persisted in an SQLite database (`/opt/solo-pool/webui/data/stats.db`) and survive WebUI restarts. Offline workers can be deleted from the database via the dashboard.

### Payments Tab
- **Payment Stats** - Overview of pending and paid balances per coin (XMR, XTM, ALEO)
- **Recent Payments** - List of recent payments with status, amount, and transaction hash
- **Miner Lookup** - Look up individual miner balances and payment history by wallet address

The payments tab integrates with the payment processor service and automatically updates every 30 seconds.

### Authentication

The dashboard is protected by username/password authentication. Credentials are auto-generated during installation:

- **Username**: Configurable via `WEBUI_USER` (default: `admin`)
- **Password**: Auto-generated 16-character password using `apg`
- **Credentials file**: `/opt/solo-pool/.credentials`

To view your credentials after installation:
```bash
sudo cat /opt/solo-pool/.credentials
```

Sessions are stored in-memory and last 24 hours by default.

### Access URLs

Access the dashboard at:
- HTTPS: `https://YOUR_SERVER_IP:8443` (self-signed certificate, enabled by default)
- HTTP: `http://YOUR_SERVER_IP:8080` (disabled by default)

## Pool Wallets

For XMR, XTM, and ALEO pools, the installation script automatically generates pool wallets to receive block rewards. The payment processor then distributes rewards to miners based on their share contributions.

**Note:** BTC, BCH, and DGB pools use CKPool's BTCSOLO mode, where miners receive rewards directly to their wallet address (specified as their stratum username). No separate pool wallet or payment processing is needed for these pools.

### Generated Wallets

| Pool | Wallet Location | Backup File | Service |
|------|-----------------|-------------|---------|
| XMR | `/opt/solo-pool/node/monero/wallet/keys/` | `SEED_BACKUP.txt` | `wallet-xmr-rpc` |
| XTM | `/opt/solo-pool/node/tari/wallet/keys/` | `SEED_BACKUP.txt` | `wallet-xtm` |
| ALEO | `/opt/solo-pool/node/aleo/wallet/keys/` | `pool-wallet.privatekey` | N/A (uses private key directly) |

### Wallet Initialization

All pool wallets are **automatically generated during installation**. No manual configuration is needed.

**XMR Wallet**: Generated during `13-install-monero.sh`. The `wallet-xmr-rpc` service syncs the wallet after node sync.

**XTM Wallet**: Generated during `14-install-tari.sh`. The `wallet-xtm` service connects after node sync.

**ALEO Wallet**: Generated during `15-install-aleo.sh`. The private key is used directly by the payment processor.

```bash
# View wallet addresses (available immediately after install)
cat /opt/solo-pool/node/monero/wallet/keys/pool-wallet.address
cat /opt/solo-pool/node/tari/wallet/keys/pool-wallet.address
cat /opt/solo-pool/node/aleo/wallet/keys/pool-wallet.address
```

### Critical Backup Warning

**BACKUP these files immediately after installation:**

```bash
# XMR seed phrase (24 words)
/opt/solo-pool/node/monero/wallet/keys/SEED_BACKUP.txt

# XTM seed phrase (24 words)
/opt/solo-pool/node/tari/wallet/keys/SEED_BACKUP.txt

# ALEO private key
/opt/solo-pool/node/aleo/wallet/keys/pool-wallet.privatekey
```

**If you lose these backup files and the server is lost, your pool funds are UNRECOVERABLE.**

### Wallet Services

```bash
# Check wallet service status
sudo systemctl status wallet-xmr-rpc
sudo systemctl status wallet-xtm

# View wallet logs
sudo journalctl -u wallet-xmr-rpc -f
sudo journalctl -u wallet-xtm -f
```

## Payment Processor

The payment processor (`solo-pool-payments`) handles share tracking and reward distribution for XMR, XTM, and ALEO pools using the generated pool wallets.

### Features

- Share tracking from pool APIs
- Proportional reward distribution
- Automatic payments to miner wallets
- RESTful API for stats and history
- Integration with WebUI payments tab

### Configuration

The payment processor listens on port `8081` by default (configurable via `PAYMENTS_API_PORT` in config.sh). The WebUI proxies requests to the payment processor, so users access payment data through the WebUI's `/api/payments/*` endpoints.

### API Authentication

The payment processor API is protected by bearer token authentication. A shared token is automatically generated during installation and configured for both services:

- **Token file**: `/opt/solo-pool/.payments_api_token`
- **WebUI config**: `payments_api_token` in `/opt/solo-pool/webui/config/config.toml`
- **Payments config**: `token` in `/opt/solo-pool/payments/config/config.toml`

The token is a 64-character hex string generated using `openssl rand -hex 32`. All API endpoints (except `/api/health`) require the token in the `Authorization` header:

```bash
# Example: Access payment stats directly (not through WebUI)
curl -H "Authorization: Bearer $(cat /opt/solo-pool/.payments_api_token)" \
     http://127.0.0.1:8081/api/stats
```

The WebUI automatically includes this token when proxying requests to the payment processor.

### API Endpoints

The payment processor API is available directly at `http://127.0.0.1:8081` (internal) or proxied through the WebUI:

| Direct Endpoint | WebUI Proxy | Description |
|-----------------|-------------|-------------|
| `GET /api/health` | - | Health check |
| `GET /api/stats` | `GET /api/payments/stats` | All payment stats |
| `GET /api/stats/:coin` | `GET /api/payments/stats/:coin` | Stats for specific coin (xmr, xtm, aleo) |
| `GET /api/miner/:coin/:address` | `GET /api/payments/miner/:coin/:address` | Miner balance and history |
| `GET /api/payments/:coin` | `GET /api/payments/coin/:coin` | Recent payments |
| `GET /api/payments/:coin/:address` | - | Miner payment history |


## Resource Requirements

### Per-Pool Requirements

#### Bitcoin (BTC)
| Component | CPU Cores | RAM | Disk | Notes |
|-----------|-----------|-----|------|-------|
| bitcoind | 2 | 4 GB | 650 GB+ | Full node, pruned option available |
| CKPool | 0.5 | 50 MB | 100 MB | Very lightweight |
| **Subtotal** | **2.5** | **4 GB** | **~650 GB** | |

#### Bitcoin Cash (BCH)
| Component | CPU Cores | RAM | Disk | Notes |
|-----------|-----------|-----|------|-------|
| BCHN | 2 | 4 GB | 300 GB+ | Full node |
| CKPool | 0.5 | 50 MB | 100 MB | Very lightweight |
| **Subtotal** | **2.5** | **4 GB** | **~300 GB** | |

#### DigiByte (DGB)
| Component | CPU Cores | RAM | Disk | Notes |
|-----------|-----------|-----|------|-------|
| digibyted | 2 | 2 GB | 50 GB+ | Full node |
| CKPool | 0.5 | 50 MB | 100 MB | Very lightweight |
| **Subtotal** | **2.5** | **2 GB** | **~50 GB** | |

#### Monero (XMR) - Solo Only
| Component | CPU Cores | RAM | Disk | Notes |
|-----------|-----------|-----|------|-------|
| monerod | 2 | 4 GB | 200 GB+ | Full node |
| monero-pool | 1 | 500 MB | 500 MB | Pool with PPLNS payouts |
| **Subtotal** | **3** | **4.5 GB** | **~201 GB** | |

#### Tari (XTM) - Solo Only
| Component | CPU Cores | RAM | Disk | Notes |
|-----------|-----------|-----|------|-------|
| minotari_node | 2 | 2 GB | 50 GB+ | Full node |
| minotari_miner | 1 | 500 MB | 50 MB | Solo miner |
| **Subtotal** | **3** | **2.5 GB** | **~50 GB** | |

#### Monero + Tari Merge Mining
| Component | CPU Cores | RAM | Disk | Notes |
|-----------|-----------|-----|------|-------|
| monerod | 2 | 4 GB | 200 GB+ | Full node |
| minotari_node | 2 | 2 GB | 50 GB+ | Full node |
| minotari_merge_mining_proxy | 1 | 500 MB | 50 MB | Merge mining proxy |
| **Subtotal** | **5** | **6.5 GB** | **~250 GB** | |

#### ALEO
| Component | CPU Cores | RAM | Disk | Notes |
|-----------|-----------|-----|------|-------|
| snarkOS (prover) | 8+ | 16 GB+ | 100 GB+ | CPU-intensive ZK proofs |
| **Subtotal** | **8** | **16 GB** | **~100 GB** | GPU recommended for proving |

### Total Resource Requirements

#### All Pools Enabled (Merge Mining Mode for XMR/XTM)

| Resource | Minimum | Recommended | Notes |
|----------|---------|-------------|-------|
| **CPU Cores** | 16 | 24+ | ALEO is very CPU-intensive |
| **RAM** | 32 GB | 64 GB | Allows headroom for blockchain sync |
| **Disk** | 1.5 TB | 2 TB+ | SSD strongly recommended |
| **Network** | 100 Mbps | 1 Gbps | High bandwidth for blockchain sync |

#### Without ALEO

| Resource | Minimum | Recommended | Notes |
|----------|---------|-------------|-------|
| **CPU Cores** | 8 | 12+ | More reasonable without ALEO |
| **RAM** | 16 GB | 32 GB | |
| **Disk** | 1.4 TB | 2 TB | SSD strongly recommended |

#### Minimal Setup (BTC + XMR/XTM Merge Only)

| Resource | Minimum | Recommended | Notes |
|----------|---------|-------------|-------|
| **CPU Cores** | 6 | 8+ | |
| **RAM** | 12 GB | 16 GB | |
| **Disk** | 900 GB | 1 TB | SSD strongly recommended |

## Network Ports

### Ports to Open (When Ready to Mine)

| Service | Port | Protocol | Direction | Notes |
|---------|------|----------|-----------|-------|
| **SSH** | 22 | TCP | Inbound | Always open (configurable) |
| | | | | |
| **Bitcoin** | | | | |
| bitcoind P2P | 8333 | TCP | Both | Blockchain network |
| bitcoind RPC | 8332 | TCP | Localhost | Internal only |
| CKPool Stratum (BTC) | 3333 | TCP | Inbound | Miner connections |
| | | | | |
| **Bitcoin Cash** | | | | |
| BCHN P2P | 8333 | TCP | Both | Blockchain network |
| BCHN RPC | 8332 | TCP | Localhost | Internal only |
| CKPool Stratum (BCH) | 3334 | TCP | Inbound | Miner connections |
| | | | | |
| **DigiByte** | | | | |
| digibyted P2P | 12024 | TCP | Both | Blockchain network |
| digibyted RPC | 14022 | TCP | Localhost | Internal only |
| CKPool Stratum (DGB) | 3335 | TCP | Inbound | Miner connections |
| | | | | |
| **Monero** | | | | |
| monerod P2P | 18080 | TCP | Both | Blockchain network |
| monerod RPC | 18081 | TCP | Localhost | Internal only |
| monero-pool Stratum | 3336 | TCP | Inbound | Miner connections |
| monero-pool API | 4243 | TCP | Localhost | Internal only |
| | | | | |
| **Tari** | | | | |
| minotari_node P2P | 18189 | TCP | Both | Blockchain network |
| minotari_node GRPC | 18142 | TCP | Localhost | Internal only |
| minotari_miner Stratum | 3337 | TCP | Inbound | Miner connections |
| minotari_merge_proxy | 3338 | TCP | Inbound | Merge mining stratum |
| | | | | |
| **ALEO** | | | | |
| snarkOS P2P | 4130 | TCP | Both | Blockchain network |
| snarkOS REST | 3030 | TCP | Localhost | Internal only |
| aleo-pool-server Stratum | 3339 | TCP | Inbound | Miner connections |
| | | | | |
| **Web Dashboard** | | | | |
| WebUI HTTP | 8080 | TCP | Inbound | Dashboard access |
| WebUI HTTPS | 8443 | TCP | Inbound | Secure dashboard access |
| | | | | |
| **Payment Processor** | | | | |
| Payments API | 8081 | TCP | Localhost | Internal only (WebUI proxy)

### Default Firewall Configuration

The firewall is automatically configured during installation to allow:

- **SSH** - Port 22 (or custom `SSH_PORT`)
- **Stratum ports** - Only for enabled pools (3333-3339)
- **WebUI ports** - HTTP (8080) and/or HTTPS (8443) if enabled

P2P ports are **not** opened by default to reduce attack surface. The pools work fine with outbound-only P2P connections.

```bash
# View current firewall rules
sudo ufw status numbered

# Example: Open Bitcoin P2P port (optional, for better connectivity)
sudo ufw allow 8333/tcp comment 'Bitcoin P2P'
```

## Directory Structure

All components follow a standardized directory layout:
- **bin/** - Executables and start scripts
- **config/** - Configuration files
- **data/** - Runtime data (blockchain, databases)
- **logs/** - Log files
- **wallet/keys/** - Wallet keys and addresses (wallets only)

```
/opt/solo-pool/
├── .credentials                     # WebUI login credentials (auto-generated)
├── .payments_api_token              # API token for payments service auth
├── bin/                             # Management scripts
│   ├── start-all.sh                 # Start all chains (parallel)
│   ├── stop-all.sh                  # Stop all services
│   ├── restart-all.sh               # Restart all services
│   ├── start-nodes.sh               # Start all node services
│   ├── stop-nodes.sh                # Stop all node services
│   ├── start-pools.sh               # Start all pool services
│   ├── stop-pools.sh                # Stop all pool services
│   ├── start-btc.sh                 # Bitcoin: node → sync → stratum
│   ├── start-bch.sh                 # Bitcoin Cash: node → sync → stratum
│   ├── start-dgb.sh                 # DigiByte: node → sync → stratum
│   ├── start-xmr.sh                 # Monero: node → sync → wallet → stratum
│   ├── start-xtm.sh                 # Tari: node → sync → wallet → stratum
│   ├── start-aleo.sh                # ALEO: node → sync → stratum
│   ├── status.sh                    # Check service status
│   ├── sync-status.sh               # Check blockchain sync progress
│   ├── maintenance.sh               # Daily maintenance (SQLite + logs + backup)
│   └── backup.sh                    # Create compressed backup
├── backups/                         # Daily backups (auto-generated)
│   └── solo-pool-backup-*.tar.gz    # Compressed backups (30-day retention)
├── config/                          # System configuration
│   ├── logrotate.conf               # Log rotation config
│   └── logrotate.state              # Logrotate state file
├── install/                         # Installation scripts and config
│   ├── config.sh                    # Configuration variables
│   ├── install.log                  # Installation log
│   └── *.sh                         # Downloaded setup scripts
├── logs/
│   ├── maintenance.log              # Maintenance task logs
│   └── startup/                     # Per-chain startup logs
│       ├── btc.log
│       ├── xmr.log
│       └── ...
├── node/
│   ├── bitcoin/
│   │   ├── bin/                     # bitcoind, bitcoin-cli
│   │   ├── config/
│   │   │   └── bitcoin.conf
│   │   ├── data/                    # Blockchain data
│   │   └── logs/
│   ├── bchn/
│   │   ├── bin/
│   │   ├── config/
│   │   │   └── bitcoin.conf
│   │   ├── data/
│   │   └── logs/
│   ├── digibyte/
│   │   ├── bin/
│   │   ├── config/
│   │   │   └── digibyte.conf
│   │   ├── data/
│   │   └── logs/
│   ├── monero/
│   │   ├── bin/                     # monerod, monero-wallet-cli, monero-wallet-rpc
│   │   │   └── start-wallet-rpc.sh
│   │   ├── config/
│   │   │   └── monerod.conf
│   │   ├── data/
│   │   ├── logs/
│   │   └── wallet/                  # Pool wallet (created after sync)
│   │       ├── keys/
│   │       │   ├── .initialized     # Marker file (created by start-xmr.sh)
│   │       │   ├── pool-wallet      # Wallet files
│   │       │   ├── pool-wallet.address
│   │       │   ├── pool-wallet.password
│   │       │   └── SEED_BACKUP.txt  # ⚠️ BACKUP THIS!
│   │       ├── data/
│   │       └── logs/
│   ├── tari/
│   │   ├── bin/                     # minotari_node, minotari_console_wallet, etc.
│   │   │   └── start-wallet.sh
│   │   ├── config/
│   │   │   └── config.toml
│   │   ├── data/
│   │   ├── logs/
│   │   └── wallet/                  # Pool wallet (created after sync)
│   │       ├── keys/
│   │       │   ├── .initialized     # Marker file (created by start-xtm.sh)
│   │       │   ├── pool-wallet.password
│   │       │   ├── pool-wallet.address
│   │       │   └── SEED_BACKUP.txt  # ⚠️ BACKUP THIS!
│   │       ├── config/
│   │       │   └── config.toml
│   │       ├── data/
│   │       └── logs/
│   └── aleo/
│       ├── bin/
│       │   ├── start-node.sh
│       │   └── snarkos
│       ├── config/
│       ├── data/
│       ├── logs/
│       ├── wallet/                  # Pool wallet keypair
│       │   ├── keys/
│       │   │   ├── pool-wallet.keys
│       │   │   ├── pool-wallet.address
│       │   │   └── pool-wallet.privatekey  # ⚠️ BACKUP THIS!
│       │   └── data/
│       └── SETUP_NOTES.txt
├── pool/
│   ├── btc-ckpool/
│   │   ├── bin/
│   │   │   └── ckpool
│   │   ├── config/
│   │   │   └── ckpool.conf
│   │   ├── data/
│   │   └── logs/
│   ├── bch-ckpool/
│   │   ├── bin/
│   │   ├── config/
│   │   │   └── ckpool.conf
│   │   ├── data/
│   │   └── logs/
│   ├── dgb-ckpool/
│   │   ├── bin/
│   │   ├── config/
│   │   │   └── ckpool.conf
│   │   ├── data/
│   │   └── logs/
│   ├── xmr-monero-pool/
│   │   ├── bin/
│   │   ├── config/
│   │   │   └── pool.conf
│   │   ├── data/
│   │   └── logs/
│   ├── xtm-minotari-miner/          # (tari_only mode)
│   │   ├── bin/
│   │   ├── config/
│   │   │   └── config.toml
│   │   ├── data/
│   │   └── logs/
│   ├── xmr-xtm-minotari-merge-proxy/ # (merge mode)
│   │   ├── bin/
│   │   ├── config/
│   │   │   └── config.toml
│   │   ├── data/
│   │   └── logs/
│   └── aleo-pool-server/
│       ├── bin/
│       │   └── start-pool.sh
│       ├── config/
│       │   └── config.toml
│       ├── data/
│       └── logs/
├── webui/                           # Web dashboard
│   ├── bin/
│   │   └── solo-pool-webui          # Dashboard binary
│   ├── config/
│   │   └── config.toml              # Dashboard configuration
│   ├── data/
│   │   └── stats.db                 # SQLite database for worker stats
│   ├── certs/                       # TLS certificates
│   │   ├── server.crt
│   │   └── server.key
│   └── logs/
│       ├── access.log               # Apache Combined Log Format
│       └── error.log
└── payments/                        # Payment processor (XMR, XTM, ALEO)
    ├── bin/
    │   └── solo-pool-payments       # Payment processor binary
    ├── config/
    │   └── config.toml              # Payment configuration
    ├── data/
    │   └── payments.db              # SQLite database
    └── logs/
```

## Repository Structure

```
solo-pool-cloud-config/
├── bin/                          # Management scripts (matches /opt/solo-pool/bin/)
│   ├── start-all.sh
│   ├── stop-all.sh
│   ├── restart-all.sh
│   ├── start-nodes.sh
│   ├── stop-nodes.sh
│   ├── start-pools.sh
│   ├── stop-pools.sh
│   ├── start-btc.sh
│   ├── start-bch.sh
│   ├── start-dgb.sh
│   ├── start-xmr.sh
│   ├── start-xtm.sh
│   ├── start-aleo.sh
│   ├── status.sh
│   ├── sync-status.sh
│   ├── maintenance.sh
│   └── backup.sh
├── install/                      # Installation scripts and deployment files
│   ├── 01-system-update.sh
│   ├── 02-cis-hardening.sh
│   ├── ...
│   ├── 99-finalize.sh
│   └── files/                    # Static files for deployment
│       ├── config/               # Configuration templates
│       ├── motd/                 # MOTD scripts
│       ├── notes/                # Setup notes
│       └── systemd/              # Systemd service files
├── payments/                     # Payment processor source
├── webui/                        # WebUI dashboard source
├── cloud-config.yaml             # Main cloud-init deployment config
└── README.md
```

## Configuration

### Cloud-Config Variables

Edit the following variables in the cloud-config/cloud-init before deployment:

```yaml
# Base URL where scripts are hosted (e.g., GitHub raw URL)
SCRIPTS_BASE_URL: "https://raw.githubusercontent.com/mattx86/solo-pool-cloud-config/refs/heads/main/install"

# Network Mode: "mainnet" (production) or "testnet" (testing)
NETWORK_MODE: "mainnet"

# Pool Selection
ENABLE_BITCOIN_POOL: "true"
ENABLE_BCH_POOL: "true"
ENABLE_DGB_POOL: "true"
ENABLE_MONERO_POOL: "true"
ENABLE_TARI_POOL: "true"
ENABLE_ALEO_POOL: "true"

# Monero/Tari Mining Mode: "merge", "monero_only", "tari_only"
MONERO_TARI_MODE: "merge"

# Optional: Custom SSH port (default: 22)
SSH_PORT: "22"

# Web Dashboard
ENABLE_WEBUI: "true"
WEBUI_HTTP_ENABLED: "false"      # Disabled by default (use HTTPS)
WEBUI_HTTP_PORT: "8080"
WEBUI_HTTPS_ENABLED: "true"
WEBUI_HTTPS_PORT: "8443"
WEBUI_REFRESH_INTERVAL: "15"     # Stats refresh interval in seconds
WEBUI_USER: "admin"              # Dashboard login username (password auto-generated)
```

## Testing Mode (Testnet)

The pool supports a testnet mode for testing the payment processor and pool functionality without risking real funds. Set `NETWORK_MODE="testnet"` in cloud-config.yaml before deployment.

### Network Mappings

| Coin | Mainnet | Testnet (NETWORK_MODE="testnet") |
|------|---------|----------------------------------|
| Bitcoin (BTC) | mainnet | testnet4 |
| Bitcoin Cash (BCH) | mainnet | testnet4 |
| DigiByte (DGB) | mainnet | testnet |
| Monero (XMR) | mainnet | stagenet |
| Tari (XTM) | mainnet | esmeralda |
| ALEO | mainnet | testnet |

### Testnet Port Differences

Some coins use different P2P/RPC ports on testnet:

| Service | Mainnet Port | Testnet Port |
|---------|--------------|--------------|
| Bitcoin RPC | 8332 | 48332 (testnet4) |
| Bitcoin P2P | 8333 | 48333 (testnet4) |
| BCH RPC | 8334 | 48334 (testnet4) |
| DGB RPC | 14022 | 14023 |
| Monero RPC | 18081 | 38081 (stagenet) |
| Monero P2P | 18080 | 38080 (stagenet) |

Stratum ports (3333-3339) remain the same regardless of network mode.

### Testing Workflow

1. Deploy with `NETWORK_MODE="testnet"` in cloud-config.yaml
2. Wait for testnet nodes to sync (typically faster than mainnet)
3. Check sync status: `/opt/solo-pool/bin/sync-status.sh`
4. Get testnet coins from faucets:
   - **BTC testnet4**: https://mempool.space/testnet4/faucet
   - **XMR stagenet**: https://stagenet-faucet.xmr-tw.org/
   - **Tari esmeralda**: Community faucets or testnet mining
5. Connect miners to stratum ports and mine
6. Verify payments are processed correctly

### Testnet Wallet Addresses

Testnet wallet addresses have different prefixes than mainnet:
- **Monero stagenet**: Addresses start with `5` (mainnet starts with `4`)
- **Bitcoin testnet**: Addresses start with `tb1`, `m`, `n`, or `2`

The installation scripts automatically handle these differences based on `NETWORK_MODE`.

## Deployment

### Any Cloud Provider (Hetzner, AWS, GCP, Azure, DigitalOcean, Vultr, Linode, OVH, etc.)

1. Create a new server/instance with Ubuntu 24.04
2. Paste the contents of `cloud-config.yaml` into the cloud-config/user-data field
3. Adjust the configuration variables at the top (enabled pools, WebUI settings, etc.)
4. Launch the server

**Provider-specific field names:**
- **Hetzner Cloud**: "Cloud config" field
- **AWS EC2**: "User data" field
- **Google Cloud**: "Automation > Startup script" or metadata key `user-data`
- **Azure**: "Custom data" field
- **DigitalOcean**: "User data" field
- **Vultr**: "Cloud-Init User-Data" field
- **Linode**: "User Data" field or StackScripts
- **OVH**: "Post-installation script" field

## Post-Deployment

### Check Installation Progress

```bash
# View live installation output (install log)
tail -f /opt/solo-pool/install/install.log

# Or view cloud-init output
tail -f /var/log/cloud-init-output.log

# Or connect to tty1 if available
# All output is directed to both /dev/tty1 and /opt/solo-pool/install/install.log
```

### Verify Services

```bash
# Check node services
sudo systemctl status node-btc-bitcoind
sudo systemctl status node-bch-bchn
sudo systemctl status node-dgb-digibyted
sudo systemctl status node-xmr-monerod
sudo systemctl status node-xtm-minotari
sudo systemctl status node-aleo-snarkos

# Check wallet services (for payment processing)
sudo systemctl status wallet-xmr-rpc              # XMR wallet RPC
sudo systemctl status wallet-xtm                  # XTM wallet daemon

# Check pool services
sudo systemctl status pool-btc-ckpool
sudo systemctl status pool-bch-ckpool
sudo systemctl status pool-dgb-ckpool
sudo systemctl status pool-xmr-monero-pool         # If monero_only mode
sudo systemctl status pool-xtm-minotari-miner      # If tari_only mode
sudo systemctl status pool-xmr-xtm-merge-proxy     # If merge mode
sudo systemctl status pool-aleo

# Check payment processor (XMR, XTM, ALEO)
sudo systemctl status solo-pool-payments

# Check web dashboard
sudo systemctl status solo-pool-webui
```

### Smart Startup

The startup scripts handle the full lifecycle for each coin:

1. Start the node
2. Wait for blockchain sync
3. Initialize wallet (XMR, XTM)
4. Start wallet service (XMR, XTM)
5. Start stratum server

All chains start **in parallel** for fastest startup - faster-syncing chains don't wait for slower ones.

```bash
# Start all services (recommended)
/opt/solo-pool/bin/start-all.sh           # Foreground mode - see all output
/opt/solo-pool/bin/start-all.sh --daemon  # Background mode with logging

# Monitor startup progress (daemon mode)
tail -f /opt/solo-pool/logs/startup/*.log

# Start individual coins
/opt/solo-pool/bin/start-btc.sh   # Bitcoin only
/opt/solo-pool/bin/start-bch.sh   # Bitcoin Cash only
/opt/solo-pool/bin/start-dgb.sh   # DigiByte only
/opt/solo-pool/bin/start-xmr.sh   # Monero only
/opt/solo-pool/bin/start-xtm.sh   # Tari only
/opt/solo-pool/bin/start-aleo.sh  # ALEO only
```

### Master Service

A master `solo-pool` systemd service is available for system boot integration:

```bash
# Start all services via systemd
sudo systemctl start solo-pool

# Stop all services via systemd
sudo systemctl stop solo-pool

# Restart all services via systemd
sudo systemctl restart solo-pool

# Check master service status
sudo systemctl status solo-pool

# Disable auto-start on boot
sudo systemctl disable solo-pool
```

### Additional Scripts

For manual control of individual service groups:

```bash
# Stop/restart all services
/opt/solo-pool/bin/stop-all.sh     # Stop all services
/opt/solo-pool/bin/restart-all.sh  # Restart all services

# Start/stop individual service groups
/opt/solo-pool/bin/start-nodes.sh  # Start all node services
/opt/solo-pool/bin/stop-nodes.sh   # Stop all node services
/opt/solo-pool/bin/start-pools.sh  # Start all pool services
/opt/solo-pool/bin/stop-pools.sh   # Stop all pool services

# Check status
/opt/solo-pool/bin/status.sh       # Check all service status
/opt/solo-pool/bin/sync-status.sh  # Check blockchain sync progress
```

### Firewall Ports

Stratum and WebUI ports are **automatically opened** during installation for enabled pools.

To open P2P ports for better node connectivity (optional):

```bash
sudo ufw allow 8333/tcp   # BTC/BCH P2P
sudo ufw allow 12024/tcp  # DGB P2P
sudo ufw allow 18080/tcp  # XMR P2P
sudo ufw allow 18189/tcp  # XTM P2P
sudo ufw allow 4130/tcp   # ALEO P2P
sudo ufw allow 3336/tcp   # monero-pool stratum (if using monero_only mode)

# View all open ports
sudo ufw status
```

## Security

### CIS Ubuntu 24.04 Hardening

The deployment automatically applies CIS (Center for Internet Security) Ubuntu 24.04 hardening benchmarks where applicable for a mining pool server. This includes:

- Filesystem hardening (nodev, nosuid, noexec on appropriate partitions)
- Kernel parameter hardening (sysctl)
- SSH hardening (key-only auth, protocol 2, etc.)
- Audit logging configuration
- Unnecessary service removal
- File permission hardening
- Network parameter hardening
- PAM configuration

Some CIS controls are intentionally skipped as they would interfere with pool operation (e.g., certain network restrictions).

### Firewall

UFW (Uncomplicated Firewall) is automatically configured to:
- **Allow SSH** - Port 22 (or custom SSH_PORT)
- **Allow stratum ports** - Only for enabled pools
- **Allow WebUI** - HTTP/HTTPS ports if dashboard is enabled
- **Deny all other incoming traffic**
- **Allow all outgoing traffic**

P2P ports are intentionally not opened to reduce attack surface. Nodes work fine with outbound-only connections.

## Maintenance

### Automated Daily Maintenance

A cron job runs daily at the scheduled time (default: 2:15 AM) to perform:

1. **SQLite Optimization**: VACUUM and ANALYZE on WebUI and Payments databases
2. **Log Rotation**: Rotate logs and compress rotated logs older than `LOG_COMPRESS_AFTER_DAYS`
3. **Cleanup**: Remove old log archives (older than `LOG_RETENTION_DAYS`)
4. **Backup**: Create compressed backup of `/opt/solo-pool` (excluding blockchain data)
5. **Disk Usage Report**: Log disk usage for monitoring

**Log Retention Policy** (configurable):
- Logs are rotated daily
- Uncompressed for first `LOG_COMPRESS_AFTER_DAYS` days (easy grep access)
- Compressed after `LOG_COMPRESS_AFTER_DAYS` days (gzip)
- Deleted after `LOG_RETENTION_DAYS` days

**Configuration Variables** (in `cloud-config.yaml`):
```yaml
MAINTENANCE_HOUR: "2"           # Hour (0-23)
MAINTENANCE_MINUTE: "15"        # Minute (0-59)
LOG_RETENTION_DAYS: "30"        # Delete logs older than this
LOG_COMPRESS_AFTER_DAYS: "7"    # Compress logs older than this
BACKUP_DIR: "/opt/solo-pool/backups"  # Backup location
BACKUP_RETENTION_DAYS: "30"     # Delete backups older than this
```

**Configuration Files**:
```bash
/opt/solo-pool/config/logrotate.conf  # Log rotation config
/etc/cron.d/solo-pool                  # Cron schedule
/opt/solo-pool/logs/maintenance.log    # Maintenance logs
```

**Manual Maintenance**:
```bash
# Run maintenance manually
/opt/solo-pool/bin/maintenance.sh

# Run backup only
/opt/solo-pool/bin/backup.sh

# View maintenance logs
cat /opt/solo-pool/logs/maintenance.log
```

### Update Node Software

```bash
# Stop services before updating
sudo systemctl stop pool-btc-ckpool node-btc-bitcoind

# Update and restart
# (Follow specific update procedures for each node)
sudo systemctl start node-btc-bitcoind pool-btc-ckpool
```

### View Logs

```bash
# Node logs
sudo journalctl -u node-btc-bitcoind -f
sudo journalctl -u node-xmr-monerod -f

# Pool logs
tail -f /opt/solo-pool/pool/btc-ckpool/logs/ckpool.log
sudo journalctl -u pool-xmr-monero-pool -f

# Payment processor logs
sudo journalctl -u solo-pool-payments -f

# WebUI logs
sudo journalctl -u solo-pool-webui -f
tail -f /opt/solo-pool/webui/logs/access.log
tail -f /opt/solo-pool/webui/logs/error.log
```

### Backup

#### Automated Backups

Daily backups are created automatically as part of maintenance (default: 2:15 AM).

**What's backed up:**
- Configuration files (`install/`, `config/`, pool configs)
- Wallet keys and seeds
- WebUI and Payments databases
- Credentials and tokens
- Current log files (not rotated archives)

**What's excluded (to save space):**
- Blockchain data (`node/*/data/`)
- Backup directory itself
- Compressed log archives

**Backup location and format:**
```bash
/opt/solo-pool/backups/solo-pool-backup-YYYYMMDD_HHMMSS_-0600.tar.gz
```
Filename includes timestamp and timezone offset for clarity.

**Retention:** 30 days (configurable via `BACKUP_RETENTION_DAYS`)

**Manual backup:**
```bash
/opt/solo-pool/bin/backup.sh
```

#### CRITICAL - Pool Wallet Seeds/Keys

**Funds are at risk if lost. Backup these files immediately after installation:**

- `/opt/solo-pool/node/monero/wallet/keys/SEED_BACKUP.txt` - XMR wallet seed phrase
- `/opt/solo-pool/node/tari/wallet/keys/SEED_BACKUP.txt` - XTM wallet seed phrase
- `/opt/solo-pool/node/aleo/wallet/keys/pool-wallet.privatekey` - ALEO private key

These are included in daily backups, but you should also keep an off-server copy.

#### Important Configuration Files

- `/opt/solo-pool/install/config.sh` - Your configuration
- `/opt/solo-pool/.credentials` - WebUI login credentials
- `/opt/solo-pool/.payments_api_token` - API token for payment processor
- `/opt/solo-pool/pool/*/config/` - Pool configurations
- `/opt/solo-pool/webui/config/config.toml` - WebUI configuration
- `/opt/solo-pool/webui/certs/` - TLS certificates (if using custom certs)
- `/opt/solo-pool/webui/data/` - WebUI database (worker stats history)
- `/opt/solo-pool/payments/config/config.toml` - Payment processor configuration
- `/opt/solo-pool/payments/data/` - Payment database (share history, balances)

## Troubleshooting

### Node Not Syncing

1. Check disk space: `df -h`
2. Check network connectivity: `curl -I https://api.github.com`
3. Check firewall: `sudo ufw status`
4. Check service logs: `sudo journalctl -u <service> -n 100`

### Pool Not Accepting Connections

1. Verify node is fully synced
2. Check stratum port is open: `sudo ufw status | grep 333`
3. Check pool service is running: `sudo systemctl status pool-btc-ckpool`
4. Check pool logs for errors

### High Resource Usage

1. Check which process: `htop`
2. ALEO proving is CPU-intensive by design
3. Initial blockchain sync is resource-intensive

### WebUI Not Accessible

1. Check service is running: `sudo systemctl status solo-pool-webui`
2. Check firewall: `sudo ufw status | grep 808`
3. Check logs: `sudo journalctl -u solo-pool-webui -n 50`
4. Verify ports in config: `cat /opt/solo-pool/webui/config/config.toml`
5. View login credentials: `sudo cat /opt/solo-pool/.credentials`

### Payment Processor Issues

1. Check service is running: `sudo systemctl status solo-pool-payments`
2. Check logs: `sudo journalctl -u solo-pool-payments -n 50`
3. Verify pool API is accessible: `curl http://127.0.0.1:PORT/api/stats`
4. Check database: `sqlite3 /opt/solo-pool/payments/data/payments.db ".tables"`
5. For ALEO: Ensure private key is set in `config/config.toml`

### Wallet Service Issues

**XMR (wallet-xmr-rpc):**
1. Check service status: `sudo systemctl status wallet-xmr-rpc`
2. Ensure monerod is synced: `sudo journalctl -u node-xmr-monerod | tail -20`
3. Check wallet was initialized: `ls -la /opt/solo-pool/node/monero/wallet/keys/.initialized`
4. Check wallet-rpc logs: `sudo journalctl -u wallet-xmr-rpc -n 50`
5. Check startup log: `tail -f /opt/solo-pool/logs/startup/xmr.log`
6. Re-run initialization: `/opt/solo-pool/bin/start-xmr.sh`

**XTM (wallet-xtm):**
1. Ensure node is synced first: `sudo systemctl status node-xtm-minotari`
2. Check wallet was initialized: `ls -la /opt/solo-pool/node/tari/wallet/keys/.initialized`
3. Check wallet address: `cat /opt/solo-pool/node/tari/wallet/keys/pool-wallet.address`
4. Check wallet logs: `sudo journalctl -u wallet-xtm -n 50`
5. Check startup log: `tail -f /opt/solo-pool/logs/startup/xtm.log`
6. Re-run initialization: `/opt/solo-pool/bin/start-xtm.sh`

**ALEO:**
1. Verify keypair was generated: `ls -la /opt/solo-pool/node/aleo/wallet/keys/`
2. Check address file: `cat /opt/solo-pool/node/aleo/wallet/keys/pool-wallet.address`
3. Ensure private key is in payment processor config

## License

MIT License - Use at your own risk. Solo mining is inherently high-variance.

## Disclaimer

Solo mining has extremely high variance. You may mine for extended periods without finding a block. This configuration is provided as-is without warranty. Always secure your wallet addresses and keep backups.
