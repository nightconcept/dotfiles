{
  config,
  lib,
  pkgs,
  ...
}: {
  config = lib.mkIf (config.desktops.hyprland.enable or false) {
    # Create a systemd user service to monitor power state changes
    systemd.user.services.hypridle-power-monitor = {
      Unit = {
        Description = "Monitor power state changes and restart hypridle";
        After = ["graphical-session.target"];
      };

      Service = {
        Type = "simple";
        ExecStart = "${pkgs.writeShellScript "hypridle-power-monitor" ''
          #!/usr/bin/env bash

          # Function to get current power state
          get_power_state() {
            if [[ -f /sys/class/power_supply/AC/online ]]; then
              cat /sys/class/power_supply/AC/online
            elif [[ -f /sys/class/power_supply/ADP1/online ]]; then
              cat /sys/class/power_supply/ADP1/online
            elif [[ -f /sys/class/power_supply/ACAD/online ]]; then
              cat /sys/class/power_supply/ACAD/online
            else
              echo "1"  # Assume plugged in if we can't detect
            fi
          }

          last_state=$(get_power_state)

          while true; do
            sleep 5
            current_state=$(get_power_state)

            if [[ "$current_state" != "$last_state" ]]; then
              echo "Power state changed from $last_state to $current_state, restarting hypridle..."
              hypridle-wrapper &
              last_state=$current_state
            fi
          done
        ''}";
        Restart = "always";
        RestartSec = "10";
      };

      Install = {
        WantedBy = ["hyprland-session.target"];
      };
    };
  };
}
