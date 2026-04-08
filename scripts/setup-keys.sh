#!/usr/bin/env bash
#
# One-time SSH and Age key setup script
#
# This script extracts encrypted keys from the bootstrap archive,
# re-encrypts them with a new password, and deploys them.
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

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
BOOTSTRAP_DIR="$REPO_DIR/scripts/bootstrap"
KEYS_ARCHIVE="$BOOTSTRAP_DIR/keys.tar.gz.gpg"
WORK_DIR="/tmp/dotfiles-key-setup-$$"

cleanup() {
    if [ -d "$WORK_DIR" ]; then
        rm -rf "$WORK_DIR"
    fi
}
trap cleanup EXIT


main() {
    print_info "🔑 SSH and Age Key Setup"
    echo "========================"
    echo

    # Check if keys already exist
    if [ -f "$HOME/.ssh/id_sdev" ] && [ -f "$HOME/.config/sops/age/keys.txt" ]; then
        print_warning "Keys already exist!"
        echo "  ~/.ssh/id_sdev"
        echo "  ~/.config/sops/age/keys.txt"
        echo
        read -p "Overwrite existing keys? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_info "Setup cancelled"
            exit 0
        fi
    fi

    # Check if archive exists
    if [ ! -f "$KEYS_ARCHIVE" ]; then
        print_error "Keys archive not found at: $KEYS_ARCHIVE"
        print_info "This script requires the bootstrap keys archive to exist."
        exit 1
    fi

    # Create working directory
    mkdir -p "$WORK_DIR"
    cd "$WORK_DIR"

    # Decrypt existing archive with bootstrap password
    print_info "🔓 Decrypting key archive..."
    echo -n "Enter bootstrap password: "
    read -s bootstrap_password
    echo

    if ! echo "$bootstrap_password" | gpg --batch --yes --passphrase-fd 0 --decrypt "$KEYS_ARCHIVE" | tar xzf -; then
        print_error "Failed to decrypt archive. Wrong password?"
        exit 1
    fi

    print_success "Archive decrypted successfully"

    # Verify we have the expected keys
    if [ ! -f "id_sdev_extracted" ] || [ ! -f "age_keys_extracted" ]; then
        print_error "Missing expected keys in archive"
        ls -la
        exit 1
    fi

    print_info "Found keys:"
    echo "  ✓ SSH private key (id_sdev_extracted)"
    echo "  ✓ Age key (age_keys_extracted)"
    echo

    # Deploy keys to their proper locations
    print_info "🚀 Deploying keys..."

    # Ensure target directories exist
    mkdir -p "$HOME/.ssh" "$HOME/.config/sops/age"

    # Deploy SSH private key
    cp "id_sdev_extracted" "$HOME/.ssh/id_sdev"
    chmod 600 "$HOME/.ssh/id_sdev"
    print_success "✓ Deployed SSH private key to ~/.ssh/id_sdev"

    # Deploy age key
    cp "age_keys_extracted" "$HOME/.config/sops/age/keys.txt"
    chmod 600 "$HOME/.config/sops/age/keys.txt"
    print_success "✓ Deployed age key to ~/.config/sops/age/keys.txt"

    echo
    print_success "🎉 Key setup complete!"
}

main "$@"
