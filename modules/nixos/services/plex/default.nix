{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib) mkIf;
  cfg = config.modules.nixos.services.plex;

  # Import our custom lib functions
  moduleLib = import ../../../../lib/module {inherit lib;};
  inherit (moduleLib) mkBoolOpt mkOpt enabled disabled;
in {
  options.modules.nixos.services.plex = {
    enable = mkBoolOpt false "Enable Plex Media Server";

    package = mkOpt lib.types.package pkgs.plex "The plex package to use";

    user = mkOpt lib.types.str "danny" "User to run Plex service as";

    openFirewall = mkBoolOpt true "Open firewall ports for Plex";

    ports = mkOpt (lib.types.listOf lib.types.port) [
      32400 # Plex Media Server
      1900 # UPnP/DLNA
      5353 # mDNS
      8324 # Plex for Roku
      32410 # GDM network discovery
      32412 # GDM network discovery
      32413 # GDM network discovery
      32414 # GDM network discovery
      32469 # Plex DLNA Server
    ] "TCP ports to open for Plex service";
  };

  config = mkIf cfg.enable {
    services.plex = {
      enable = true;
      package = cfg.package;
      openFirewall = cfg.openFirewall;
      user = cfg.user;
    };

    networking.firewall.allowedTCPPorts = cfg.ports;
  };
}
