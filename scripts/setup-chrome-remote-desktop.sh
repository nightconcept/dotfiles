#!/usr/bin/env bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== Chrome Remote Desktop Setup Script ===${NC}\n"

# Force sudo refresh upfront
echo -e "${YELLOW}This script requires sudo access.${NC}"
echo "Please enter your password to continue..."
sudo -v

# Keep sudo alive in background
while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &

# Function to print colored messages
info() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Check if running on Debian/Ubuntu
if ! command -v apt &> /dev/null; then
    error "This script requires apt (Debian/Ubuntu)"
    exit 1
fi

# Step 1: Install Chrome Remote Desktop
info "Installing Chrome Remote Desktop..."
if dpkg -l | grep -q chrome-remote-desktop; then
    success "Chrome Remote Desktop already installed"
else
    info "Downloading Chrome Remote Desktop..."
    wget -q https://dl.google.com/linux/direct/chrome-remote-desktop_current_amd64.deb -O /tmp/chrome-remote-desktop.deb

    info "Installing package..."
    sudo dpkg -i /tmp/chrome-remote-desktop.deb 2>/dev/null || true
    sudo apt --fix-broken install -y

    rm /tmp/chrome-remote-desktop.deb
    success "Chrome Remote Desktop installed"
fi

# Step 2: Create configuration directory
info "Creating configuration directory..."
mkdir -p ~/.config/chrome-remote-desktop
success "Configuration directory created"

# Step 3: Detect and configure desktop session
info "Detecting desktop environment..."
echo ""

# Try to auto-detect desktop environment
DESKTOP_SESSION_CMD=""
if [ -d /usr/share/xsessions/ ]; then
    echo "Available desktop sessions:"
    echo ""

    sessions=()
    index=1

    for desktop_file in /usr/share/xsessions/*.desktop; do
        if [ -f "$desktop_file" ]; then
            name=$(grep "^Name=" "$desktop_file" | cut -d= -f2)
            exec_cmd=$(grep "^Exec=" "$desktop_file" | cut -d= -f2)
            sessions+=("$exec_cmd")
            echo "  $index) $name ($exec_cmd)"
            ((index++))
        fi
    done

    echo ""
    if [ ${#sessions[@]} -gt 0 ]; then
        read -p "Select desktop session number [1-${#sessions[@]}]: " choice

        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#sessions[@]}" ]; then
            DESKTOP_SESSION_CMD="${sessions[$((choice-1))]}"
        else
            warning "Invalid selection, using first option"
            DESKTOP_SESSION_CMD="${sessions[0]}"
        fi
    fi
else
    warning "Could not find /usr/share/xsessions/"
    read -p "Enter your desktop start command (e.g., startxfce4, gnome-session): " DESKTOP_SESSION_CMD
fi

if [ -z "$DESKTOP_SESSION_CMD" ]; then
    error "No desktop session command configured"
    exit 1
fi

info "Creating ~/.chrome-remote-desktop-session with: $DESKTOP_SESSION_CMD"
echo "exec /etc/X11/Xsession '$DESKTOP_SESSION_CMD'" > ~/.chrome-remote-desktop-session
chmod +x ~/.chrome-remote-desktop-session
success "Desktop session configured"

# Step 4: Add user to chrome-remote-desktop group
info "Adding user to chrome-remote-desktop group..."
if groups $USER | grep -q chrome-remote-desktop; then
    success "User already in chrome-remote-desktop group"
else
    sudo usermod -a -G chrome-remote-desktop $USER
    success "User added to chrome-remote-desktop group"
    warning "You will need to log out and log back in for group changes to take effect"
fi

# Step 5: Set default display size
info "Setting default display size..."
if grep -q "CHROME_REMOTE_DESKTOP_DEFAULT_DESKTOP_SIZES" ~/.profile 2>/dev/null; then
    success "Display size already configured in ~/.profile"
else
    echo "" >> ~/.profile
    echo "# Chrome Remote Desktop default display size" >> ~/.profile
    echo "export CHROME_REMOTE_DESKTOP_DEFAULT_DESKTOP_SIZES=1920x1080" >> ~/.profile
    success "Display size configured (1920x1080)"
fi

# Step 6: Instructions for browser setup
echo ""
echo -e "${GREEN}=== Setup Complete! ===${NC}"
echo ""
echo "Next steps to enable remote access:"
echo ""
echo "1. ${YELLOW}Log out and log back in${NC} (required for group membership)"
echo ""
echo "2. Open Chrome and navigate to:"
echo "   ${BLUE}https://remotedesktop.google.com/access${NC}"
echo ""
echo "3. Under 'Set up Remote Access', click ${GREEN}Turn On${NC}"
echo ""
echo "4. Give your computer a name (e.g., 'Debian Laptop')"
echo ""
echo "5. Set a PIN (at least 6 digits) - ${YELLOW}remember this!${NC}"
echo ""
echo "6. Click ${GREEN}Start${NC}"
echo ""
echo "Then from any device:"
echo "  - Go to ${BLUE}https://remotedesktop.google.com/access${NC}"
echo "  - Sign in with the same Google account"
echo "  - Click on your computer and enter the PIN"
echo ""
echo -e "${BLUE}Troubleshooting:${NC}"
echo "  Check status: sudo systemctl status chrome-remote-desktop@$USER"
echo "  View logs: cat /tmp/chrome_remote_desktop_*"
echo ""
echo "Press Enter to open Chrome to remotedesktop.google.com/access"
read -r

# Try to open Chrome to the setup page
if command -v google-chrome &> /dev/null; then
    google-chrome https://remotedesktop.google.com/access &
elif command -v chromium &> /dev/null; then
    chromium https://remotedesktop.google.com/access &
else
    warning "Could not find Chrome or Chromium to open automatically"
    echo "Please manually navigate to: https://remotedesktop.google.com/access"
fi

success "Setup script completed!"
