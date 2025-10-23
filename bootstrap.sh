#!/usr/bin/env bash
#
# Universal Bootstrap Script for Nix Dotfiles
#
# Usage:
#   # From existing system or NixOS LiveCD
#   curl -sSL https://raw.githubusercontent.com/nightconcept/dotfiles-nix/main/bootstrap.sh | bash
#   wget -qO- https://raw.githubusercontent.com/nightconcept/dotfiles-nix/main/bootstrap.sh | bash
#
#   # Force fresh installation mode (useful when auto-detection fails)
#   curl -sSL https://raw.githubusercontent.com/nightconcept/dotfiles-nix/main/bootstrap.sh | bash -s -- --install
#
# Supports:
#   - NixOS fresh installation (auto-detected from LiveCD)
#   - NixOS existing system (configuration switching)
#   - Linux distros (Ubuntu, Fedora, Arch, SUSE, Alpine, etc.)
#   - macOS (partial - manual steps required)
#
# Features:
#   - Auto-detects if running from LiveCD for fresh install
#   - Partitions disk and installs NixOS when on LiveCD
#   - Switches configuration on existing NixOS systems
#   - Sets up Home Manager on non-NixOS Linux
#   - Handles both desktop and server installations
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
FLAKE_REPO="https://forge.solivan.dev/nightconcept/dotfiles"
FLAKE_DIR="$HOME/git/dotfiles"

# Print colored output
print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Detect OS/Distro
detect_os() {
    if [[ "$OSTYPE" == "darwin"* ]]; then
        echo "darwin"
    elif [[ -f /etc/os-release ]]; then
        . /etc/os-release
        if [[ "$ID" == "nixos" ]]; then
            echo "nixos"
        else
            echo "linux"
        fi
    else
        echo "unknown"
    fi
}

# Check if running from NixOS LiveCD/Installer
is_nixos_livecd() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        if [[ "$ID" == "nixos" ]]; then
            # Check multiple indicators of installer environment:
            # 1. No existing nixos-rebuild command (fresh install)
            # 2. Root filesystem is tmpfs (common for live systems)
            # 3. nixos user exists (typical installer user)
            # 4. No /mnt/etc/nixos/configuration.nix (not installed yet)
            if { ! command -v nixos-rebuild &>/dev/null; } || \
               { mountpoint -q / && findmnt -n -o FSTYPE / | grep -q tmpfs; } || \
               { id nixos &>/dev/null; } || \
               { [[ ! -f /etc/nixos/configuration.nix ]] && [[ ! -L /etc/nixos/configuration.nix ]]; }; then
                return 0
            fi
        fi
    fi
    return 1
}

# Detect package manager
detect_package_manager() {
    if command -v apt-get &> /dev/null; then
        echo "apt"
    elif command -v dnf &> /dev/null; then
        echo "dnf"
    elif command -v yum &> /dev/null; then
        echo "yum"
    elif command -v pacman &> /dev/null; then
        echo "pacman"
    elif command -v zypper &> /dev/null; then
        echo "zypper"
    elif command -v apk &> /dev/null; then
        echo "apk"
    elif command -v emerge &> /dev/null; then
        echo "emerge"
    else
        echo "unknown"
    fi
}

# Detect existing Nix installation on macOS
detect_macos_nix_state() {
    local has_nix=false
    local has_darwin=false
    local install_type="none"

    # Check for Nix command
    if command -v nix &> /dev/null; then
        has_nix=true
        install_type="upstream"
    fi

    # Check for nix-darwin
    if command -v darwin-rebuild &> /dev/null || [[ -d /run/current-system/sw ]]; then
        has_darwin=true
    fi

    # Check for existing Nix store
    local has_nix_store=false
    if [[ -d /nix ]]; then
        has_nix_store=true
    fi

    echo "$install_type:$has_nix:$has_darwin:$has_nix_store"
}

# Function to backup file if it exists
backup_file() {
    if [ -f "$1" ]; then
        print_info "Backing up $1"
        sudo cp "$1" "$1.backup-$(date +%Y%m%d-%H%M%S)"
    fi
}

# Install prerequisites based on package manager
install_prerequisites() {
    local pkg_manager=$1

    # Check if essential tools are already available
    local missing_tools=()
    command -v curl &> /dev/null || missing_tools+=("curl")
    command -v git &> /dev/null || missing_tools+=("git")
    command -v xz &> /dev/null || missing_tools+=("xz")
    command -v sudo &> /dev/null || missing_tools+=("sudo")

    # If all tools are present, no need to install
    if [[ ${#missing_tools[@]} -eq 0 ]]; then
        print_info "All prerequisites already installed"
        return
    fi

    print_info "Installing prerequisites..."

    case "$pkg_manager" in
        apt)
            sudo apt-get update
            sudo apt-get install -y curl git xz-utils sudo
            ;;
        dnf|yum)
            sudo ${pkg_manager} install -y curl git xz sudo
            ;;
        pacman)
            sudo pacman -Syu --noconfirm curl git xz sudo
            ;;
        zypper)
            sudo zypper install -y curl git xz sudo
            ;;
        apk)
            sudo apk add --no-cache curl git xz sudo
            ;;
        emerge)
            # For Gentoo, we need to handle sudo separately if not present
            if ! command -v sudo &> /dev/null; then
                print_error "sudo is required but not installed."
                print_info "Please install sudo first:"
                print_info "  su -c 'emerge --ask=n app-admin/sudo'"
                print_info "Then configure sudo access for your user and re-run this script."
                exit 1
            fi
            sudo emerge --ask=n dev-vcs/git net-misc/curl app-arch/xz-utils
            ;;
        *)
            print_warning "Unknown package manager. Missing tools: ${missing_tools[*]}"
            print_info "Please install missing tools manually, then re-run this script."
            read -p "Continue anyway? (y/n): " -n 1 -r </dev/tty
            echo
            [[ ! $REPLY =~ ^[Yy]$ ]] && exit 1
            ;;
    esac
}

# Detect if running in WSL
is_wsl() {
    if [[ -f /proc/version ]] && grep -qi microsoft /proc/version; then
        return 0
    fi
    return 1
}

# Setup OpenRC service for Nix daemon (Gentoo and other OpenRC systems)
setup_nix_openrc() {
    # Check if we're on WSL - OpenRC doesn't work there
    if is_wsl; then
        print_warning "Detected WSL environment - OpenRC services not supported"
        print_info "Starting nix-daemon directly..."

        # Start daemon directly
        sudo /nix/var/nix/profiles/default/bin/nix-daemon &
        sleep 2

        # Create a helper script for future sessions
        cat > "$HOME/.nix-daemon-wsl.sh" <<'EOF'
#!/bin/bash
# Auto-start nix-daemon in WSL if not running
if ! pgrep -x nix-daemon > /dev/null 2>&1; then
    sudo /nix/var/nix/profiles/default/bin/nix-daemon > /dev/null 2>&1 &
fi
EOF
        chmod +x "$HOME/.nix-daemon-wsl.sh"

        print_success "nix-daemon started"
        print_info "To auto-start the daemon in future sessions, add this to your shell RC file:"
        print_info "  source ~/.nix-daemon-wsl.sh"
        return
    fi

    # Check if we're on an OpenRC system
    if ! command -v rc-update &> /dev/null; then
        return
    fi

    print_info "Detected OpenRC init system"

    # Check if nix-daemon service already exists
    if rc-update show default | grep -q nix-daemon; then
        print_info "nix-daemon service already enabled"
        return
    fi

    print_info "Setting up nix-daemon service for OpenRC..."

    # Create the service file
    sudo tee /etc/init.d/nix-daemon > /dev/null <<'EOF'
#!/sbin/openrc-run

name=$RC_SVCNAME
description="Nix Daemon"
supervisor="supervise-daemon"
command="/nix/var/nix/profiles/default/bin/nix-daemon"
command_args="--daemon"
EOF

    # Make it executable
    sudo chmod +x /etc/init.d/nix-daemon

    # Enable the service
    print_info "Enabling nix-daemon service..."
    sudo rc-update add nix-daemon default

    # Start the service
    print_info "Starting nix-daemon service..."
    sudo rc-service nix-daemon start

    print_success "OpenRC nix-daemon service configured and started"
    print_warning "It's recommended to reboot after installing Nix on OpenRC systems"
}

# Install Nix on non-NixOS systems
install_nix() {
    if command -v nix &> /dev/null; then
        print_info "Nix is already installed"
        return
    fi

    print_info "Installing upstream Nix..."

    # Use official upstream Nix installer (multi-user daemon mode)
    sh <(curl -L https://nixos.org/nix/install) --daemon

    # Setup OpenRC service if needed
    setup_nix_openrc

    # Source Nix
    if [[ -f /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]]; then
        . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
    elif [[ -f "$HOME/.nix-profile/etc/profile.d/nix.sh" ]]; then
        . "$HOME/.nix-profile/etc/profile.d/nix.sh"
    fi

    # Enable flakes and nix-command features
    local config_changed=false
    if [[ -f /etc/nix/nix.conf ]]; then
        if ! grep -q "experimental-features" /etc/nix/nix.conf; then
            print_info "Enabling flakes and nix-command features..."
            echo "experimental-features = nix-command flakes" | sudo tee -a /etc/nix/nix.conf
            config_changed=true
        fi

        # Add user to trusted users
        if ! grep -q "trusted-users.*$USER" /etc/nix/nix.conf; then
            print_info "Adding $USER to trusted users..."
            echo "trusted-users = root $USER" | sudo tee -a /etc/nix/nix.conf
            config_changed=true
        fi
    fi

    # Restart nix-daemon to apply configuration changes
    if [[ "$config_changed" == "true" ]]; then
        print_info "Restarting nix-daemon to apply configuration..."
        if command -v systemctl &> /dev/null; then
            sudo systemctl restart nix-daemon
        elif command -v rc-service &> /dev/null; then
            sudo rc-service nix-daemon restart
        else
            print_warning "Could not restart nix-daemon automatically"
            print_info "Please restart the nix-daemon service manually"
        fi
    fi
}

# Clone flake repository
clone_flake() {
    if [[ -d "$FLAKE_DIR" ]]; then
        print_info "Flake directory already exists at $FLAKE_DIR"

        # Check if /dev/tty is available for interactive input
        if [[ -r /dev/tty ]] && [[ -w /dev/tty ]]; then
            read -p "Pull latest changes? (y/n): " -n 1 -r </dev/tty || REPLY="y"
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                cd "$FLAKE_DIR"
                git pull
            fi
        else
            # Non-interactive mode: always pull latest changes
            print_info "Non-interactive mode: pulling latest changes..."
            cd "$FLAKE_DIR"
            git pull || print_warning "Failed to pull, continuing with existing version"
        fi
    else
        print_info "Cloning flake repository..."
        mkdir -p "$(dirname "$FLAKE_DIR")"
        git clone "$FLAKE_REPO" "$FLAKE_DIR"
    fi
    cd "$FLAKE_DIR"
}

# Determine system type
select_system_type() {
    print_info "What type of system is this?" >&2
    echo "  1) Desktop/Laptop (with GUI)" >&2
    echo "  2) Server (headless, no GUI)" >&2
    echo >&2

    # Check if /dev/tty is available
    if [[ ! -r /dev/tty ]] || [[ ! -w /dev/tty ]]; then
        print_warning "/dev/tty not available, defaulting to server configuration" >&2
        echo "server"
        return
    fi

    read -p "Select type (1-2): " -n 1 -r </dev/tty || {
        print_warning "Failed to read input, defaulting to server configuration" >&2
        echo "server"
        return
    }
    echo >&2

    case "$REPLY" in
        1)
            echo "desktop"
            ;;
        2)
            echo "server"
            ;;
        *)
            print_error "Invalid selection" >&2
            select_system_type
            ;;
    esac
}

# NixOS host selection menu for desktops
select_desktop_host() {
    print_info "Available desktop configurations:" >&2
    echo "  1) tidus   - Dell Latitude 7420 laptop" >&2
    echo "  2) Skip    - Don't switch configuration" >&2
    echo >&2

    if [[ ! -r /dev/tty ]] || [[ ! -w /dev/tty ]]; then
        print_warning "/dev/tty not available, skipping configuration" >&2
        echo "skip"
        return
    fi

    read -p "Select configuration (1-2): " -n 1 -r </dev/tty || {
        print_warning "Failed to read input, skipping configuration" >&2
        echo "skip"
        return
    }
    echo >&2

    case "$REPLY" in
        1)
            echo "tidus"
            ;;
        2)
            echo "skip"
            ;;
        *)
            print_error "Invalid selection" >&2
            select_desktop_host
            ;;
    esac
}

# NixOS host selection menu for servers
select_server_host() {
    print_info "Available server configurations:" >&2
    echo "  1) aerith  - Plex media server" >&2
    echo "  2) barrett - VPN torrent server" >&2
    echo "  3) rinoa   - Docker server" >&2
    echo "  4) vincent - CI/CD runner with Docker" >&2
    echo "  5) Skip    - Don't switch configuration" >&2
    echo >&2

    if [[ ! -r /dev/tty ]] || [[ ! -w /dev/tty ]]; then
        print_warning "/dev/tty not available, defaulting to rinoa" >&2
        echo "rinoa"
        return
    fi

    read -p "Select configuration (1-5): " -n 1 -r </dev/tty || {
        print_warning "Failed to read input, defaulting to rinoa" >&2
        echo "rinoa"
        return
    }
    echo >&2

    case "$REPLY" in
        1)
            echo "aerith"
            ;;
        2)
            echo "barrett"
            ;;
        3)
            echo "rinoa"
            ;;
        4)
            echo "vincent"
            ;;
        5)
            echo "skip"
            ;;
        *)
            print_error "Invalid selection" >&2
            select_server_host
            ;;
    esac
}

# Setup SOPS age keys (both user and system level)
setup_age_keys() {
    print_info "Setting up SOPS age keys..."

    local age_key=""
    local setup_system_key=false

    # Check if we're setting up system-level keys (NixOS only)
    if [[ "$1" == "--system" ]]; then
        setup_system_key=true
    fi

    # Create user age directory
    mkdir -p "$HOME/.config/sops/age"

    # Check if user age key already exists
    if [[ -f "$HOME/.config/sops/age/keys.txt" ]]; then
        print_info "User age key file already exists"
        age_key=$(cat "$HOME/.config/sops/age/keys.txt")
    else
        # Extract keys from encrypted bootstrap archive
        local keys_archive="$FLAKE_DIR/scripts/bootstrap/keys.tar.gz.gpg"

        if [[ ! -f "$keys_archive" ]]; then
            print_error "Keys archive not found at: $keys_archive"
            print_warning "Skipping age key setup. Secrets won't work until configured."
            return 1
        fi

        print_info "🔓 Extracting keys from bootstrap archive..."
        echo -n "Enter bootstrap password: "

        if [[ ! -r /dev/tty ]] || [[ ! -w /dev/tty ]]; then
            print_warning "/dev/tty not available, skipping age key setup"
            return 1
        fi

        read -s bootstrap_password </dev/tty || {
            print_warning "Failed to read password, skipping age key setup"
            return 1
        }
        echo

        # Create temporary directory for extraction
        local temp_dir="/tmp/bootstrap-key-extract-$$"
        mkdir -p "$temp_dir"

        # Save current directory to return to it later
        local original_dir="$PWD"
        cd "$temp_dir"

        # Decrypt and extract keys
        if echo "$bootstrap_password" | gpg --batch --yes --passphrase-fd 0 --decrypt "$keys_archive" | tar xzf -; then
            # Deploy age key
            if [[ -f "age_keys_extracted" ]]; then
                cp "age_keys_extracted" "$HOME/.config/sops/age/keys.txt"
                chmod 600 "$HOME/.config/sops/age/keys.txt"
                age_key=$(cat "$HOME/.config/sops/age/keys.txt")
                print_success "✓ Age key deployed to ~/.config/sops/age/keys.txt"
            fi

            # Deploy SSH private key
            if [[ -f "id_sdev_extracted" ]]; then
                mkdir -p "$HOME/.ssh"
                cp "id_sdev_extracted" "$HOME/.ssh/id_sdev"
                chmod 600 "$HOME/.ssh/id_sdev"
                print_success "✓ SSH private key deployed to ~/.ssh/id_sdev"
            fi

            print_success "🎉 Keys extracted and deployed successfully!"
        else
            print_error "Failed to decrypt archive. Wrong password?"
            rm -rf "$temp_dir"
            cd "$original_dir"
            return 1
        fi

        # Cleanup and return to original directory
        rm -rf "$temp_dir"
        cd "$original_dir"
    fi

    # Setup system-level key for NixOS (requires sudo)
    if [[ "$setup_system_key" == "true" ]] && [[ -n "$age_key" ]]; then
        print_info "Setting up system-level SOPS age key..."
        if command -v sudo &> /dev/null; then
            sudo mkdir -p /var/lib/sops-nix
            echo "$age_key" | sudo tee /var/lib/sops-nix/key.txt > /dev/null
            sudo chmod 600 /var/lib/sops-nix/key.txt
            sudo chown root:root /var/lib/sops-nix/key.txt
            print_success "System-level age key configured"
        else
            print_warning "sudo not available, system-level key setup skipped"
            print_info "To manually set up system key later, run:"
            print_info "  sudo mkdir -p /var/lib/sops-nix"
            print_info "  echo '$age_key' | sudo tee /var/lib/sops-nix/key.txt"
            print_info "  sudo chmod 600 /var/lib/sops-nix/key.txt"
        fi
    fi
}

# Apply NixOS configuration
apply_nixos_config() {
    local host=$1
    local is_install=${2:-false}

    print_info "Building and switching to NixOS configuration: $host"

    # Enable flakes if not already enabled
    if ! grep -q "experimental-features.*flakes" /etc/nix/nix.conf 2>/dev/null; then
        echo "experimental-features = nix-command flakes" | sudo tee -a /etc/nix/nix.conf
    fi

    # Setup age keys before applying config (including system-level for NixOS)
    setup_age_keys --system

    # Build and switch
    if [[ "$is_install" == "true" ]]; then
        nixos-install --flake ".#$host" --no-root-password
    else
        sudo nixos-rebuild switch --flake ".#$host"
    fi

    print_success "NixOS configuration applied!"
}

# Apply Home Manager configuration directly from flake
apply_home_manager_from_flake() {
    local profile=$1

    print_info "Applying Home Manager configuration from flake: $profile"

    # Use nix run to apply home-manager configuration directly from the flake
    # This doesn't require home-manager to be pre-installed
    nix run home-manager/master -- switch --flake ".#$profile" -b backup

    # Fix .nix-profile symlink if it's pointing to the wrong location
    if [[ -L "$HOME/.nix-profile" ]]; then
        local current_target=$(readlink -f "$HOME/.nix-profile")
        local expected_target="$HOME/.local/state/nix/profiles/home-manager"

        if [[ "$current_target" != "$expected_target" && -d "$HOME/.local/state/nix/profiles/home-manager" ]]; then
            print_info "Fixing .nix-profile symlink..."
            rm -f "$HOME/.nix-profile"
            ln -sf "$HOME/.local/state/nix/profiles/home-manager" "$HOME/.nix-profile"
        fi
    fi

    # Change default shell to fish for desktop and server profiles
    if [[ "$profile" == "desktop" || "$profile" == "server" ]]; then
        local fish_path="$HOME/.nix-profile/bin/fish"

        if [[ -x "$fish_path" ]]; then
            print_info "Setting default shell to fish..."

            # Add fish to /etc/shells if not already present
            if ! grep -q "^$fish_path$" /etc/shells 2>/dev/null; then
                print_info "Adding fish to /etc/shells..."
                echo "$fish_path" | sudo tee -a /etc/shells > /dev/null
            fi

            # Change default shell
            if command -v chsh &> /dev/null; then
                chsh -s "$fish_path"
                print_success "Default shell changed to fish"
                print_info "Please log out and log back in for shell change to take effect"
            else
                print_warning "chsh command not found, cannot change default shell"
                print_info "To change shell manually later, run: chsh -s $fish_path"
            fi
        else
            print_warning "Fish shell not found at expected path: $fish_path"
        fi
    fi

    print_success "Home Manager configuration applied!"
    print_info "The 'home-manager' command is now available for future updates"
    print_info "Restart your shell or run: source ~/.nix-profile/etc/profile.d/hm-session-vars.sh"
}


# Fresh Nix installation for macOS
install_fresh_nix_macos() {
    print_info "🍎 Installing fresh Nix on macOS..."
    print_info "   Downloading and running official Nix installer..."

    # Install upstream Nix (multi-user)
    sh <(curl -L https://nixos.org/nix/install) --daemon

    # Source Nix for current session
    if [ -f /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]; then
        . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
    fi

    print_success "✅ Fresh Nix installation completed!"
}

# Install or update nix-darwin
install_nix_darwin() {
    local hostname=$(hostname -s)
    local darwin_config="waver"  # default

    # Check if merlin config exists and we're on merlin
    if [[ "$hostname" == "merlin" ]]; then
        darwin_config="merlin"
    fi

    print_info "🔧 Installing nix-darwin..."
    print_info "   Using Darwin configuration: $darwin_config"

    # Clone flake if not already done
    clone_flake

    # Install nix-darwin with the flake
    cd "$FLAKE_DIR"
    nix run nix-darwin -- switch --flake ".#$darwin_config"

    print_success "✅ nix-darwin installation completed!"
    print_info "📋 Next steps:"
    print_info "   1. Restart your terminal for PATH changes to take effect"
    print_info "   2. Verify: darwin-rebuild switch --flake .#$darwin_config"
}

# Bootstrap macOS with nix-darwin
bootstrap_macos() {
    local nix_state=$(detect_macos_nix_state)
    IFS=':' read -r install_type has_nix has_darwin has_nix_store <<< "$nix_state"

    print_info "🍎 Bootstrapping macOS with Nix and nix-darwin"
    echo

    # Install Nix if not already installed
    if [[ "$install_type" == "none" ]]; then
        print_info "Installing Nix..."
        install_fresh_nix_macos
    else
        print_success "Nix already installed"
    fi

    # Install/update nix-darwin
    print_info "Installing nix-darwin..."
    install_nix_darwin
}

# Apply Home Manager configuration
apply_home_config() {
    local profile=$1

    print_info "Available Home Manager profiles:"
    echo "  1) desktop - Full desktop environment"
    echo "  2) server  - Minimal server configuration"
    echo "  3) Skip    - Don't apply Home Manager configuration"
    echo

    # Handle non-interactive environments
    if [[ ! -r /dev/tty ]] || [[ ! -w /dev/tty ]]; then
        print_warning "/dev/tty not available, defaulting to server profile"
        profile="server"
    else
        read -p "Select profile (1-3): " -n 1 -r </dev/tty || {
            print_warning "Failed to read input, defaulting to server profile"
            profile="server"
        }
        echo

        case "$REPLY" in
            1)
                profile="desktop"
                ;;
            2)
                profile="server"
                ;;
            3)
                print_info "Skipping Home Manager configuration"
                return
                ;;
            *)
                print_error "Invalid selection"
                apply_home_config
                return
                ;;
        esac
    fi

    # Apply configuration using the flake-based approach
    apply_home_manager_from_flake "$profile"
}

# Partition and format disk for fresh install
setup_disk() {
    local disk=$1

    print_warning "This will completely erase $disk"
    lsblk "$disk" 2>/dev/null || { print_error "Disk $disk not found"; exit 1; }

    if [[ ! -r /dev/tty ]] || [[ ! -w /dev/tty ]]; then
        print_warning "/dev/tty not available, auto-confirming disk erase"
        confirm="yes"
    else
        read -p "Continue? (yes/no): " confirm </dev/tty || confirm="yes"
    fi

    if [ "$confirm" != "yes" ]; then
        echo "Aborted"
        exit 1
    fi

    print_info "Partitioning disk..."

    # Wipe disk
    wipefs -af "$disk"
    sgdisk -Z "$disk"

    # Create partitions for BIOS/MBR boot
    parted "$disk" -- mklabel msdos
    parted "$disk" -- mkpart primary ext4 1MiB 100%
    parted "$disk" -- set 1 boot on

    sleep 2

    # Determine partition naming scheme
    if [ -b "${disk}p1" ]; then
        ROOT_PART="${disk}p1"
    else
        ROOT_PART="${disk}1"
    fi

    print_info "Formatting partition..."
    mkfs.ext4 -L nixos "$ROOT_PART"

    print_info "Mounting filesystem..."
    mount "$ROOT_PART" /mnt

    print_info "Generating hardware configuration..."
    nixos-generate-config --root /mnt

    # Clone repository to target location
    print_info "Cloning dotfiles repository..."
    mkdir -p /mnt/home/danny/git
    git clone "$FLAKE_REPO" /mnt/home/danny/git/dotfiles-nix

    # Create symlink at /etc/nixos for convenience
    mkdir -p /mnt/etc/nixos
    ln -sf /home/danny/git/dotfiles-nix /mnt/etc/nixos/dotfiles-nix

    # Copy hardware configuration to host directory
    if [[ -n "$ARG_HOSTNAME" ]]; then
        mkdir -p "/mnt/etc/nixos/dotfiles-nix/hosts/nixos/$ARG_HOSTNAME"
        cp /mnt/etc/nixos/hardware-configuration.nix "/mnt/etc/nixos/dotfiles-nix/hosts/nixos/$ARG_HOSTNAME/"
    fi

    print_success "Disk setup complete"
}

# NixOS fresh installation flow
nixos_fresh_install() {
    print_info "Starting NixOS fresh installation from LiveCD"

    # Check if running as root
    if [ "$EUID" -ne 0 ]; then
        print_error "Fresh installation requires root. Use 'sudo -i' on LiveCD"
        exit 1
    fi

    print_info "Root check passed, EUID=$EUID"

    # Determine system type
    print_info "About to select system type..."
    system_type=$(select_system_type)
    print_info "System type selected: $system_type"

    # Select host configuration based on type
    local host
    if [[ "$system_type" == "desktop" ]]; then
        host=$(select_desktop_host)
    else
        host=$(select_server_host)
    fi

    if [[ "$host" == "skip" ]]; then
        print_error "Host configuration required for installation"
        exit 1
    fi

    # Get installation parameters
    local disk=$(prompt_with_default "Enter target disk (e.g., /dev/sda, /dev/vda)" "/dev/sda")

    # Setup disk
    setup_disk "$disk"

    # Change to repository directory
    cd /mnt/home/danny/git/dotfiles-nix

    # Update hardware configuration for the selected host
    print_info "Updating hardware configuration for $host"
    cp /mnt/etc/nixos/hardware-configuration.nix "hosts/nixos/$host/"


    # Setup age keys for both user-level and system-level secrets
    print_info "Setting up SOPS age keys..."

    # Create directories in mounted system with correct ownership
    mkdir -p /mnt/home/danny/.config/sops/age
    mkdir -p /mnt/home/danny/.ssh
    mkdir -p /mnt/var/lib/sops-nix

    # Ensure .config and .ssh directories have correct ownership
    chown -R 1000:100 /mnt/home/danny/.config
    chown -R 1000:100 /mnt/home/danny/.ssh
    chmod 700 /mnt/home/danny/.ssh

    local age_key=""

    # Check for existing key or prompt for new one
    if [[ -f "$HOME/.config/sops/age/keys.txt" ]]; then
        print_info "Using existing age key"
        age_key=$(cat "$HOME/.config/sops/age/keys.txt")
    else
        print_info "Age key is required for accessing encrypted secrets (SOPS)"
        echo "Enter your age private key (starts with AGE-SECRET-KEY):"
        echo "(Press Enter to skip if you don't have one)"
        if [[ ! -r /dev/tty ]] || [[ ! -w /dev/tty ]]; then
            print_warning "/dev/tty not available, skipping age key input"
            age_key=""
        else
            read -r age_key </dev/tty || age_key=""
        fi
    fi

    if [[ "$age_key" =~ ^AGE-SECRET-KEY ]]; then
        # Save user-level age key
        echo "$age_key" > /mnt/home/danny/.config/sops/age/keys.txt
        chmod 600 /mnt/home/danny/.config/sops/age/keys.txt
        chown 1000:100 /mnt/home/danny/.config/sops/age/keys.txt

        # Save system-level age key (required for system services)
        echo "$age_key" > /mnt/var/lib/sops-nix/key.txt
        chmod 600 /mnt/var/lib/sops-nix/key.txt
        chown 0:0 /mnt/var/lib/sops-nix/key.txt

        print_success "Age keys saved (both user and system level)"
    else
        print_warning "No age key provided, secrets won't work until configured"
        print_info "To configure later, run:"
        print_info "  1. Place age key at: ~/.config/sops/age/keys.txt"
        print_info "  2. Copy to system: sudo cp ~/.config/sops/age/keys.txt /var/lib/sops-nix/key.txt"
        print_info "  3. Set permissions: sudo chmod 600 /var/lib/sops-nix/key.txt"
    fi

    # Optionally set a password for the user
    print_info "User account setup"
    echo "Set a password for user 'danny' now? (recommended for SSH access)"
    echo "Press Enter to skip and set it after first boot"

    local hashed_password=""
    if [[ -r /dev/tty ]] && [[ -w /dev/tty ]]; then
        read -s -p "Enter password (or press Enter to skip): " user_password </dev/tty
        echo
        if [[ -n "$user_password" ]]; then
            # Hash the password using mkpasswd
            if command -v mkpasswd &>/dev/null; then
                hashed_password=$(mkpasswd -m sha-512 "$user_password")
                print_success "Password set for user danny"
            else
                print_warning "mkpasswd not found, trying openssl"
                # Fallback to openssl if available
                if command -v openssl &>/dev/null; then
                    local salt=$(openssl rand -base64 16 | tr -d '\n')
                    hashed_password=$(openssl passwd -6 -salt "$salt" "$user_password")
                    print_success "Password set for user danny"
                else
                    print_warning "Cannot hash password, will need to set after boot"
                fi
            fi
        fi
    fi

    # Create a minimal configuration that just boots
    print_info "Generating minimal bootable configuration..."
    if [[ -n "$hashed_password" ]]; then
        cat > /mnt/etc/nixos/configuration.nix <<EOF
{ config, pkgs, ... }:
{
  imports = [ ./hardware-configuration.nix ];

  boot.loader = {
    systemd-boot.enable = false;
    efi.canTouchEfiVariables = false;
    grub = {
      enable = true;
      device = "DISK_PLACEHOLDER";  # Install GRUB to MBR
    };
  };

  networking.hostName = "HOSTNAME_PLACEHOLDER";
  networking.networkmanager.enable = true;

  time.timeZone = "America/Los_Angeles";

  users.users.danny = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" ];
    hashedPassword = "$hashed_password";
  };

  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = true;
    };
  };

  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  system.stateVersion = "24.11";
}
EOF
    else
        cat > /mnt/etc/nixos/configuration.nix <<'EOF'
{ config, pkgs, ... }:
{
  imports = [ ./hardware-configuration.nix ];

  boot.loader = {
    systemd-boot.enable = false;
    efi.canTouchEfiVariables = false;
    grub = {
      enable = true;
      device = "DISK_PLACEHOLDER";  # Install GRUB to MBR
    };
  };

  networking.hostName = "HOSTNAME_PLACEHOLDER";
  networking.networkmanager.enable = true;

  time.timeZone = "America/Los_Angeles";

  users.users.danny = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" ];
  };

  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = true;
    };
  };

  # Essential packages for post-install management
  environment.systemPackages = with pkgs; [
    git
    wget
    vim
    curl
  ];

  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  system.stateVersion = "24.11";
}
EOF
    fi
    # Replace placeholders
    sed -i "s/HOSTNAME_PLACEHOLDER/$host/g" /mnt/etc/nixos/configuration.nix
    sed -i "s|DISK_PLACEHOLDER|$disk|g" /mnt/etc/nixos/configuration.nix

    # Install minimal system
    print_info "Installing minimal NixOS system..."
    nixos-install --no-root-password

    # Create post-install script
    cat > /mnt/home/danny/apply-full-config.sh <<'EOF'
#!/usr/bin/env bash
echo "Applying full flake configuration..."

# Ensure we own the dotfiles directory and have latest changes
if [ -d ~/git/dotfiles-nix ]; then
    cd ~/git/dotfiles-nix
    echo "Pulling latest changes..."
    git pull
else
    echo "Cloning dotfiles repository..."
    mkdir -p ~/git
    git clone https://github.com/nightconcept/dotfiles-nix ~/git/dotfiles-nix
    cd ~/git/dotfiles-nix
fi

sudo nixos-rebuild switch --flake .#HOSTNAME_PLACEHOLDER
echo "Configuration complete!"
EOF
    sed -i "s/HOSTNAME_PLACEHOLDER/$host/g" /mnt/home/danny/apply-full-config.sh
    chmod +x /mnt/home/danny/apply-full-config.sh
    chown 1000:100 /mnt/home/danny/apply-full-config.sh

    print_success "Installation complete!"
    echo
    echo "Next steps:"
    echo "1. Reboot into your new system: reboot"
    if [[ -z "$hashed_password" ]]; then
        echo "2. Log in as 'danny' (no password required)"
        echo "3. Set your password immediately: passwd"
        echo "4. Apply the full configuration: ~/apply-full-config.sh"
    else
        echo "2. Log in as 'danny' with the password you set"
        echo "3. Apply the full configuration: ~/apply-full-config.sh"
    fi
    echo
    echo "The system is now running a minimal NixOS installation with SSH enabled."
    echo "The full flake configuration will be applied after reboot."
}

# Prompt for input with default value
prompt_with_default() {
    local prompt="$1"
    local default="$2"
    local value

    if [[ ! -r /dev/tty ]] || [[ ! -w /dev/tty ]]; then
        print_warning "/dev/tty not available, using default: $default"
        echo "$default"
        return
    fi

    read -p "$prompt [$default]: " value </dev/tty || {
        print_warning "Failed to read input, using default: $default"
        echo "$default"
        return
    }
    echo "${value:-$default}"
}

# Main installation flow
main() {
    # Parse command-line arguments
    local force_install=false
    while [[ $# -gt 0 ]]; do
        case $1 in
            --install|--fresh-install)
                force_install=true
                shift
                ;;
            --help|-h)
                echo "Usage: $0 [OPTIONS]"
                echo "Options:"
                echo "  --install, --fresh-install  Force fresh installation mode"
                echo "  --help, -h                  Show this help message"
                exit 0
                ;;
            *)
                shift
                ;;
        esac
    done

    clear
    echo "======================================"
    echo "   Nix Dotfiles Bootstrap Script"
    echo "======================================"
    echo

    # Detect OS
    OS=$(detect_os)
    print_info "Detected OS: $OS"

    case "$OS" in
        nixos)
            # Check if running from LiveCD (fresh install) or forced install mode
            if is_nixos_livecd || [[ "$force_install" == "true" ]]; then
                if [[ "$force_install" == "true" ]]; then
                    print_info "Fresh installation mode (forced)"
                else
                    print_info "Detected NixOS installer environment"
                fi
                nixos_fresh_install
            else
                # Existing NixOS system
                print_info "Running on existing NixOS system"
                clone_flake

                # Determine system type and select configuration
                system_type=$(select_system_type)
                local host
                if [[ "$system_type" == "desktop" ]]; then
                    host=$(select_desktop_host)
                else
                    host=$(select_server_host)
                fi

                if [[ "$host" != "skip" ]]; then
                    apply_nixos_config "$host"
                else
                    print_info "Skipping NixOS configuration"
                fi
            fi
            ;;
            
        linux)
            print_info "Running on Linux (non-NixOS)"

            # Detect and use package manager
            PKG_MANAGER=$(detect_package_manager)
            print_info "Detected package manager: $PKG_MANAGER"

            # Install prerequisites
            install_prerequisites "$PKG_MANAGER"

            # Install Nix
            install_nix

            # Clone flake
            clone_flake

            # Setup age keys (required for SOPS secrets)
            setup_age_keys

            # Apply Home Manager configuration directly from flake
            apply_home_config
            ;;
            
        darwin)
            print_info "Running on macOS"
            bootstrap_macos
            ;;
            
        *)
            print_error "Unsupported OS"
            exit 1
            ;;
    esac
    
    # Installation is handled above in nixos_fresh_install for NixOS
    # This section is only reached for non-NixOS systems
    print_success "Bootstrap complete!"
}

# Run main function
main "$@"