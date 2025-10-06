{
  config,
  lib,
  pkgs,
  ...
}: {
  imports = [
    ./hyprlock.nix
    ./hypridle-power.nix
  ];

  config = lib.mkIf (config.desktops.hyprland.enable or false) {
    # Create scripts to handle power state detection
    home.packages = with pkgs; [
      (writeShellScriptBin "hypridle-wrapper" ''
        #!/usr/bin/env bash

        # Kill any existing hypridle instances
        killall hypridle 2>/dev/null

        # Check if AC adapter is connected (on battery = 0, on AC = 1)
        on_ac() {
          if [[ -f /sys/class/power_supply/AC/online ]]; then
            [[ $(cat /sys/class/power_supply/AC/online) -eq 1 ]]
          elif [[ -f /sys/class/power_supply/ADP1/online ]]; then
            [[ $(cat /sys/class/power_supply/ADP1/online) -eq 1 ]]
          elif [[ -f /sys/class/power_supply/ACAD/online ]]; then
            [[ $(cat /sys/class/power_supply/ACAD/online) -eq 1 ]]
          else
            # Assume plugged in if we can't detect
            true
          fi
        }

        # Start hypridle with appropriate config
        if on_ac; then
          hypridle -c ~/.config/hypr/hypridle-plugged.conf
        else
          hypridle -c ~/.config/hypr/hypridle-unplugged.conf
        fi
      '')
    ];

    # Hypridle configuration for when laptop is PLUGGED IN
    xdg.configFile."hypr/hypridle-plugged.conf".text = ''
      general {
        lock_cmd = pidof hyprlock || hyprlock       # avoid starting multiple hyprlock instances
        before_sleep_cmd = loginctl lock-session    # lock before suspend
        after_sleep_cmd = hyprctl dispatch dpms on  # turn on screen after resume
      }

      # Dim screen after 15 minutes when plugged in
      listener {
        timeout = 900
        on-timeout = brightnessctl -s set 10%       # dim screen to 10%
        on-resume = brightnessctl -r                # restore brightness
      }

      # Lock screen after 20 minutes when plugged in
      listener {
        timeout = 1200
        on-timeout = loginctl lock-session          # lock screen
      }

      # Turn off display after 30 minutes when plugged in
      listener {
        timeout = 1800
        on-timeout = hyprctl dispatch dpms off      # turn off screen
        on-resume = hyprctl dispatch dpms on        # turn on screen
      }

      # Sleep after 1 hour when plugged in
      listener {
        timeout = 3600
        on-timeout = systemctl suspend              # suspend system
      }
    '';

    # Hypridle configuration for when laptop is UNPLUGGED (on battery)
    xdg.configFile."hypr/hypridle-unplugged.conf".text = ''
      general {
        lock_cmd = pidof hyprlock || hyprlock       # avoid starting multiple hyprlock instances
        before_sleep_cmd = loginctl lock-session    # lock before suspend
        after_sleep_cmd = hyprctl dispatch dpms on  # turn on screen after resume
      }

      # Dim screen after 5 minutes when on battery
      listener {
        timeout = 300
        on-timeout = brightnessctl -s set 10%       # dim screen to 10%
        on-resume = brightnessctl -r                # restore brightness
      }

      # Lock screen after 10 minutes when on battery
      listener {
        timeout = 600
        on-timeout = loginctl lock-session          # lock screen
      }

      # Turn off display after 15 minutes when on battery
      listener {
        timeout = 900
        on-timeout = hyprctl dispatch dpms off      # turn off screen
        on-resume = hyprctl dispatch dpms on        # turn on screen
      }

      # Sleep after 20 minutes when on battery
      listener {
        timeout = 1200
        on-timeout = systemctl suspend              # suspend system
      }
    '';
  };
}
