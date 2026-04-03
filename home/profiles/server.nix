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

  # Disable sops for standalone server config (no known homeDirectory)
  modules.home.secrets.sops.enable = lib.mkForce false;

  modules.home.programs = {
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
