{
  config,
  lib,
  pkgs,
  ...
}: {
  config = lib.mkIf (config.desktops.hyprland.enable or false) {
    # Create wofi-bluetooth script
    home.packages = with pkgs; [
      (writeShellScriptBin "wofi-bluetooth" ''
        #!/usr/bin/env bash

        # Get Bluetooth status
        get_status() {
          if bluetoothctl show 2>/dev/null | grep -q "Powered: yes"; then
            controller=$(bluetoothctl show 2>/dev/null | grep "Name" | cut -d ' ' -f 2-)
            if [ -z "$controller" ]; then
              echo "Bluetooth: On"
            else
              echo "$controller"
            fi
          else
            echo "Bluetooth: Off"
          fi
        }

        # Get connected devices
        get_connected_devices() {
          bluetoothctl devices Connected | cut -d ' ' -f 3-
        }

        # Toggle power
        toggle_power() {
          if bluetoothctl show 2>/dev/null | grep -q "Powered: yes"; then
            bluetoothctl power off
          else
            bluetoothctl power on
          fi
        }

        # Connect/disconnect device
        toggle_connection() {
          device="$1"
          mac=$(bluetoothctl devices | grep "$device" | cut -d ' ' -f 2)
          if bluetoothctl info "$mac" | grep -q "Connected: yes"; then
            bluetoothctl disconnect "$mac"
          else
            bluetoothctl connect "$mac"
          fi
        }

        # Scan for devices
        scan_devices() {
          bluetoothctl scan on &
          scan_pid=$!
          sleep 5
          kill $scan_pid 2>/dev/null
          bluetoothctl scan off
        }

        # Main menu
        show_menu() {
          # Build menu options
          options="󰂯 Power On/Off\n"
          options+="󰂰 Scan for Devices\n"
          options+="──────────────\n"

          # Add connected devices
          connected=$(get_connected_devices)
          if [ -n "$connected" ]; then
            while IFS= read -r device; do
              options+="󰂱 Connected: $device\n"
            done <<< "$connected"
            options+="──────────────\n"
          fi

          # Add paired devices
          while IFS= read -r line; do
            mac=$(echo "$line" | cut -d ' ' -f 2)
            name=$(echo "$line" | cut -d ' ' -f 3-)
            if ! bluetoothctl info "$mac" | grep -q "Connected: yes"; then
              options+="󰂲 $name\n"
            fi
          done < <(bluetoothctl devices Paired)

          # Show menu
          selected=$(echo -e "$options" | wofi --dmenu --prompt "Bluetooth" --width 350 --height 400)

          # Handle selection
          case "$selected" in
            *"Power"*)
              toggle_power
              ;;
            *"Scan"*)
              notify-send "Bluetooth" "Scanning for devices..." -i bluetooth
              scan_devices
              notify-send "Bluetooth" "Scan complete" -i bluetooth
              exec "$0"
              ;;
            *"Connected:"*)
              device=$(echo "$selected" | sed 's/.*Connected: //')
              toggle_connection "$device"
              ;;
            "󰂲 "*)
              device=$(echo "$selected" | sed 's/󰂲 //')
              toggle_connection "$device"
              ;;
          esac
        }

        # Check if bluetoothctl command exists
        if ! command -v bluetoothctl &> /dev/null; then
          notify-send "Bluetooth" "bluetoothctl not found. Please install bluez." -i bluetooth-disabled
          exit 1
        fi

        # Try to ensure bluetooth service is running
        if systemctl list-unit-files | grep -q bluetooth.service; then
          if ! systemctl is-active --quiet bluetooth.service; then
            sudo systemctl start bluetooth.service 2>/dev/null || true
          fi
        fi

        show_menu
      '')
    ];

    # Update waybar bluetooth module to use wofi-bluetooth
    programs.waybar.settings.mainBar.bluetooth = lib.mkForce {
      format = "󰂯";
      format-disabled = "󰂲";
      format-connected = "󰂱 {num_connections}";
      format-connected-battery = "󰂱 {device_battery_percentage}%";
      tooltip-format = "{controller_alias}\t{controller_address}";
      tooltip-format-connected = "{controller_alias}\t{controller_address}\n\n{device_enumerate}";
      tooltip-format-enumerate-connected = "{device_alias}\t{device_address}";
      tooltip-format-enumerate-connected-battery = "{device_alias}\t{device_address}\t{device_battery_percentage}%";
      on-click = "wofi-bluetooth";
    };
  };
}
