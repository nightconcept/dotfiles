{
  config,
  lib,
  pkgs,
  ...
}: {
  config = lib.mkIf (config.desktops.hyprland.enable or false) {
    # Install gnome-keyring and libsecret for secret management
    home.packages = with pkgs; [
      gnome-keyring
      libsecret
      seahorse # GUI for managing keyring
    ];

    # Enable gnome-keyring service
    services.gnome-keyring = {
      enable = true;
      components = ["pkcs11" "secrets" "ssh"];
    };

    # Set up environment variables for secret service
    home.sessionVariables = {
      SSH_AUTH_SOCK = "$XDG_RUNTIME_DIR/keyring/ssh";
    };

    # Start gnome-keyring with Hyprland
    wayland.windowManager.hyprland.settings = {
      exec-once = [
        "gnome-keyring-daemon --start --components=pkcs11,secrets,ssh"
        "dbus-update-activation-environment --systemd DISPLAY WAYLAND_DISPLAY SWAYSOCK XDG_CURRENT_DESKTOP"
        "dbus-update-activation-environment --systemd --all"
      ];
    };
  };
}
