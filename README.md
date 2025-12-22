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
| Monero (XMR) | monerod | P2Pool | RandomX |
| Tari (XTM) | minotari_node | minotari_miner | RandomX |
| Monero+Tari | monerod + minotari_node | minotari_merge_mining_proxy | RandomX |
| ALEO | snarkOS | snarkOS (integrated) | AleoBFT/PoSW |

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
| P2Pool | 1 | 1 GB | 1 GB | Decentralized pool with sidechain |
| **Subtotal** | **3** | **5 GB** | **~201 GB** | |

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
| P2Pool Stratum | 3336 | TCP | Inbound | Miner connections |
| P2Pool P2P | 37889 | TCP | Both | P2Pool sidechain network |
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

### Default Firewall Configuration

By default, only SSH (port 22) is allowed. Use the following commands to open ports as needed:

```bash
# Example: Open Bitcoin stratum port
sudo ufw allow 3333/tcp comment 'CKPool BTC Stratum'

# Example: Open Bitcoin P2P port
sudo ufw allow 8333/tcp comment 'Bitcoin P2P'

# View current rules
sudo ufw status numbered
```

## Directory Structure

```
/opt/solo-pool/
├── install-scripts/                 # Installation scripts and config
│   ├── config.sh                    # Configuration variables
│   ├── install.log                  # Installation log
│   └── *.sh                         # Downloaded setup scripts
├── node/
│   ├── bitcoin/
│   │   ├── bin/                     # bitcoind, bitcoin-cli
│   │   ├── data/                    # Blockchain data
│   │   └── bitcoin.conf
│   ├── bchn/
│   │   ├── bin/
│   │   ├── data/
│   │   └── bitcoin.conf
│   ├── digibyte/
│   │   ├── bin/
│   │   ├── data/
│   │   └── digibyte.conf
│   ├── monero/
│   │   ├── bin/
│   │   ├── data/
│   │   └── monerod.conf
│   ├── tari/
│   │   ├── bin/
│   │   ├── data/
│   │   └── config.toml
│   └── aleo/
│       ├── bin/
│       ├── data/
│       ├── logs/
│       ├── start-prover.sh
│       └── SETUP_NOTES.txt
└── pool/
    ├── btc-ckpool/
    │   ├── bin/
    │   ├── logs/
    │   └── ckpool.conf
    ├── bch-ckpool/
    │   ├── bin/
    │   ├── logs/
    │   └── ckpool.conf
    ├── dgb-ckpool/
    │   ├── bin/
    │   ├── logs/
    │   └── ckpool.conf
    ├── xmr-p2pool/
    │   ├── bin/
    │   ├── data/
    │   ├── logs/
    │   └── start-p2pool.sh
    ├── xtm-minotari-miner/          # (tari_only mode)
    │   ├── config/
    │   └── logs/
    ├── xmr-xtm-minotari-merge-proxy/ # (merge mode)
    │   ├── config/
    │   └── logs/
    └── aleo -> ../node/aleo         # Symlink (snarkOS is both node and prover)
```

## Configuration

### Cloud-Config Variables

Edit the following variables in the cloud-config/cloud-init before deployment:

```yaml
# Base URL where scripts are hosted (e.g., GitHub raw URL)
SCRIPTS_BASE_URL: "https://raw.githubusercontent.com/mattx86/solo-pool-cloud-config/refs/heads/main/install-scripts"

# Pool Selection
ENABLE_BITCOIN_POOL: "true"
ENABLE_BCH_POOL: "true"
ENABLE_DGB_POOL: "true"
ENABLE_MONERO_POOL: "true"
ENABLE_TARI_POOL: "true"
ENABLE_ALEO_POOL: "true"

# Monero/Tari Mining Mode: "merge", "monero_only", "tari_only"
MONERO_TARI_MODE: "merge"

# Wallet Addresses (REQUIRED for pools you enable)
BTC_WALLET_ADDRESS: "your-btc-address-here"
BCH_WALLET_ADDRESS: "your-bch-address-here"
DGB_WALLET_ADDRESS: "your-dgb-address-here"
XMR_WALLET_ADDRESS: "your-xmr-address-here"
XTM_WALLET_ADDRESS: "your-xtm-address-here"
ALEO_WALLET_ADDRESS: "your-aleo-address-here"

# Optional: Custom SSH port (default: 22)
SSH_PORT: "22"
```

## Deployment

### Any Cloud Provider (Hetzner, AWS, GCP, Azure, DigitalOcean, Vultr, Linode, OVH, etc.)

1. Create a new server/instance with Ubuntu 24.04
2. Paste the contents of `cloud-config.yaml` into the cloud-config/user-data field
3. Adjust the configuration variables at the top (wallet addresses, enabled pools, etc.)
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
tail -f /opt/solo-pool/install-scripts/install.log

# Or view cloud-init output
tail -f /var/log/cloud-init-output.log

# Or connect to tty1 if available
# All output is directed to both /dev/tty1 and /opt/solo-pool/install-scripts/install.log
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

# Check pool services
sudo systemctl status pool-btc-ckpool
sudo systemctl status pool-bch-ckpool
sudo systemctl status pool-dgb-ckpool
sudo systemctl status pool-xmr-p2pool              # If monero_only mode
sudo systemctl status pool-xtm-minotari-miner      # If tari_only mode
sudo systemctl status pool-xmr-xtm-merge-proxy     # If merge mode
```

### Master Service

A master `solo-pool` systemd service manages all node and pool services. It is enabled by default and will start all services on boot.

```bash
# Start all services via systemd
sudo systemctl start solo-pool

# Stop all services via systemd
sudo systemctl stop solo-pool

# Check master service status
sudo systemctl status solo-pool

# Disable auto-start on boot
sudo systemctl disable solo-pool
```

### Convenience Scripts

Convenience scripts are also available for manual control:

```bash
# Start/stop all services
/opt/solo-pool/start-all.sh    # Start nodes first, then pools
/opt/solo-pool/stop-all.sh     # Stop pools first, then nodes

# Start/stop individual service groups
/opt/solo-pool/start-nodes.sh  # Start all node services
/opt/solo-pool/stop-nodes.sh   # Stop all node services
/opt/solo-pool/start-pools.sh  # Start all pool services
/opt/solo-pool/stop-pools.sh   # Stop all pool services

# Check status
/opt/solo-pool/status.sh       # Check all service status
/opt/solo-pool/sync-status.sh  # Check blockchain sync progress
```

### Open Firewall Ports

Once nodes are synced and you're ready to accept miners:

```bash
# Open stratum ports for your enabled pools
sudo ufw allow 3333/tcp  # BTC
sudo ufw allow 3334/tcp  # BCH
sudo ufw allow 3335/tcp  # DGB
sudo ufw allow 3336/tcp  # XMR
sudo ufw allow 3337/tcp  # XTM (solo)
sudo ufw allow 3338/tcp  # XMR+XTM (merge)

# Open P2P ports for better node connectivity
sudo ufw allow 8333/tcp   # BTC/BCH
sudo ufw allow 12024/tcp  # DGB
sudo ufw allow 18080/tcp  # XMR
sudo ufw allow 18189/tcp  # XTM
sudo ufw allow 4130/tcp   # ALEO
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

UFW (Uncomplicated Firewall) is configured to:
- Allow SSH (port 22 by default)
- Deny all other incoming traffic
- Allow all outgoing traffic

Open additional ports only when needed.

## Maintenance

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
sudo journalctl -u pool-xmr-p2pool -f
```

### Backup

Important files to backup:
- `/opt/solo-pool/install-scripts/config.sh` - Your configuration
- `/opt/solo-pool/node/*/data/wallet*` - Any wallet files
- `/opt/solo-pool/pool/*/` - Pool configurations and logs

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

## License

MIT License - Use at your own risk. Solo mining is inherently high-variance.

## Disclaimer

Solo mining has extremely high variance. You may mine for extended periods without finding a block. This configuration is provided as-is without warranty. Always secure your wallet addresses and keep backups.
