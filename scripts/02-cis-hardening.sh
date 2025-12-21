#!/bin/bash
# =============================================================================
# 02-cis-hardening.sh
# CIS Ubuntu 24.04 Hardening
#
# Applies CIS benchmarks where applicable for a mining pool server.
# Some controls are intentionally skipped to allow pool operation.
# =============================================================================

set -e

# Source configuration
source /opt/solo-pool/config.sh

log "Applying CIS Ubuntu 24.04 hardening..."

# =============================================================================
# 1. FILESYSTEM CONFIGURATION
# =============================================================================
log "1. Filesystem hardening..."

# 1.1 Disable unused filesystems
log "  Disabling unused filesystems..."
cat > /etc/modprobe.d/cis-filesystems.conf << 'EOF'
# CIS 1.1.1.x - Disable unused filesystems
install cramfs /bin/true
install freevxfs /bin/true
install jffs2 /bin/true
install hfs /bin/true
install hfsplus /bin/true
install squashfs /bin/true
install udf /bin/true
install vfat /bin/true
EOF

# 1.2 Configure /tmp
log "  Configuring /tmp mount options..."
if ! grep -q "^tmpfs /tmp" /etc/fstab; then
    echo "tmpfs /tmp tmpfs defaults,rw,nosuid,nodev,noexec,relatime,size=2G 0 0" >> /etc/fstab
fi

# 1.3 Configure /var/tmp
log "  Configuring /var/tmp..."
if ! grep -q "/var/tmp" /etc/fstab; then
    echo "tmpfs /var/tmp tmpfs defaults,rw,nosuid,nodev,noexec,relatime,size=1G 0 0" >> /etc/fstab
fi

# 1.4 Configure /dev/shm
log "  Configuring /dev/shm..."
if ! grep -q "/dev/shm" /etc/fstab; then
    echo "tmpfs /dev/shm tmpfs defaults,rw,nosuid,nodev,noexec,relatime 0 0" >> /etc/fstab
fi

# =============================================================================
# 2. SERVICES
# =============================================================================
log "2. Removing/disabling unnecessary services..."

# Disable unnecessary services
SERVICES_TO_DISABLE=(
    "avahi-daemon"
    "cups"
    "isc-dhcp-server"
    "slapd"
    "nfs-server"
    "rpcbind"
    "rsync"
    "snmpd"
    "squid"
    "vsftpd"
    "apache2"
    "nginx"
    "dovecot"
    "smbd"
    "nmbd"
)

for svc in "${SERVICES_TO_DISABLE[@]}"; do
    if systemctl is-enabled "$svc" 2>/dev/null | grep -q "enabled"; then
        log "  Disabling $svc..."
        systemctl stop "$svc" 2>/dev/null || true
        systemctl disable "$svc" 2>/dev/null || true
    fi
done

# Remove unnecessary packages
log "  Removing unnecessary packages..."
PACKAGES_TO_REMOVE=(
    "nis"
    "rsh-client"
    "rsh-server"
    "talk"
    "telnet"
    "ldap-utils"
    "xinetd"
)

for pkg in "${PACKAGES_TO_REMOVE[@]}"; do
    if dpkg -l | grep -q "^ii  $pkg "; then
        apt-get -y remove "$pkg" >/dev/tty1 2>&1 || true
    fi
done

# =============================================================================
# 3. NETWORK CONFIGURATION
# =============================================================================
log "3. Network hardening (sysctl)..."

cat > /etc/sysctl.d/99-cis-hardening.conf << 'EOF'
# CIS Network Hardening

# 3.1 Disable IP forwarding
net.ipv4.ip_forward = 0
net.ipv6.conf.all.forwarding = 0

# 3.2 Packet redirect sending
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0

# 3.3 Source routed packets
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv6.conf.all.accept_source_route = 0
net.ipv6.conf.default.accept_source_route = 0

# 3.4 ICMP redirects
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0

# 3.5 Secure ICMP redirects
net.ipv4.conf.all.secure_redirects = 0
net.ipv4.conf.default.secure_redirects = 0

# 3.6 Log suspicious packets
net.ipv4.conf.all.log_martians = 1
net.ipv4.conf.default.log_martians = 1

# 3.7 Ignore broadcast ICMP requests
net.ipv4.icmp_echo_ignore_broadcasts = 1

# 3.8 Ignore bogus ICMP responses
net.ipv4.icmp_ignore_bogus_error_responses = 1

# 3.9 Enable reverse path filtering
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1

# 3.10 Enable TCP SYN cookies
net.ipv4.tcp_syncookies = 1

# 3.11 IPv6 router advertisements
net.ipv6.conf.all.accept_ra = 0
net.ipv6.conf.default.accept_ra = 0

# Additional hardening
kernel.randomize_va_space = 2
kernel.dmesg_restrict = 1
kernel.kptr_restrict = 2
kernel.yama.ptrace_scope = 1
fs.suid_dumpable = 0

# Performance tuning for high connection servers (pools)
net.core.somaxconn = 65535
net.core.netdev_max_backlog = 65535
net.ipv4.tcp_max_syn_backlog = 65535
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_keepalive_time = 300
net.ipv4.tcp_keepalive_probes = 5
net.ipv4.tcp_keepalive_intvl = 15
EOF

# Apply sysctl settings
sysctl -p /etc/sysctl.d/99-cis-hardening.conf >/dev/tty1 2>&1 || true

# =============================================================================
# 4. SSH HARDENING
# =============================================================================
log "4. SSH hardening..."

# Backup original config
cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak

cat > /etc/ssh/sshd_config.d/99-cis-hardening.conf << EOF
# CIS SSH Hardening

# Protocol and port
Protocol 2
Port ${SSH_PORT}

# Logging
LogLevel VERBOSE

# Authentication
LoginGraceTime 60
PermitRootLogin prohibit-password
StrictModes yes
MaxAuthTries 4
MaxSessions 10

# Disable unused auth methods
HostbasedAuthentication no
PermitEmptyPasswords no
ChallengeResponseAuthentication no

# PAM
UsePAM yes

# Disable tunneling and forwarding
AllowAgentForwarding no
AllowTcpForwarding no
X11Forwarding no
PermitTunnel no

# Banner
Banner /etc/issue.net

# Environment
PermitUserEnvironment no

# Timeouts
ClientAliveInterval 300
ClientAliveCountMax 3

# Ciphers and MACs (strong only)
Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com,aes256-ctr,aes192-ctr,aes128-ctr
MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com,hmac-sha2-512,hmac-sha2-256
KexAlgorithms curve25519-sha256,curve25519-sha256@libssh.org,ecdh-sha2-nistp521,ecdh-sha2-nistp384,ecdh-sha2-nistp256,diffie-hellman-group-exchange-sha256
EOF

# Create warning banner
cat > /etc/issue.net << 'EOF'
***************************************************************************
                            AUTHORIZED ACCESS ONLY
This system is for authorized use only. Unauthorized access is prohibited.
All activities may be monitored and recorded.
***************************************************************************
EOF

# Restart SSH (but be careful not to lock ourselves out)
log "  Restarting SSH..."
systemctl restart sshd >/dev/tty1 2>&1 || systemctl restart ssh >/dev/tty1 2>&1 || true

# =============================================================================
# 5. USER ACCOUNTS AND ENVIRONMENT
# =============================================================================
log "5. User account hardening..."

# 5.1 Password policies
log "  Configuring password policies..."

# Install libpam-pwquality
apt-get -y install libpam-pwquality >/dev/tty1 2>&1 || true

# Configure password quality
cat > /etc/security/pwquality.conf << 'EOF'
# Password quality requirements
minlen = 14
dcredit = -1
ucredit = -1
ocredit = -1
lcredit = -1
minclass = 4
maxrepeat = 3
maxclassrepeat = 4
gecoscheck = 1
EOF

# 5.2 Configure login.defs
log "  Configuring login.defs..."
sed -i 's/^PASS_MAX_DAYS.*/PASS_MAX_DAYS   365/' /etc/login.defs
sed -i 's/^PASS_MIN_DAYS.*/PASS_MIN_DAYS   1/' /etc/login.defs
sed -i 's/^PASS_WARN_AGE.*/PASS_WARN_AGE   7/' /etc/login.defs

# 5.3 Set default umask
log "  Setting default umask..."
echo "umask 027" >> /etc/profile.d/cis-umask.sh
chmod +x /etc/profile.d/cis-umask.sh

# 5.4 Lock inactive accounts
log "  Configuring inactive account lockout..."
useradd -D -f 30

# 5.5 Restrict root login to console only
log "  Restricting root login..."
echo "tty1" > /etc/securetty

# =============================================================================
# 6. FILE PERMISSIONS
# =============================================================================
log "6. File permission hardening..."

# Critical files
chmod 644 /etc/passwd
chmod 644 /etc/group
chmod 600 /etc/shadow
chmod 600 /etc/gshadow
chmod 600 /etc/ssh/sshd_config

# Remove world-writable files from /etc
find /etc -type f -perm -0002 -exec chmod o-w {} \; 2>/dev/null || true

# Set sticky bit on world-writable directories
find / -xdev -type d -perm -0002 ! -perm -1000 -exec chmod +t {} \; 2>/dev/null || true

# =============================================================================
# 7. AUDIT CONFIGURATION
# =============================================================================
log "7. Configuring audit daemon..."

apt-get -y install auditd audispd-plugins >/dev/tty1 2>&1 || true

cat > /etc/audit/rules.d/cis.rules << 'EOF'
# CIS Audit Rules

# Remove any existing rules
-D

# Buffer Size
-b 8192

# Failure Mode
-f 1

# Monitor login/logout events
-w /var/log/lastlog -p wa -k logins
-w /var/run/faillock -p wa -k logins

# Monitor session initiation
-w /var/run/utmp -p wa -k session
-w /var/log/wtmp -p wa -k logins
-w /var/log/btmp -p wa -k logins

# Monitor sudo usage
-w /etc/sudoers -p wa -k scope
-w /etc/sudoers.d -p wa -k scope

# Monitor changes to system files
-w /etc/passwd -p wa -k identity
-w /etc/group -p wa -k identity
-w /etc/shadow -p wa -k identity
-w /etc/gshadow -p wa -k identity
-w /etc/security/opasswd -p wa -k identity

# Monitor network configuration changes
-w /etc/hosts -p wa -k network
-w /etc/network -p wa -k network

# Monitor cron
-w /etc/crontab -p wa -k cron
-w /etc/cron.d -p wa -k cron
-w /etc/cron.daily -p wa -k cron
-w /etc/cron.hourly -p wa -k cron
-w /etc/cron.monthly -p wa -k cron
-w /etc/cron.weekly -p wa -k cron

# Monitor SSH config
-w /etc/ssh/sshd_config -p wa -k sshd

# Make the configuration immutable
-e 2
EOF

# Enable and start auditd
systemctl enable auditd >/dev/tty1 2>&1 || true
systemctl restart auditd >/dev/tty1 2>&1 || true

# =============================================================================
# 8. ADDITIONAL HARDENING
# =============================================================================
log "8. Additional hardening..."

# 8.1 Disable core dumps
log "  Disabling core dumps..."
echo "* hard core 0" >> /etc/security/limits.conf
echo "fs.suid_dumpable = 0" >> /etc/sysctl.d/99-cis-hardening.conf

# 8.2 Configure systemd coredump
mkdir -p /etc/systemd/coredump.conf.d
cat > /etc/systemd/coredump.conf.d/disable.conf << 'EOF'
[Coredump]
Storage=none
ProcessSizeMax=0
EOF

# 8.3 Disable USB storage (optional - uncomment if not needed)
# echo "install usb-storage /bin/true" >> /etc/modprobe.d/cis-filesystems.conf

# 8.4 Configure log rotation
cat > /etc/logrotate.d/syslog << 'EOF'
/var/log/syslog
/var/log/mail.info
/var/log/mail.warn
/var/log/mail.err
/var/log/mail.log
/var/log/daemon.log
/var/log/kern.log
/var/log/auth.log
/var/log/user.log
/var/log/lpr.log
/var/log/cron.log
/var/log/debug
/var/log/messages
{
    rotate 7
    daily
    missingok
    notifempty
    compress
    delaycompress
    sharedscripts
    postrotate
        /usr/lib/rsyslog/rsyslog-rotate
    endscript
}
EOF

# 8.5 Disable ICMP timestamp responses (not in standard sysctl)
iptables -A INPUT -p icmp --icmp-type timestamp-request -j DROP 2>/dev/null || true
iptables -A OUTPUT -p icmp --icmp-type timestamp-reply -j DROP 2>/dev/null || true

# =============================================================================
# 9. SKIPPED CONTROLS (Required for Pool Operation)
# =============================================================================
log "9. Noting skipped controls..."
log "  The following CIS controls are skipped for pool operation:"
log "    - IPv6 disable: May be needed for some networks"
log "    - Strict TCP wrappers: Pools need to accept connections"
log "    - Mandatory access control: May interfere with pool software"
log "    - Aide/Tripwire: Can be added later if needed"

log_success "CIS hardening applied"
log "Note: Some settings require reboot to take full effect"
