#!/usr/bin/env bash
# Install terminal emulators (Ghostty/WezTerm)

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Print colored output
print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Detect package manager
detect_package_manager() {
    if command -v apt-get &> /dev/null; then
        echo "apt"
    elif command -v dnf &> /dev/null; then
        echo "dnf"
    elif command -v pacman &> /dev/null; then
        echo "pacman"
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        echo "brew"
    else
        echo "unknown"
    fi
}

PKG_MANAGER=$(detect_package_manager)

install_ghostty_apt() {
    # Detect if we are on Ubuntu or Debian
    local DISTRO
    DISTRO=$(lsb_release -is)

    if [[ "$DISTRO" == "Ubuntu" ]]; then
        print_info "Installing Ghostty via Mike Kasberg PPA (recommended for Ubuntu)..."
        
        # Ensure add-apt-repository is available
        sudo apt-get update
        sudo apt-get install -y software-properties-common

        # Add the PPA
        sudo add-apt-repository -y ppa:mkasberg/ghostty-ubuntu
        
        # Update and install
        sudo apt-get update
        sudo apt-get install -y ghostty
    else
        print_info "Installing Ghostty from debian.griffo.io repository..."

        # Ensure dependencies are installed
        sudo apt-get update
        sudo apt-get install -y curl gpg lsb-release

        # Download and add the GPG key
        print_info "Adding GPG key..."
        curl -sS https://debian.griffo.io/EA0F721D231FDD3A0A17B9AC7808B4DD62C41256.asc | \
            sudo gpg --yes --dearmor -o /etc/apt/trusted.gpg.d/debian.griffo.io.gpg

        # Add the repository
        print_info "Adding repository..."
        echo "deb https://debian.griffo.io/apt $(lsb_release -sc) main" | \
            sudo tee /etc/apt/sources.list.d/debian.griffo.io.list

        # Update apt cache
        print_info "Updating apt cache..."
        sudo apt-get update

        # Install ghostty
        print_info "Installing ghostty..."
        sudo apt-get install -y ghostty
    fi

    print_success "Ghostty installed successfully!"
}

install_ghostty_pacman() {
    print_info "Installing Ghostty via pacman..."
    sudo pacman -S --noconfirm ghostty
}

install_ghostty_dnf() {
    print_info "Installing Ghostty via dnf..."
    # Ghostty might be in a COPR for Fedora
    if ! sudo dnf list ghostty &> /dev/null; then
        print_info "Ghostty not found in default repos, enabling COPR..."
        sudo dnf copr enable -y carlwgeorge/ghostty
    fi
    sudo dnf install -y ghostty
}

install_ghostty_brew() {
    print_info "Installing Ghostty via Homebrew..."
    brew install --cask ghostty
}

install_wezterm_apt() {
    print_info "Which version of WezTerm would you like to install?"
    echo "1) Stable (wezterm)"
    echo "2) Nightly (wezterm-nightly) [Recommended]"
    echo
    read -p "Enter your choice (1 or 2): " wez_choice

    case $wez_choice in
        1)
            PACKAGE="wezterm"
            ;;
        2)
            PACKAGE="wezterm-nightly"
            ;;
        *)
            print_warning "Invalid choice. Defaulting to nightly."
            PACKAGE="wezterm-nightly"
            ;;
    esac

    print_info "Installing $PACKAGE from apt.fury.io repository..."

    # Ensure dependencies are installed
    sudo apt-get update
    sudo apt-get install -y curl gpg

    # Download and add the GPG key
    print_info "Adding GPG key..."
    curl -fsSL https://apt.fury.io/wez/gpg.key | \
        sudo gpg --yes --dearmor -o /usr/share/keyrings/wezterm-fury.gpg

    # Add the repository
    print_info "Adding repository..."
    echo 'deb [signed-by=/usr/share/keyrings/wezterm-fury.gpg] https://apt.fury.io/wez/ * *' | \
        sudo tee /etc/apt/sources.list.d/wezterm.list

    # Set proper permissions
    sudo chmod 644 /usr/share/keyrings/wezterm-fury.gpg

    # Update apt cache
    print_info "Updating apt cache..."
    sudo apt-get update

    # Install wezterm
    print_info "Installing $PACKAGE..."
    sudo apt-get install -y "$PACKAGE"

    print_success "$PACKAGE installed successfully!"
}

install_wezterm_pacman() {
    print_info "Installing WezTerm via pacman..."
    sudo pacman -S --noconfirm wezterm
}

install_wezterm_dnf() {
    print_info "Installing WezTerm via dnf..."
    sudo dnf install -y wezterm
}

install_wezterm_brew() {
    print_info "Installing WezTerm via Homebrew..."
    brew install --cask wezterm
}

install_ghostty() {
    case "$PKG_MANAGER" in
        apt) install_ghostty_apt ;;
        pacman) install_ghostty_pacman ;;
        dnf) install_ghostty_dnf ;;
        brew) install_ghostty_brew ;;
        *) print_error "Ghostty installation not implemented for $PKG_MANAGER" ;;
    esac
}

install_wezterm() {
    case "$PKG_MANAGER" in
        apt) install_wezterm_apt ;;
        pacman) install_wezterm_pacman ;;
        dnf) install_wezterm_dnf ;;
        brew) install_wezterm_brew ;;
        *) print_error "WezTerm installation not implemented for $PKG_MANAGER" ;;
    esac
}

# Main menu
main() {
    if [[ "$PKG_MANAGER" == "unknown" ]]; then
        print_error "Unsupported package manager. This script supports apt, dnf, pacman, and brew."
        exit 1
    fi

    echo "Terminal Emulator Installation Script"
    echo "====================================="
    print_info "Detected package manager: $PKG_MANAGER"
    echo
    echo "Which terminal emulator would you like to install?"
    echo "1) Ghostty"
    echo "2) WezTerm"
    echo "3) Both"
    echo "0) Exit"
    echo
    read -p "Enter your choice (0-3): " choice

    case $choice in
        0)
            print_info "Exiting."
            exit 0
            ;;
        1)
            install_ghostty
            ;;
        2)
            install_wezterm
            ;;
        3)
            install_ghostty
            install_wezterm
            ;;
        *)
            print_error "Invalid choice. Exiting."
            exit 1
            ;;
    esac

    echo
    print_success "Installation process complete!"
}

main "$@"
