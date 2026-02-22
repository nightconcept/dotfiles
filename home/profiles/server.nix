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

  modules.home.programs = {
    openclaw.enable = true;
    shell = {
      fish.enable = true;
      starship.enable = true;
      zoxide.enable = true;
    };
  };

  # Additional server-specific packages
  home.packages = with pkgs; [
    lazydocker
  ];
}
