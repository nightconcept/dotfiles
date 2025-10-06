{
  config,
  lib,
  pkgs,
  ...
}: {
  config = lib.mkIf (config.desktops.hyprland.enable or false) {
    # Service to handle lid open events and refresh waybar
    systemd.user.services.waybar-lid-handler = {
      Unit = {
        Description = "Refresh waybar on lid open";
        After = ["graphical-session.target"];
      };

      Service = {
        Type = "simple";
        ExecStart = pkgs.writeShellScript "waybar-lid-handler" ''
          #!/usr/bin/env bash

          # Monitor for lid events
          ${pkgs.acpid}/bin/acpi_listen | while IFS= read -r line; do
            if echo "$line" | grep -q "button/lid.*open"; then
              # Wait a moment for network to stabilize
              sleep 2
              # Send signal to waybar to refresh custom modules
              ${pkgs.procps}/bin/pkill -SIGUSR2 waybar || true
            fi
          done
        '';
        Restart = "always";
        RestartSec = "5";
      };

      Install = {
        WantedBy = ["hyprland-session.target"];
      };
    };

    # Alternative: Use Hyprland's exec-once to monitor lid events
    wayland.windowManager.hyprland.extraConfig = lib.mkAfter ''
      # Refresh waybar on various system events
      bind = , XF86ScreenSaver, exec, pkill -SIGUSR2 waybar

      # Monitor lid events and refresh waybar
      exec-once = ${pkgs.writeShellScript "waybar-lid-monitor" ''
        #!/usr/bin/env bash
        while true; do
          # Check if lid state changed
          if [ -f /proc/acpi/button/lid/LID0/state ]; then
            state=$(cat /proc/acpi/button/lid/LID0/state | awk '{print $2}')
            if [ "$state" = "open" ] && [ "$last_state" = "closed" ]; then
              sleep 2
              pkill -SIGUSR2 waybar || true
            fi
            last_state=$state
          fi
          sleep 1
        done &
      ''}
    '';
  };
}
