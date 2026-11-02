# Plex Media Server Container Module
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.modules.nixos.docker.containers.plex;
  containerName = "plex";
  containerPath = "/var/lib/docker-containers/${containerName}";
  usesTitan = lib.hasPrefix "/mnt/titan" cfg.mediaPath;
in {
  options.modules.nixos.docker.containers.plex = {
    enable = lib.mkEnableOption "Plex Media Server container";

    timezone = lib.mkOption {
      type = lib.types.str;
      default = "America/Chicago";
      description = "Timezone for Plex";
    };

    dataPath = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/plex/Plex Media Server";
      description = "Plex data directory (database, metadata, Preferences.xml). The NixOS service default.";
    };

    mediaPath = lib.mkOption {
      type = lib.types.str;
      default = "/mnt/titan";
      description = "Media root, mounted at the same path inside the container";
    };

    uid = lib.mkOption {
      type = lib.types.int;
      default = 1000;
      description = "UID Plex runs as; must own dataPath";
    };

    gid = lib.mkOption {
      type = lib.types.int;
      default = 193;
      description = "GID Plex runs as (the NixOS plex group)";
    };

    enableWatchtower = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable Watchtower auto-updates";
    };
  };

  config = lib.mkIf cfg.enable {
    virtualisation.docker.enable = true;

    systemd.tmpfiles.rules = [
      "d ${containerPath} 0755 root root -"
      "d ${containerPath}/config 0755 ${toString cfg.uid} ${toString cfg.gid} -"
      "d ${containerPath}/transcode 0755 ${toString cfg.uid} ${toString cfg.gid} -"
    ];

    systemd.services."docker-container-${containerName}" = {
      description = "Plex Media Server Container";
      after = ["docker.service"] ++ lib.optionals usesTitan ["mnt-titan.mount"];
      requires = ["docker.service"] ++ lib.optionals usesTitan ["mnt-titan.mount"];
      wantedBy = ["multi-user.target"];
      unitConfig = lib.mkIf usesTitan {
        RequiresMountsFor = [cfg.mediaPath];
      };

      preStart = ''
        # A library scan against an empty mount point marks media as missing.
        ${lib.optionalString usesTitan ''
          if ! ${pkgs.util-linux}/bin/mountpoint -q /mnt/titan; then
            echo "Titan is not mounted at /mnt/titan" >&2
            exit 1
          fi
        ''}
        if [ ! -f ${lib.escapeShellArg "${cfg.dataPath}/Preferences.xml"} ]; then
          echo "Plex data not found at ${cfg.dataPath}; refusing to start an unclaimed server" >&2
          exit 1
        fi

        cp ${./docker-compose.yml} ${containerPath}/docker-compose.yml

        cat > ${containerPath}/.env <<EOF
        TZ=${cfg.timezone}
        PLEX_UID=${toString cfg.uid}
        PLEX_GID=${toString cfg.gid}
        CONFIG_PATH=${containerPath}/config
        DATA_PATH=${cfg.dataPath}
        TRANSCODE_PATH=${containerPath}/transcode
        MEDIA_PATH=${cfg.mediaPath}
        WATCHTOWER_ENABLE=${lib.boolToString cfg.enableWatchtower}
        EOF
      '';

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        WorkingDirectory = containerPath;
        ExecStart = "${pkgs.docker-compose}/bin/docker-compose up -d --wait --wait-timeout 300";
        ExecStop = "${pkgs.docker-compose}/bin/docker-compose down";
        ExecReload = "${pkgs.docker-compose}/bin/docker-compose restart";
      };
    };

    # Host networking: the same ports the NixOS Plex module opened.
    networking.firewall = {
      allowedTCPPorts = [32400 8324 32469];
      allowedUDPPorts = [1900 5353 32410 32412 32413 32414];
    };
  };
}
