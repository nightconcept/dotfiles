{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib) mkIf;
  cfg = config.modules.nixos.kernel;

  # Import our custom lib functions
  moduleLib = import ../../../lib/module {inherit lib;};
  inherit (moduleLib) mkOpt;
in {
  options.modules.nixos.kernel = {
    type =
      mkOpt (lib.types.enum ["lts" "zen" "latest" "default"]) "default"
      "Kernel type to use (lts, zen, latest, or default)";

    customPackage =
      mkOpt (lib.types.nullOr lib.types.package) null
      "Custom kernel package to use (overrides type selection)";
  };

  config = {
    boot.kernelPackages =
      if cfg.customPackage != null
      then cfg.customPackage
      else if cfg.type == "lts"
      then pkgs.linuxPackages_6_12 # Latest LTS as of Jan 2025
      else if cfg.type == "zen"
      then pkgs.linuxPackages_zen
      else if cfg.type == "latest"
      then pkgs.linuxPackages_latest
      else pkgs.linuxPackages; # Default stable kernel
  };
}
