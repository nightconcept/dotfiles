# Network drives (CIFS/SMB) configuration module
{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.modules.nixos.storage.networkDrives;

  # Default titan mount configuration
  titanMount = {
    name = "titan";
    source = "//192.168.1.167/titan";
    credentials = "/run/secrets/network/titan_credentials";
  };
in {
  options.modules.nixos.storage.networkDrives = {
    enable = mkEnableOption "Network drive mounting";

    enableTitan = mkOption {
      type = types.bool;
      default = false;
      description = "Enable default titan network mount";
    };

    titanIdleTimeout = mkOption {
      type = types.int;
      default = 60;
      description = "Timeout in seconds before unmounting titan when idle (0 to disable)";
    };

    mounts = mkOption {
      type = types.listOf (types.submodule {
        options = {
          name = mkOption {
            type = types.str;
            description = "Mount point name";
          };
          source = mkOption {
            type = types.str;
            description = "Network share path (e.g., //192.168.1.167/share)";
          };
          credentials = mkOption {
            type = types.str;
            default = null;
            description = "Path to credentials file";
          };
        };
      });
      default = [];
      description = "Network mounts to configure";
    };
  };

  config = mkIf cfg.enable (let
    # Combine user-defined mounts with titan if enabled
    allMounts = cfg.mounts ++ (optionals cfg.enableTitan [titanMount]);
  in {
    # Create mount points
    systemd.tmpfiles.rules =
      map (
        mount: "d /mnt/${mount.name} 0755 root root -"
      )
      allMounts;

    # Create mount units
    systemd.mounts =
      map (mount: {
        description = "Mount ${mount.name} network share";
        what = mount.source;
        where = "/mnt/${mount.name}";
        type = "cifs";
        options = "credentials=${mount.credentials},uid=1000,gid=100,iocharset=utf8,nofail,_netdev,x-systemd.automount,x-systemd.mount-timeout=10";
        wantedBy = [];
        after = ["network-online.target" "nss-lookup.target"];
        wants = ["network-online.target"];
        requiredBy = [];
      })
      allMounts;

    # Create automount units
    systemd.automounts =
      map (mount: {
        description = "Automount ${mount.name} network share";
        where = "/mnt/${mount.name}";
        wantedBy = ["multi-user.target"];
        automountConfig = {
          TimeoutIdleSec =
            if mount.name == "titan"
            then toString cfg.titanIdleTimeout
            else "60";
          DirectoryMode = "0755";
        };
      })
      allMounts;
  });
}
