# Basic networking configuration module
{
  config,
  lib,
  ...
}:
with lib; let
  cfg = config.modules.nixos.networking.base;
in {
  options.modules.nixos.networking.base = {
    enable = mkOption {
      type = types.bool;
      default = true;
      description = "Enable basic networking";
    };

    hostName = mkOption {
      type = types.str;
      default = "nixos";
      description = "System hostname";
    };
  };

  config = mkIf cfg.enable {
    networking.hostName = cfg.hostName;
    networking.networkmanager.enable = true;
    networking.firewall.enable = true;
    networking.firewall.allowedTCPPorts = [];
    networking.firewall.allowedUDPPorts = [];
  };
}
