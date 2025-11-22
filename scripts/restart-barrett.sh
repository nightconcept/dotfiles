#!/usr/bin/env bash

# Restart Barrett Services Script
# Restarts network mounts and qBittorrent

set -euo pipefail

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root (use sudo)"
    exit 1
fi

info "Reloading systemd daemon..."
systemctl daemon-reload

info "Restarting Titan mount..."
systemctl restart mnt-titan.automount
sleep 2

info "Triggering automount by accessing directory..."
ls /mnt/titan > /dev/null 2>&1 || true
sleep 1

info "Restarting qBittorrent..."
systemctl restart qbittorrent
sleep 2

echo ""
success "All services restarted!"
echo ""

info "Service Status:"
echo ""
systemctl status mnt-titan.automount --no-pager -l | head -n 3
systemctl status mnt-titan.mount --no-pager -l | head -n 3
systemctl status qbittorrent --no-pager -l | head -n 3

echo ""
info "qBittorrent WebUI: http://barrett.local:8112"
