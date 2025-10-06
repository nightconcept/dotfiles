# Minimal server configuration
{
  config,
  lib,
  pkgs,
  ...
}: {
  imports = [
    ./base.nix
  ];

  modules.home.programs.shell = {
    fish.enable = true;
    starship.enable = true;
    zoxide.enable = true;
  };

  modules.home.programs.vscode.enable = true;

  # Additional server-specific packages
  home.packages = with pkgs; [
    lazydocker
  ];
}
