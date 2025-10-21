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

  # Reminder to install ghostty manually via native package manager
  home.activation.checkGhostty = lib.hm.dag.entryAfter ["writeBoundary"] ''
    if ! command -v ghostty &> /dev/null; then
      echo "NOTE: Ghostty is not installed. Please install it manually:"
      if [ -f /etc/arch-release ]; then
        echo "  Arch Linux: yay -S ghostty"
      elif [ -f /etc/debian_version ]; then
        echo "  Debian/Ubuntu: Run ./scripts/install-terminal-debian.sh"
      else
        echo "  Visit https://ghostty.org for installation instructions"
      fi
    fi
  '';

  modules.home.programs = {
    # Use configOnly - install ghostty manually via native package manager
    ghostty.configOnly = true;
    spotify.enable = true;
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
    github-desktop
    gitnuro
    kdePackages.xdg-desktop-portal-kde
    nerd-fonts.fira-code
    nerd-fonts.fira-mono
    obsidian
    uv
    vlc
    vscode
    xdg-utils
  ];

  stylix.targets.gtk.enable = lib.mkForce false;
}
