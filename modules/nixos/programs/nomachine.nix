{
  lib,
  config,
  pkgs,
  ...
}: let
  inherit (lib) mkIf mkEnableOption;
  inherit (lib.types) package;

  # Import our custom lib functions
  moduleLib = import ../../../lib/module {inherit lib;};
  inherit (moduleLib) mkOpt;

  cfg = config.modules.nixos.programs.nomachine;
in {
  options.modules.nixos.programs.nomachine = {
    enable = mkEnableOption "NoMachine remote desktop client";

    package = mkOpt package pkgs.nomachine-client "The NoMachine client package to use";
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [cfg.package];

    nixpkgs.config.allowUnfreePredicate = pkg:
      lib.getName pkg == "nomachine-client";
  };
}
