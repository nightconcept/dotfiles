#!/usr/bin/env bash
# Install terminal emulators (Ghostty/WezTerm) on Debian/Ubuntu

set -e

# Check if running on Debian-based system
if ! command -v apt &> /dev/null; then
    echo "Error: This script requires apt (Debian/Ubuntu-based system)"
    exit 1
fi

echo "Terminal Emulator Installation Script"
echo "====================================="
echo
echo "Which terminal emulator would you like to install?"
echo "1) Ghostty"
echo "2) WezTerm"
echo "3) Both"
echo "0) Exit"
echo
read -p "Enter your choice (0-3): " choice

install_ghostty() {
    echo
    echo "Installing Ghostty from debian.griffo.io repository..."
    echo

    # Download and add the GPG key
    echo "Adding GPG key..."
    curl -sS https://debian.griffo.io/EA0F721D231FDD3A0A17B9AC7808B4DD62C41256.asc | \
        sudo gpg --yes --dearmor -o /etc/apt/trusted.gpg.d/debian.griffo.io.gpg

    # Add the repository
    echo "Adding repository..."
    echo "deb https://debian.griffo.io/apt $(lsb_release -sc) main" | \
        sudo tee /etc/apt/sources.list.d/debian.griffo.io.list

    # Update apt cache
    echo "Updating apt cache..."
    sudo apt update

    # Install ghostty
    echo "Installing ghostty..."
    sudo apt install -y ghostty

    echo
    echo "Ghostty installed successfully!"
    ghostty --version
}

install_wezterm() {
    echo
    echo "Which version of WezTerm would you like to install?"
    echo "1) Stable (wezterm)"
    echo "2) Nightly (wezterm-nightly) [Recommended]"
    echo
    read -p "Enter your choice (1 or 2): " wez_choice

    case $wez_choice in
        1)
            PACKAGE="wezterm"
            echo "Selected: Stable version"
            ;;
        2)
            PACKAGE="wezterm-nightly"
            echo "Selected: Nightly version"
            ;;
        *)
            echo "Invalid choice. Defaulting to nightly."
            PACKAGE="wezterm-nightly"
            ;;
    esac

    echo
    echo "Installing $PACKAGE from apt.fury.io repository..."
    echo

    # Download and add the GPG key
    echo "Adding GPG key..."
    curl -fsSL https://apt.fury.io/wez/gpg.key | \
        sudo gpg --yes --dearmor -o /usr/share/keyrings/wezterm-fury.gpg

    # Add the repository
    echo "Adding repository..."
    echo 'deb [signed-by=/usr/share/keyrings/wezterm-fury.gpg] https://apt.fury.io/wez/ * *' | \
        sudo tee /etc/apt/sources.list.d/wezterm.list

    # Set proper permissions
    sudo chmod 644 /usr/share/keyrings/wezterm-fury.gpg

    # Update apt cache
    echo "Updating apt cache..."
    sudo apt update

    # Install wezterm
    echo "Installing $PACKAGE..."
    sudo apt install -y "$PACKAGE"

    echo
    echo "$PACKAGE installed successfully!"
    wezterm --version
}

case $choice in
    0)
        echo "Exiting."
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
        echo "Invalid choice. Exiting."
        exit 1
        ;;
esac

echo
echo "Installation complete!"
