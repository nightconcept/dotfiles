# Linux (non-NixOS) Desktops
{
  config,
  lib,
  pkgs,
  ...
}: {
  imports = [
    ./base.nix
    ../../modules/home
  ];

  # Disable GPU driver management from targets.genericLinux (not needed on this system)
  targets.genericLinux.gpu.enable = false;

  # Reminder to install ghostty manually via native package manager
  home.activation.checkGhostty = lib.hm.dag.entryAfter ["writeBoundary"] ''
    if ! [ -x /usr/bin/ghostty ] && ! [ -x /usr/local/bin/ghostty ]; then
      echo "NOTE: Ghostty is not installed. Please install it manually:"
      if [ -f /etc/arch-release ]; then
        echo "  Arch Linux: yay -S ghostty"
      elif [ -f /etc/debian_version ] || [ -f /etc/lsb-release ]; then
        echo "  Debian/Ubuntu: Run ./scripts/install-terminal.sh"
      else
        echo "  Visit https://ghostty.org for installation instructions"
      fi
    fi
  '';

  modules.home.programs = {
    chromium.enable = true;
    mise.enable = true;
    # Use configOnly - install ghostty manually via native package manager
    ghostty.configOnly = true;
    herdr.enable = true;
    spotify.enable = true;
    zotero.enable = true;
    # wezterm.configOnly = true; # Replaced by ghostty - install manually if needed
    xdg.enable = true;
    shell = {
      fish.enable = true;
      starship.enable = true;
      zoxide.enable = true;
    };
  };

  fonts.fontconfig.enable = true;

  home.packages = with pkgs; [
    beamPackages.erlang
    github-desktop
    gitnuro
    gleam
    kdePackages.xdg-desktop-portal-kde
    nerd-fonts.fira-code
    nerd-fonts.fira-mono
    obsidian
    # User-space emulator binary only. Transparent foreign ELF execution
    # still requires system binfmt registration outside Home Manager.
    qemu-user
    vlc
    vscode
    xdg-utils
  ];

  stylix.targets.gtk.enable = lib.mkForce false;
}
