#!/usr/bin/env bash

# Barrett Debian Setup Script
# This script imperatively sets up a Barrett VPN torrent server on Debian
# Replicates the NixOS configuration but runs everything ONLY once (idempotent)

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# State directory to track completed steps
STATE_DIR="/var/lib/barrett-setup"
SETUP_USER="danny"

# Helper functions
info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root"
        exit 1
    fi
}

mark_complete() {
    local step="$1"
    mkdir -p "$STATE_DIR"
    touch "$STATE_DIR/$step"
    success "Completed: $step"
}

is_complete() {
    local step="$1"
    [[ -f "$STATE_DIR/$step" ]]
}

skip_if_complete() {
    local step="$1"
    if is_complete "$step"; then
        warning "Skipping $step (already completed)"
        return 0
    fi
    return 1
}

# ============================================================================
# STEP 1: System Base Setup
# ============================================================================
setup_base_system() {
    local step="base_system"
    skip_if_complete "$step" && return

    info "Setting up base system..."

    # Update package lists
    apt-get update

    # Install essential packages
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
        curl wget git vim bat btop cifs-utils gnupg \
        fish zoxide ripgrep fd-find fzf eza \
        openssh-server sudo build-essential \
        python3 python3-pip python3-venv \
        avahi-daemon libnss-mdns \
        network-manager

    # Set hostname
    hostnamectl set-hostname barrett

    mark_complete "$step"
}

# ============================================================================
# STEP 2: User Setup
# ============================================================================
setup_user() {
    local step="user_setup"
    skip_if_complete "$step" && return

    info "Setting up user: $SETUP_USER..."

    # Create user if doesn't exist
    if ! id -u "$SETUP_USER" &>/dev/null; then
        useradd -m -s /usr/bin/fish -G sudo,users "$SETUP_USER"
        info "User $SETUP_USER created"
    else
        # Update shell and groups
        usermod -s /usr/bin/fish -a -G sudo,users "$SETUP_USER"
        info "User $SETUP_USER updated"
    fi

    # Set up SSH directory and authorized keys
    mkdir -p "/home/$SETUP_USER/.ssh"
    cat > "/home/$SETUP_USER/.ssh/authorized_keys" << 'EOF'
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMJKTm63zFmYfGauCBlUWq7lvHFq+NVPT5RqIfjLM7MN danny@solivan.dev
EOF
    chmod 700 "/home/$SETUP_USER/.ssh"
    chmod 600 "/home/$SETUP_USER/.ssh/authorized_keys"
    chown -R "$SETUP_USER:$SETUP_USER" "/home/$SETUP_USER/.ssh"

    mark_complete "$step"
}

# ============================================================================
# STEP 3: SSH Configuration
# ============================================================================
setup_ssh() {
    local step="ssh_config"
    skip_if_complete "$step" && return

    info "Configuring SSH..."

    # Backup original config if not already backed up
    if [[ ! -f /etc/ssh/sshd_config.backup ]]; then
        cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup
    fi

    # Apply secure SSH settings
    cat > /etc/ssh/sshd_config.d/barrett.conf << 'EOF'
# Barrett SSH Configuration
PermitRootLogin no
PasswordAuthentication yes
PubkeyAuthentication yes
KbdInteractiveAuthentication no
ChallengeResponseAuthentication no
MaxAuthTries 3
ClientAliveInterval 60
ClientAliveCountMax 3
X11Forwarding no
AllowTcpForwarding yes
GatewayPorts no
LogLevel INFO
EOF

    # Enable and restart SSH
    systemctl enable ssh || true
    systemctl restart ssh || true

    mark_complete "$step"
}

# ============================================================================
# STEP 4: NordVPN Setup
# ============================================================================
setup_nordvpn() {
    local step="nordvpn_setup"
    skip_if_complete "$step" && return

    info "Installing NordVPN..."

    # Download and install NordVPN using official install script
    if ! command -v nordvpn &>/dev/null; then
        sh <(curl -sSf https://downloads.nordcdn.com/apps/linux/install.sh)
    fi

    # Add user to nordvpn group
    usermod -aG nordvpn "$SETUP_USER"

    # Unmask the service (it's often masked after install)
    info "Unmasking NordVPN service..."
    systemctl unmask nordvpn.service
    systemctl unmask nordvpn

    # Reload systemd to pick up the unmask
    systemctl daemon-reload

    # Enable and start NordVPN daemon
    systemctl enable nordvpn
    systemctl restart nordvpn 2>/dev/null || systemctl start nordvpn

    # Wait for daemon to be ready
    sleep 5

    # Check if token file exists
    if [[ -f /root/.nordvpn-token ]]; then
        info "Configuring NordVPN with token..."
        TOKEN=$(cat /root/.nordvpn-token)

        # Login with token if not already logged in
        if ! nordvpn account &>/dev/null; then
            nordvpn login --token "$TOKEN" || warning "NordVPN login failed, may already be logged in"
        else
            info "Already logged in to NordVPN"
        fi

        # Configure settings (these are idempotent)
        nordvpn set killswitch on || true
        nordvpn set technology NordLynx || true
        nordvpn set lan-discovery enable || true
        nordvpn set dns 103.86.96.100 103.86.99.100 || true
        nordvpn set autoconnect on || true

        # Connect to P2P server if not already connected
        if ! nordvpn status | grep -q "Status: Connected"; then
            nordvpn connect p2p || warning "Failed to connect to VPN"
        else
            info "Already connected to VPN"
        fi
    else
        warning "NordVPN token not found at /root/.nordvpn-token"
        warning "Please create the file with your token and run: nordvpn login --token \$(cat /root/.nordvpn-token)"
    fi

    mark_complete "$step"
}

# ============================================================================
# STEP 5: Network Drives (Titan Mount)
# ============================================================================
setup_network_drives() {
    local step="network_drives"
    skip_if_complete "$step" && return

    info "Setting up Titan network mount..."

    # Create mount point
    mkdir -p /mnt/titan

    # Check if credentials file exists
    if [[ ! -f /root/.titan-credentials ]]; then
        warning "Titan credentials not found at /root/.titan-credentials"
        warning "Please create the file with the following format:"
        cat << 'EOF'
username=YOUR_USERNAME
password=YOUR_PASSWORD
domain=WORKGROUP
EOF
        warning "Then run: chmod 600 /root/.titan-credentials"
        mark_complete "$step"
        return
    fi

    # Create systemd mount unit
    cat > /etc/systemd/system/mnt-titan.mount << 'EOF'
[Unit]
Description=Mount Titan network share
After=network-online.target
Wants=network-online.target

[Mount]
What=//192.168.1.167/titan
Where=/mnt/titan
Type=cifs
Options=credentials=/root/.titan-credentials,uid=1000,gid=100,iocharset=utf8,nofail,_netdev,x-systemd.automount,x-systemd.mount-timeout=10

[Install]
WantedBy=multi-user.target
EOF

    # Create systemd automount unit
    cat > /etc/systemd/system/mnt-titan.automount << 'EOF'
[Unit]
Description=Automount Titan network share

[Automount]
Where=/mnt/titan
TimeoutIdleSec=60
DirectoryMode=0755

[Install]
WantedBy=multi-user.target
EOF

    # Enable automount
    systemctl daemon-reload
    systemctl enable mnt-titan.automount || true
    systemctl restart mnt-titan.automount || systemctl start mnt-titan.automount

    # Create downloads directory
    mkdir -p /mnt/titan/downloads
    chown -R "$SETUP_USER:users" /mnt/titan/downloads || true

    mark_complete "$step"
}

# ============================================================================
# STEP 6: qBittorrent Setup
# ============================================================================
setup_qbittorrent() {
    local step="qbittorrent_setup"
    skip_if_complete "$step" && return

    info "Installing and configuring qBittorrent..."

    # Install qBittorrent-nox
    apt-get install -y qbittorrent-nox

    # Create configuration directories
    mkdir -p /var/lib/torrent/qbittorrent/qBittorrent/{config,cache,data/logs}
    mkdir -p /mnt/titan/downloads
    chown -R "$SETUP_USER:users" /var/lib/torrent

    # Check if password hash file exists
    if [[ ! -f /root/.qbittorrent-password-hash ]]; then
        warning "qBittorrent password hash not found at /root/.qbittorrent-password-hash"
        warning "Generate one with: echo -n 'your_password' | md5sum | awk '{print \$1}'"
        warning "Or use the PBKDF2 hash from your SOPS secrets"
    fi

    # Create qBittorrent systemd service
    cat > /etc/systemd/system/qbittorrent.service << EOF
[Unit]
Description=qBittorrent-nox service
After=network.target mnt-titan.mount
Requires=mnt-titan.mount

[Service]
Type=simple
User=$SETUP_USER
Group=users
ExecStartPre=/bin/bash -c 'mkdir -p /var/lib/torrent/qbittorrent/qBittorrent/{config,data/logs}'
ExecStart=/usr/bin/qbittorrent-nox \\
    --confirm-legal-notice \\
    --webui-port=8112 \\
    --profile=/var/lib/torrent/qbittorrent \\
    --save-path=/mnt/titan/downloads
Restart=on-failure
RestartSec=10s
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF

    # Generate qBittorrent configuration
    if [[ -f /root/.qbittorrent-password-hash ]]; then
        HASH=$(cat /root/.qbittorrent-password-hash)

        cat > /var/lib/torrent/qbittorrent/qBittorrent/config/qBittorrent.conf << QBCONF
[Application]
FileLogger\\Enabled=true
FileLogger\\Path=/var/lib/torrent/qbittorrent/qBittorrent/data/logs

[BitTorrent]
Session\\AddTorrentStopped=false
Session\\AnonymousMode=true
Session\\DefaultSavePath=/mnt/titan/downloads
Session\\DHTEnabled=false
Session\\Encryption=1
Session\\GlobalMaxRatio=2.0
Session\\GlobalUPSpeedLimit=100
Session\\GlobalDLSpeedLimit=0
Session\\LSDEnabled=false
Session\\MaxActiveDownloads=3
Session\\MaxConnections=100
Session\\MaxConnectionsPerTorrent=50
Session\\PeXEnabled=false
Session\\Port=6881
Session\\RequireEncryption=true
Session\\ShareLimitAction=Stop
Session\\QueueingSystemEnabled=true

[LegalNotice]
Accepted=true

[Preferences]
WebUI\\CSRFProtection=false
WebUI\\LocalHostAuth=false
WebUI\\Password_PBKDF2="@ByteArray($HASH)"
WebUI\\Port=8112
WebUI\\Username=$SETUP_USER

[RSS]
AutoDownloader\\DownloadRepacks=true
QBCONF

        chown "$SETUP_USER:users" /var/lib/torrent/qbittorrent/qBittorrent/config/qBittorrent.conf
        chmod 600 /var/lib/torrent/qbittorrent/qBittorrent/config/qBittorrent.conf
    fi

    # Configure firewall (if ufw is installed)
    if command -v ufw &>/dev/null; then
        ufw allow 8112/tcp || true
        ufw allow 6881/tcp || true
        ufw allow 6881/udp || true
    fi

    # Enable and start service
    systemctl daemon-reload
    systemctl enable qbittorrent || true
    systemctl restart qbittorrent || systemctl start qbittorrent

    mark_complete "$step"
}

# ============================================================================
# STEP 7: Autoremove-torrents Setup
# ============================================================================
setup_autoremove_torrents() {
    local step="autoremove_torrents"
    skip_if_complete "$step" && return

    info "Installing autoremove-torrents..."

    # Install Python package
    pip3 install --break-system-packages autoremove-torrents

    # Create config directory
    mkdir -p /etc/autoremove-torrents
    mkdir -p /var/log/autoremove-torrents
    chown "$SETUP_USER:users" /var/log/autoremove-torrents

    # Check if password file exists
    if [[ ! -f /root/.qbittorrent-password ]]; then
        warning "qBittorrent password not found at /root/.qbittorrent-password"
        warning "Please create the file with your plain text password"
        mark_complete "$step"
        return
    fi

    # Generate config with password
    PASSWORD=$(cat /root/.qbittorrent-password)
    cat > /etc/autoremove-torrents/config.yml << ARTCONF
qbittorrent_task:
  client: qbittorrent
  host: http://127.0.0.1:8112
  username: $SETUP_USER
  password: "$PASSWORD"
  strategies:
    minimal_seed_strategy:
      remove: 'seeding_time > 600'
      delete_data: true
ARTCONF

    chmod 600 /etc/autoremove-torrents/config.yml

    # Create systemd service
    cat > /etc/systemd/system/autoremove-torrents.service << 'EOF'
[Unit]
Description=Remove torrents automatically
After=qbittorrent.service
Wants=qbittorrent.service

[Service]
Type=oneshot
User=root
ExecStart=/usr/local/bin/autoremove-torrents --conf=/etc/autoremove-torrents/config.yml --log=/var/log/autoremove-torrents
EOF

    # Create systemd timer
    cat > /etc/systemd/system/autoremove-torrents.timer << 'EOF'
[Unit]
Description=Run autoremove-torrents every 5 minutes

[Timer]
OnBootSec=5min
OnUnitActiveSec=5min
Unit=autoremove-torrents.service

[Install]
WantedBy=timers.target
EOF

    # Enable timer
    systemctl daemon-reload
    systemctl enable autoremove-torrents.timer || true
    systemctl restart autoremove-torrents.timer || systemctl start autoremove-torrents.timer

    mark_complete "$step"
}

# ============================================================================
# STEP 8: IP Filter Setup
# ============================================================================
setup_ipfilter() {
    local step="ipfilter_setup"
    skip_if_complete "$step" && return

    info "Setting up qBittorrent IP filter..."

    # Create cache directory
    mkdir -p /var/cache/qbittorrent-ipfilter
    chown "$SETUP_USER:users" /var/cache/qbittorrent-ipfilter

    # Create IP filter update script
    cat > /usr/local/bin/update-qbittorrent-ipfilter << 'IPFILTER_SCRIPT'
#!/usr/bin/env bash
set -euo pipefail

CACHE_DIR="/var/cache/qbittorrent-ipfilter"
OUTPUT_FILE="/var/lib/torrent/qbittorrent/qBittorrent/data/ipfilter.dat"
TEMP_FILE=$(mktemp)
BLOCKLIST_DIR="$CACHE_DIR/blocklists"

mkdir -p "$BLOCKLIST_DIR"
cd "$BLOCKLIST_DIR"

echo "Starting IP filter update..."

# Download blocklists
curl -sSL "http://list.iblocklist.com/?list=ydxerpxkpcfqjaybcssw&fileformat=p2p&archiveformat=gz" -o "level1.gz" || true
curl -sSL "https://www.biglybt.com/blocklist/level1.gz" -o "biglybt.gz" || true

echo "Processing blocklists..."

# Extract and process
for file in *.gz; do
    [[ -f "$file" ]] && zcat "$file" | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' >> "$TEMP_FILE" || true
done

# Sort and deduplicate
sort -u "$TEMP_FILE" -o "$TEMP_FILE.sorted"
FINAL_COUNT=$(wc -l < "$TEMP_FILE.sorted" || echo 0)

# Create IP filter file
{
    echo "# qBittorrent IP Filter"
    echo "# Updated: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
    echo "# Total unique IPs: $FINAL_COUNT"
    echo ""

    while IFS= read -r ip; do
        echo "$ip-$ip,1"
    done < "$TEMP_FILE.sorted"
} > "$OUTPUT_FILE"

chown danny:users "$OUTPUT_FILE"
rm -f "$TEMP_FILE" "$TEMP_FILE.sorted"

echo "IP filter update complete! Total IPs: $FINAL_COUNT"
IPFILTER_SCRIPT

    chmod +x /usr/local/bin/update-qbittorrent-ipfilter

    # Create systemd service
    cat > /etc/systemd/system/qbittorrent-ipfilter-update.service << 'EOF'
[Unit]
Description=Update qBittorrent IP filters
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
User=danny
ExecStart=/usr/local/bin/update-qbittorrent-ipfilter
EOF

    # Create systemd timer
    cat > /etc/systemd/system/qbittorrent-ipfilter-update.timer << 'EOF'
[Unit]
Description=Update qBittorrent IP filters every 24 hours

[Timer]
OnBootSec=5min
OnUnitActiveSec=24h
Unit=qbittorrent-ipfilter-update.service

[Install]
WantedBy=timers.target
EOF

    # Enable timer
    systemctl daemon-reload
    systemctl enable qbittorrent-ipfilter-update.timer || true
    systemctl restart qbittorrent-ipfilter-update.timer || systemctl start qbittorrent-ipfilter-update.timer

    # Run initial update (may already be running)
    systemctl start qbittorrent-ipfilter-update.service || true

    mark_complete "$step"
}

# ============================================================================
# STEP 9: Network Configuration
# ============================================================================
setup_network() {
    local step="network_config"
    skip_if_complete "$step" && return

    info "Configuring network..."

    # Enable NetworkManager
    systemctl enable NetworkManager || true
    systemctl restart NetworkManager || systemctl start NetworkManager

    # Enable mDNS/Avahi
    systemctl enable avahi-daemon || true
    systemctl restart avahi-daemon || systemctl start avahi-daemon

    mark_complete "$step"
}

# ============================================================================
# STEP 10: Final Configuration
# ============================================================================
final_setup() {
    local step="final_setup"
    skip_if_complete "$step" && return

    info "Performing final setup..."

    # Enable and configure firewall
    if ! command -v ufw &>/dev/null; then
        apt-get install -y ufw
    fi

    ufw --force enable || true
    ufw allow ssh || true
    ufw allow 8112/tcp || true  # qBittorrent Web UI

    # Set timezone
    timedatectl set-timezone America/Los_Angeles || true

    mark_complete "$step"
    success "Barrett setup complete!"
}

# ============================================================================
# Print Instructions
# ============================================================================
print_instructions() {
    echo ""
    echo "============================================================================"
    echo -e "${GREEN}Barrett Setup Complete!${NC}"
    echo "============================================================================"
    echo ""
    echo "Before the system is fully functional, you need to manually set up secrets:"
    echo ""
    echo "1. NordVPN Token:"
    echo "   sudo bash -c 'echo \"YOUR_TOKEN\" > /root/.nordvpn-token'"
    echo "   chmod 600 /root/.nordvpn-token"
    echo ""
    echo "2. Titan Network Drive Credentials:"
    echo "   sudo bash -c 'cat > /root/.titan-credentials << EOF"
    echo "   username=YOUR_USERNAME"
    echo "   password=YOUR_PASSWORD"
    echo "   domain=WORKGROUP"
    echo "   EOF'"
    echo "   chmod 600 /root/.titan-credentials"
    echo ""
    echo "3. qBittorrent Password (plain text for autoremove-torrents):"
    echo "   sudo bash -c 'echo \"YOUR_PASSWORD\" > /root/.qbittorrent-password'"
    echo "   chmod 600 /root/.qbittorrent-password"
    echo ""
    echo "4. qBittorrent Password Hash (PBKDF2 for qBittorrent WebUI):"
    echo "   sudo bash -c 'echo \"YOUR_PBKDF2_HASH\" > /root/.qbittorrent-password-hash'"
    echo "   chmod 600 /root/.qbittorrent-password-hash"
    echo ""
    echo "Then restart affected services:"
    echo "   sudo systemctl restart nordvpn"
    echo "   sudo systemctl restart mnt-titan.automount"
    echo "   sudo systemctl restart qbittorrent"
    echo ""
    echo "Access qBittorrent Web UI at: http://barrett.local:8112"
    echo "Username: $SETUP_USER"
    echo ""
    echo "To check service status:"
    echo "   systemctl status nordvpn"
    echo "   systemctl status qbittorrent"
    echo "   systemctl status autoremove-torrents.timer"
    echo "   systemctl status qbittorrent-ipfilter-update.timer"
    echo "   nordvpn status"
    echo ""
    echo "============================================================================"
}

# ============================================================================
# Main Execution
# ============================================================================
main() {
    check_root

    info "Starting Barrett Debian setup..."
    info "State directory: $STATE_DIR"
    echo ""

    # Run all setup steps
    setup_base_system
    setup_user
    setup_ssh
    setup_network
    setup_network_drives
    setup_nordvpn
    setup_qbittorrent
    setup_autoremove_torrents
    setup_ipfilter
    final_setup

    # Print final instructions
    print_instructions
}

# Run main function
main "$@"
