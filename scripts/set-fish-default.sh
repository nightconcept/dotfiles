#!/usr/bin/env bash
#
# Script to set fish as the default shell safely
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# 1. Find the fish executable
FISH_PATH=""

# Try finding it in the PATH
if command -v fish &>/dev/null; then
    FISH_PATH=$(command -v fish)
fi

# If not found or if it's a symlink to a Nix path, try to find the "real" path
# often useful for Home Manager on non-NixOS
if [[ -z "$FISH_PATH" ]]; then
    COMMON_PATHS=(
        "$HOME/.nix-profile/bin/fish"
        "/run/current-system/sw/bin/fish"
        "/usr/local/bin/fish"
        "/usr/bin/fish"
    )

    for path in "${COMMON_PATHS[@]}"; do
        if [[ -x "$path" ]]; then
            FISH_PATH="$path"
            break
        fi
    done
fi

if [[ -z "$FISH_PATH" ]]; then
    print_error "Fish shell not found! Please ensure it is installed."
    exit 1
fi

print_info "Found fish at: $FISH_PATH"

# 2. Add to /etc/shells if not already present
if ! grep -q "^$FISH_PATH$" /etc/shells 2>/dev/null; then
    print_info "Adding $FISH_PATH to /etc/shells..."
    echo "$FISH_PATH" | sudo tee -a /etc/shells > /dev/null
else
    print_info "$FISH_PATH is already in /etc/shells"
fi

# 3. Change the shell
print_info "Changing default shell to fish..."
if chsh -s "$FISH_PATH"; then
    print_success "Default shell changed to fish!"
    print_info "You may need to log out and back in for the changes to take effect."
else
    print_error "Failed to change shell. You might need to run: chsh -s $FISH_PATH manually."
    exit 1
fi
