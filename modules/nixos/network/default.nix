{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib) mkIf;
  cfg = config.modules.nixos.network;

  # Import our custom lib functions
  moduleLib = import ../../../lib/module {inherit lib;};
  inherit (moduleLib) mkBoolOpt mkOpt enabled disabled;
in {
  options.modules.nixos.network = {
    networkManager = mkBoolOpt true "Enable NetworkManager for network configuration";

    mdns = mkBoolOpt true "Enable mDNS for .local domain resolution";

    hosts = mkOpt (lib.types.attrsOf (lib.types.listOf lib.types.str)) {
      "192.168.1.100" = ["mog" "mog.local"];
    } "Static host entries";
  };

  config = lib.mkMerge [
    (mkIf cfg.networkManager {
      networking.networkmanager.enable = true;
    })

    (mkIf cfg.mdns {
      services.avahi = {
        enable = true;
        nssmdns4 = true;
        nssmdns6 = true;
        publish = {
          enable = true;
          addresses = true;
          workstation = true;
        };
      };
    })

    {
      networking.hosts = cfg.hosts;
    }
  ];
}
