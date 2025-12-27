#!/bin/bash
# =============================================================================
# Solopool Installer
# =============================================================================
# Usage:
#   git clone https://github.com/mattx86/solopool.git
#   cd solopool
#   cp config.sh.example config.sh
#   nano config.sh  # Edit configuration
#   sudo ./install.sh
#
# With custom mount point (set MOUNT_POINT in config.sh or use -m):
#   sudo ./install.sh -m /mnt/data
# =============================================================================

set -e

# Terminal colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Get script directory (where git repo was cloned)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Default values
DEFAULT_BASE_DIR="/opt/solopool"
MOUNT_POINT_ARG=""

# =============================================================================
# FUNCTIONS
# =============================================================================

log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $*"
}

log_error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERROR:${NC} $*" >&2
}

log_warn() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] WARNING:${NC} $*"
}

log_section() {
    echo ""
    echo -e "${BLUE}=============================================${NC}"
    echo -e "${BLUE} $*${NC}"
    echo -e "${BLUE}=============================================${NC}"
}

usage() {
    echo "Usage: $0 [-m|--mount PATH] [-h|--help]"
    echo ""
    echo "Options:"
    echo "  -m, --mount PATH    Use PATH as base directory instead of /opt/solopool"
    echo "                      PATH must be a valid mount point"
    echo "  -h, --help          Show this help message"
    echo ""
    echo "Prerequisites:"
    echo "  1. Clone the repository: git clone https://github.com/mattx86/solopool.git"
    echo "  2. Create config: cp config.sh.example config.sh"
    echo "  3. Edit config: nano config.sh"
    echo "  4. Run installer: sudo ./install.sh"
    echo ""
    exit 0
}

validate_mount_point() {
    local path="$1"

    # Check if path exists
    if [ ! -d "$path" ]; then
        log_error "Mount point '$path' does not exist"
        exit 1
    fi

    # Check if it's a mount point
    if mountpoint -q "$path" 2>/dev/null; then
        log "Validated: '$path' is a mount point"
    else
        log_warn "'$path' is not a mount point, using as regular directory"
    fi

    # Check if writable
    if ! touch "$path/.solopool_test" 2>/dev/null; then
        log_error "Mount point '$path' is not writable"
        exit 1
    fi
    rm -f "$path/.solopool_test"

    # Check available space (warn if < 100GB)
    local avail_gb
    avail_gb=$(df -BG "$path" 2>/dev/null | tail -1 | awk '{print $4}' | tr -d 'G')
    if [ -n "$avail_gb" ] && [ "$avail_gb" -lt 100 ] 2>/dev/null; then
        log_warn "Only ${avail_gb}GB available on $path (recommend 500GB+ for full nodes)"
    fi
}

# =============================================================================
# ARGUMENT PARSING
# =============================================================================

while [[ $# -gt 0 ]]; do
    case $1 in
        -m|--mount)
            MOUNT_POINT_ARG="$2"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        *)
            log_error "Unknown option: $1"
            usage
            ;;
    esac
done

# =============================================================================
# PRE-FLIGHT CHECKS
# =============================================================================

log_section "Solopool Installer"

# Check for root
if [ "$EUID" -ne 0 ]; then
    log_error "Please run as root: sudo ./install.sh"
    exit 1
fi

# Check for config.sh
if [ ! -f "${SCRIPT_DIR}/config.sh" ]; then
    log_error "config.sh not found!"
    echo ""
    echo "Please create your configuration file first:"
    echo "  cp config.sh.example config.sh"
    echo "  nano config.sh"
    echo ""
    exit 1
fi

# Source user config
log "Loading configuration from config.sh..."
source "${SCRIPT_DIR}/config.sh"

# =============================================================================
# DETERMINE BASE DIRECTORY
# =============================================================================

# Priority: command line arg > config file > default
if [ -n "$MOUNT_POINT_ARG" ]; then
    validate_mount_point "$MOUNT_POINT_ARG"
    BASE_DIR="$MOUNT_POINT_ARG"
elif [ -n "${MOUNT_POINT:-}" ]; then
    validate_mount_point "$MOUNT_POINT"
    BASE_DIR="$MOUNT_POINT"
else
    BASE_DIR="$DEFAULT_BASE_DIR"
fi

log "Base directory: $BASE_DIR"

# =============================================================================
# CREATE DIRECTORY STRUCTURE
# =============================================================================

log_section "Creating Directory Structure"

INSTALL_DIR="${BASE_DIR}/install"
BIN_DIR="${BASE_DIR}/bin"
NODE_DIR="${BASE_DIR}/node"
POOL_DIR="${BASE_DIR}/pool"
WALLET_DIR="${BASE_DIR}/wallet"
WEBUI_DIR="${BASE_DIR}/webui"
PAYMENTS_DIR="${BASE_DIR}/payments"

mkdir -p "$INSTALL_DIR"
mkdir -p "$BIN_DIR"

log "Created: $BASE_DIR"

# =============================================================================
# GENERATE RUNTIME CONFIG
# =============================================================================

log_section "Generating Runtime Configuration"

# Copy user config
cp "${SCRIPT_DIR}/config.sh" "${INSTALL_DIR}/config.sh"

# Append derived paths
cat >> "${INSTALL_DIR}/config.sh" << EOF

# =============================================================================
# DERIVED PATHS - Auto-generated by install.sh
# =============================================================================
SCRIPTS_BASE_URL="file://${INSTALL_DIR}"
BASE_DIR="${BASE_DIR}"
BIN_DIR="${BIN_DIR}"
INSTALL_DIR="${INSTALL_DIR}"
NODE_DIR="${NODE_DIR}"
POOL_DIR="${POOL_DIR}"
WALLET_DIR="${WALLET_DIR}"
WEBUI_DIR="${WEBUI_DIR}"
PAYMENTS_DIR="${PAYMENTS_DIR}"

# Node directories (using coin codes)
BTC_NODE_DIR="\${NODE_DIR}/btc"
BCH_NODE_DIR="\${NODE_DIR}/bch"
DGB_NODE_DIR="\${NODE_DIR}/dgb"
XMR_NODE_DIR="\${NODE_DIR}/xmr"
XTM_NODE_DIR="\${NODE_DIR}/xtm"
ALEO_NODE_DIR="\${NODE_DIR}/aleo"

# Legacy variable names (for compatibility during transition)
BITCOIN_DIR="\${BTC_NODE_DIR}"
BCHN_DIR="\${BCH_NODE_DIR}"
DIGIBYTE_DIR="\${DGB_NODE_DIR}"
MONERO_DIR="\${XMR_NODE_DIR}"
TARI_DIR="\${XTM_NODE_DIR}"

# Pool directories (using coin codes)
BTC_POOL_DIR="\${POOL_DIR}/btc"
BCH_POOL_DIR="\${POOL_DIR}/bch"
DGB_POOL_DIR="\${POOL_DIR}/dgb"
XMR_POOL_DIR="\${POOL_DIR}/xmr"
XTM_POOL_DIR="\${POOL_DIR}/xtm"
XMR_XTM_POOL_DIR="\${POOL_DIR}/xmr-xtm"
ALEO_POOL_DIR="\${POOL_DIR}/aleo"

# Legacy variable names (for compatibility during transition)
BTC_CKPOOL_DIR="\${BTC_POOL_DIR}"
BCH_CKPOOL_DIR="\${BCH_POOL_DIR}"
DGB_CKPOOL_DIR="\${DGB_POOL_DIR}"
XMR_MONERO_POOL_DIR="\${XMR_POOL_DIR}"
XTM_MINER_DIR="\${XTM_POOL_DIR}"
XMR_XTM_MERGE_DIR="\${XMR_XTM_POOL_DIR}"

# Wallet directories
XMR_WALLET_DIR="\${WALLET_DIR}/xmr"
XTM_WALLET_DIR="\${WALLET_DIR}/xtm"

# CKPool socket directories (for API communication with WebUI)
BTC_CKPOOL_SOCKET_DIR="/tmp/ckpool-btc"
BCH_CKPOOL_SOCKET_DIR="/tmp/ckpool-bch"
DGB_CKPOOL_SOCKET_DIR="/tmp/ckpool-dgb"

# Backup directory
BACKUP_DIR="\${BASE_DIR}/backups"

# Log file for installation
LOG_FILE="\${INSTALL_DIR}/install.log"

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================
log() {
    echo "[\$(date '+%Y-%m-%d %H:%M:%S')] \$*" | tee -a "\${LOG_FILE}"
}

log_error() {
    echo "[\$(date '+%Y-%m-%d %H:%M:%S')] ERROR: \$*" | tee -a "\${LOG_FILE}" >&2
}

log_success() {
    echo "[\$(date '+%Y-%m-%d %H:%M:%S')] SUCCESS: \$*" | tee -a "\${LOG_FILE}"
}

run_cmd() {
    "\$@" 2>&1 | tee -a "\${LOG_FILE}"
}

# Validation function
validate_config() {
    local errors=0
    if [ -z "\${BASE_DIR:-}" ]; then
        echo "ERROR: BASE_DIR not defined" >&2
        ((errors++))
    fi
    if [ -z "\${POOL_USER:-}" ]; then
        echo "ERROR: POOL_USER not defined" >&2
        ((errors++))
    fi
    return \$errors
}

# Mark that config was successfully loaded
CONFIG_LOADED="true"
EOF

chmod 600 "${INSTALL_DIR}/config.sh"
log "Generated: ${INSTALL_DIR}/config.sh"

# =============================================================================
# COPY INSTALL SCRIPTS AND TEMPLATES
# =============================================================================

log_section "Copying Install Scripts"

# Copy install scripts
cp -r "${SCRIPT_DIR}/install/"* "${INSTALL_DIR}/"
chmod +x "${INSTALL_DIR}/"*.sh 2>/dev/null || true

log "Copied install scripts to ${INSTALL_DIR}/"

# =============================================================================
# RUN INSTALL SCRIPTS
# =============================================================================

log_section "Running Installation Scripts"

cd "$INSTALL_DIR"

# Script execution order
SCRIPTS=(
    "01-system-update.sh"
    "02-cis-hardening.sh"
    "03-ufw-setup.sh"
    "04-user-setup.sh"
    "05-install-dependencies.sh"
    "10-install-bitcoin.sh"
    "11-install-bch.sh"
    "12-install-digibyte.sh"
    "13-install-monero.sh"
    "14-install-tari.sh"
    "15-install-aleo.sh"
    "16-install-webui.sh"
    "17-install-payments.sh"
    "20-configure-services.sh"
    "99-finalize.sh"
)

for script in "${SCRIPTS[@]}"; do
    if [ -f "$script" ]; then
        log_section "Running: $script"
        ./"$script"
        log "Completed: $script"
    else
        log_warn "Script not found: $script (skipping)"
    fi
done

# =============================================================================
# INSTALLATION COMPLETE
# =============================================================================

log_section "Installation Complete!"

echo ""
echo -e "${GREEN}Solopool has been installed successfully!${NC}"
echo ""
echo "Base directory:  $BASE_DIR"
echo "Configuration:   ${INSTALL_DIR}/config.sh"
echo "Management:      ${BIN_DIR}/"
echo ""
echo "Next steps:"
echo "  1. Wait for blockchain sync (check with: ${BIN_DIR}/sync-status.sh)"
echo "  2. Switch to production mode: ${BIN_DIR}/switch-mode.sh production"
echo "  3. Access WebUI: https://YOUR_SERVER_IP:8443"
echo ""
echo "Credentials are stored in: ${BASE_DIR}/.credentials"
echo ""
