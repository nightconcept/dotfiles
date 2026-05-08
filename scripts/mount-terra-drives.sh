#!/usr/bin/env bash

# Script to assemble and mount local RAID arrays (jeanne and terra)
# Detected 6 drives: 3x4TB (jeanne) and 3x8TB (terra)

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

info() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root"
        exit 1
    fi
}

install_mdadm() {
    if ! command -v mdadm &>/dev/null; then
        info "mdadm not found, attempting to install..."
        if command -v apt-get &>/dev/null; then
            apt-get update && apt-get install -y mdadm
        else
            error "Package manager not supported. Please install mdadm manually."
            exit 1
        fi
    else
        info "mdadm is already installed."
    fi
}

assemble_arrays() {
    info "Attempting to assemble RAID arrays..."
    # Force scanning and assembly
    mdadm --assemble --scan || warning "Some arrays may already be assembled or failed to assemble."
    
    # Wait a moment for devices to settle
    sleep 2
    
    if [ -f /proc/mdstat ]; then
        info "Current RAID status (/proc/mdstat):"
        cat /proc/mdstat
    fi
}

mount_arrays() {
    # Find all active md devices
    local md_devices=$(lsblk -dno NAME,TYPE | grep md | awk '{print $1}')
    
    if [[ -z "$md_devices" ]]; then
        error "No active RAID (md) devices found after assembly."
        return 1
    fi
    
    for dev in $md_devices; do
        local dev_path="/dev/$dev"
        # Get label from metadata or filesystem
        local label=$(lsblk -no LABEL "$dev_path" | head -n1 || echo "raid-$dev")
        local mount_point="/mnt/$label"
        
        info "Processing $dev_path (Label: $label)..."
        
        mkdir -p "$mount_point"
        
        if mountpoint -q "$mount_point"; then
            warning "$dev_path is already mounted at $mount_point"
        else
            if mount "$dev_path" "$mount_point" 2>/dev/null; then
                success "Mounted $dev_path at $mount_point"
            else
                # Try mounting by checking if it's part of LVM
                if command -v pvs &>/dev/null && pvs "$dev_path" &>/dev/null; then
                    info "$dev_path detected as LVM Physical Volume. Scanning LVM..."
                    vgscan
                    vgchange -ay
                    
                    # Find LVs associated with this PV's VG
                    local vg_name=$(pvs "$dev_path" --noheadings -o vg_name | tr -d ' ')
                    local lv_names=$(lvs $vg_name --noheadings -o lv_name | tr -d ' ')
                    
                    for lv in $lv_names; do
                        local lv_path="/dev/$vg_name/$lv"
                        local lv_mount="/mnt/$vg_name-$lv"
                        mkdir -p "$lv_mount"
                        if mount "$lv_path" "$lv_mount"; then
                            success "Mounted LVM volume $lv_path at $lv_mount"
                        fi
                    done
                else
                    error "Failed to mount $dev_path. Check 'dmesg' or 'journalctl -xe' for details."
                fi
            fi
        fi
    done
}

main() {
    check_root
    install_mdadm
    assemble_arrays
    mount_arrays
    
    info "Final block device structure:"
    lsblk -e 7
}

main "$@"
