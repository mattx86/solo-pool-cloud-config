#!/bin/bash
# =============================================================================
# 03-ufw-setup.sh
# UFW Firewall Configuration
# =============================================================================

set -e

# Source configuration
source /opt/solo-pool/config.sh

log "Configuring UFW firewall..."

# Install UFW if not present
run_cmd apt-get -y install ufw

# Reset UFW to defaults
log "Resetting UFW to defaults..."
run_cmd ufw --force reset

# Set default policies
log "Setting default policies (deny incoming, allow outgoing)..."
run_cmd ufw default deny incoming
run_cmd ufw default allow outgoing

# Allow SSH
log "Allowing SSH on port ${SSH_PORT}..."
run_cmd ufw allow ${SSH_PORT}/tcp comment 'SSH'

# Enable UFW
log "Enabling UFW..."
run_cmd ufw --force enable

# Show status
log "UFW Status:"
run_cmd ufw status verbose

log_success "UFW firewall configured - only SSH (port ${SSH_PORT}) is allowed"
log "To open additional ports later, use: sudo ufw allow <port>/tcp"
