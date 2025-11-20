#!/usr/bin/env bash

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=== VNC Ultimate Fix Script ===${NC}\n"

info() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Request sudo for package installation
echo -e "${YELLOW}This script may need sudo to install packages.${NC}"
sudo -v
while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &

# Step 1: Check what VNC servers are available
info "Checking for VNC server installations..."
echo ""

VNCSERVER=""
if command -v tigervncserver &> /dev/null; then
    VNCSERVER="tigervncserver"
    success "Found tigervncserver at $(which tigervncserver)"
elif command -v vncserver &> /dev/null && ! vncserver -help 2>&1 | grep -q "usage:.*wrapped"; then
    VNCSERVER="vncserver"
    success "Found vncserver at $(which vncserver)"
else
    warning "No working VNC server found, installing from Debian repos..."
    sudo apt update -qq
    sudo apt install -y tigervnc-standalone-server tigervnc-common dbus-x11
    VNCSERVER="tigervncserver"
    success "Installed tigervncserver"
fi

echo ""
info "Using VNC server: $VNCSERVER"
echo ""

# Step 2: Kill any existing processes
info "Cleaning up any existing VNC processes..."
pkill -9 Xvnc 2>/dev/null || true
pkill -9 vnc 2>/dev/null || true
rm -f /tmp/.X1-lock /tmp/.X11-unix/X1 2>/dev/null || true
sleep 2
success "Cleanup complete"

# Step 3: Setup directories and config
info "Setting up VNC configuration..."
mkdir -p ~/.vnc

# Create VNC config for both ~/.vnc and ~/.config/tigervnc
cat > ~/.vnc/config << 'EOF'
geometry=1920x1080
depth=24
dpi=96
localhost=no
desktop=debian-vnc
EOF

# TigerVNC also uses ~/.config/tigervnc/config
mkdir -p ~/.config/tigervnc
cat > ~/.config/tigervnc/config << 'EOF'
geometry=1920x1080
depth=24
dpi=96
localhost=no
desktop=debian-vnc
session=custom
EOF

success "VNC config created"

# Step 4: Check/set password
if [ ! -f ~/.vnc/passwd ]; then
    warning "No VNC password found"
    echo "Enter VNC password (min 6 characters):"
    vncpasswd
else
    info "VNC password exists"
fi

# Step 5: Create startup scripts
info "Creating startup scripts..."

# First, detect what desktop environments are available
HAS_KDE=false
HAS_XFCE=false
HAS_GNOME=false

command -v startplasma-x11 &> /dev/null && HAS_KDE=true
command -v startxfce4 &> /dev/null && HAS_XFCE=true
command -v gnome-session &> /dev/null && HAS_GNOME=true

if [ "$HAS_KDE" = true ]; then
    info "Detected KDE Plasma"
    DESKTOP_CHOICE="KDE"
elif [ "$HAS_XFCE" = true ]; then
    info "Detected XFCE"
    DESKTOP_CHOICE="XFCE"
elif [ "$HAS_GNOME" = true ]; then
    info "Detected GNOME"
    DESKTOP_CHOICE="GNOME"
else
    warning "No desktop environment detected, installing XFCE..."
    sudo apt install -y xfce4 xfce4-goodies
    DESKTOP_CHOICE="XFCE"
fi

# TigerVNC uses both ~/.vnc/xstartup AND looks for a custom session
# We need to set both to ensure it works

# Create the xstartup file
if [ "$DESKTOP_CHOICE" = "KDE" ]; then
    STARTUP_CMD="dbus-launch --exit-with-session startplasma-x11"
elif [ "$DESKTOP_CHOICE" = "XFCE" ]; then
    STARTUP_CMD="dbus-launch --exit-with-session startxfce4"
else
    STARTUP_CMD="dbus-launch --exit-with-session gnome-session"
fi

# Create ~/.vnc/xstartup
cat > ~/.vnc/xstartup << EOF
#!/bin/bash
exec >> ~/.vnc/xstartup.log 2>&1
echo "=== VNC Session Started: \$(date) ==="
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS
export XKL_XMODMAP_DISABLE=1
echo "Executing: $STARTUP_CMD"
exec $STARTUP_CMD
EOF
chmod +x ~/.vnc/xstartup

# Also create a systemd-compatible session file for TigerVNC
mkdir -p ~/.config/tigervnc
cat > ~/.config/tigervnc/xstartup << EOF
#!/bin/bash
exec >> ~/.vnc/xstartup.log 2>&1
echo "=== TigerVNC Session Started: \$(date) ==="
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS
export XKL_XMODMAP_DISABLE=1
echo "Executing: $STARTUP_CMD"
exec $STARTUP_CMD
EOF
chmod +x ~/.config/tigervnc/xstartup

# Also create a "custom" session wrapper that TigerVNC will use
# This is what gets called when session=custom is set
cat > ~/.config/tigervnc/custom << EOF
#!/bin/bash
exec >> ~/.vnc/session.log 2>&1
echo "=== Custom TigerVNC Session: \$(date) ==="
echo "USER: \$USER"
echo "HOME: \$HOME"
echo "DISPLAY: \$DISPLAY"

# Source the user's xstartup
if [ -f "\$HOME/.vnc/xstartup" ]; then
    echo "Running \$HOME/.vnc/xstartup"
    exec "\$HOME/.vnc/xstartup"
else
    echo "No xstartup found, running default"
    exec $STARTUP_CMD
fi
EOF
chmod +x ~/.config/tigervnc/custom

# IMPORTANT: Also create ~/.xsession which Xtigervnc-session will use
# This is the key file that actually gets executed!
cat > ~/.xsession << EOF
#!/bin/bash
exec >> ~/.vnc/session.log 2>&1
echo "=== .xsession Started: \$(date) ==="
echo "USER: \$USER"
echo "HOME: \$HOME"
echo "DISPLAY: \$DISPLAY"

unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS
export XKL_XMODMAP_DISABLE=1

echo "Starting: $STARTUP_CMD"
exec $STARTUP_CMD
EOF
chmod +x ~/.xsession

success "Created startup scripts for $DESKTOP_CHOICE"
info "TigerVNC will use ~/.xsession for session startup"

# Step 6: Start VNC server with the right command
info "Starting VNC server..."
echo ""

# Try starting with proper syntax - EXPLICITLY disable localhost-only mode
if [ "$VNCSERVER" = "tigervncserver" ]; then
    tigervncserver :1 -localhost no 2>&1 | tee /tmp/vnc-start.log
else
    vncserver :1 -localhost no 2>&1 | tee /tmp/vnc-start.log
fi

sleep 3

# Step 7: Verify it's running
echo ""
info "Verifying VNC server..."

# Check both process name variants
if pgrep -f "X.*vnc.*:1" > /dev/null || pgrep -f "Xtigervnc" > /dev/null; then
    success "VNC server is running!"

    # Wait for desktop to start
    info "Waiting for desktop environment to start..."
    sleep 10

    # Check for desktop processes
    if pgrep -f "plasma|xfce|gnome-shell" > /dev/null; then
        success "Desktop environment is running!"
    else
        warning "Desktop environment may not have started yet. Give it a few more seconds."
    fi

    # Show connection info
    echo ""
    echo -e "${GREEN}=== SUCCESS! VNC Server is Running ===${NC}"
    echo ""
    IP_ADDR=$(hostname -I | awk '{print $1}')
    echo "Connection Info:"
    echo "  IP:Port    : $IP_ADDR:5901"
    echo "  Display    : :1"
    echo "  Desktop    : $DESKTOP_CHOICE"
    echo ""
    echo "Connect with any VNC client using:"
    echo "  Address: $IP_ADDR:5901"
    echo "  Password: (the one you set)"
    echo ""

else
    # Check if the server actually started by looking at the logs
    if grep -q "New Xtigervnc server" /tmp/vnc-start.log 2>/dev/null; then
        success "VNC server started (detected from logs)"
        IP_ADDR=$(hostname -I | awk '{print $1}')
        echo ""
        echo -e "${GREEN}=== SUCCESS! VNC Server is Running ===${NC}"
        echo ""
        echo "Connection Info:"
        echo "  IP:Port    : $IP_ADDR:5901"
        echo "  Display    : :1"
        echo ""
    else
        error "VNC server may have failed to start"
        echo "Startup log:"
        cat /tmp/vnc-start.log 2>/dev/null || echo "No log found"
    fi
fi

# Step 8: Show useful commands
echo ""
echo -e "${BLUE}=== Useful Commands ===${NC}"
echo "Check processes: ps aux | grep Xvnc"
echo "Check logs: cat ~/.vnc/*.log"
echo "Stop VNC: $VNCSERVER -kill :1"
echo "Restart: $VNCSERVER :1"
echo ""

# Step 9: Show logs if they exist
if [ -f ~/.vnc/xstartup.log ]; then
    echo -e "${BLUE}=== Startup Log ===${NC}"
    cat ~/.vnc/xstartup.log
    echo ""
fi

# Check multiple possible log locations
HOSTNAME=$(hostname)
SHORTHOST=$(hostname -s)

echo -e "${BLUE}=== Checking for VNC logs ===${NC}"
for logfile in \
    ~/.vnc/$HOSTNAME:1.log \
    ~/.vnc/$SHORTHOST:1.log \
    ~/.config/tigervnc/$HOSTNAME:1.log \
    ~/.config/tigervnc/$SHORTHOST:1.log \
    /var/log/Xtigervnc.1.log \
    ~/.vnc/*.log \
    ~/.config/tigervnc/*.log
do
    if [ -f "$logfile" ] 2>/dev/null; then
        echo "Found log: $logfile"
        echo -e "${BLUE}=== VNC Server Log (last 30 lines) ===${NC}"
        tail -30 "$logfile"
        echo ""
        break
    fi
done

# Show tigervnc session info
echo -e "${BLUE}=== TigerVNC Session Info ===${NC}"
if [ -f ~/.config/tigervnc/config ]; then
    echo "Config:"
    cat ~/.config/tigervnc/config
fi
