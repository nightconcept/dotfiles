# Recyclarr TRaSH Guides sync container module.
# Syncs quality profiles, custom formats, and quality sizes into Sonarr and
# Radarr from ./recyclarr.yml on a schedule.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.modules.nixos.docker.containers.recyclarr;
  containers = config.modules.nixos.docker.containers;
  containerName = "recyclarr";
  containerPath = "/var/lib/docker-containers/${containerName}";
in {
  options.modules.nixos.docker.containers.recyclarr = {
    enable = lib.mkEnableOption "Recyclarr TRaSH Guides sync for Sonarr and Radarr";

    configPath = lib.mkOption {
      type = lib.types.str;
      default = "/home/danny/docker/recyclarr/config";
      description = "Path to Recyclarr configuration, cache, and logs";
    };

    schedule = lib.mkOption {
      type = lib.types.str;
      default = "@daily";
      description = "Cron schedule for recyclarr sync";
    };

    sonarrConfigXml = lib.mkOption {
      type = lib.types.str;
      default = "${containers.sonarr.configPath}/config.xml";
      description = "Sonarr config.xml that holds the API key Recyclarr uses";
    };

    radarrConfigXml = lib.mkOption {
      type = lib.types.str;
      default = "${containers.radarr.configPath}/config.xml";
      description = "Radarr config.xml that holds the API key Recyclarr uses";
    };

    uid = lib.mkOption {
      type = lib.types.int;
      default = 1000;
      description = "User ID for Recyclarr";
    };

    gid = lib.mkOption {
      type = lib.types.int;
      default = 1000;
      description = "Group ID for Recyclarr";
    };

    timezone = lib.mkOption {
      type = lib.types.str;
      default = "America/Los_Angeles";
      description = "Timezone used by Recyclarr";
    };
  };

  config = lib.mkIf cfg.enable {
    virtualisation.docker.enable = true;

    systemd.tmpfiles.rules = [
      "d ${containerPath} 0700 root root -"
      "d /home/danny/docker/recyclarr 0755 danny users -"
      "d ${cfg.configPath} 0750 ${toString cfg.uid} ${toString cfg.gid} -"
    ];

    systemd.services."docker-container-${containerName}" = {
      description = "Recyclarr TRaSH Guides Sync Container";
      after = [
        "docker.service"
        "docker-network-proxy.service"
        "docker-container-sonarr.service"
        "docker-container-radarr.service"
      ];
      requires = ["docker.service" "docker-network-proxy.service"];
      wantedBy = ["multi-user.target"];
      restartTriggers = [
        ./recyclarr.yml
        ./settings.yml
        ./custom-formats
        ./docker-compose.yml
      ];

      preStart = ''
        # Sonarr and Radarr own their API keys; read them instead of copying
        # them into SOPS, so a key rotated in the UI cannot drift.
        api_key() {
          ${pkgs.gnused}/bin/sed -n 's:.*<ApiKey>\(.*\)</ApiKey>.*:\1:p' "$1"
        }
        sonarr_key=$(api_key ${lib.escapeShellArg cfg.sonarrConfigXml})
        radarr_key=$(api_key ${lib.escapeShellArg cfg.radarrConfigXml})
        if [ -z "$sonarr_key" ] || [ -z "$radarr_key" ]; then
          echo "Could not read the Sonarr or Radarr API key" >&2
          exit 1
        fi

        cp ${./docker-compose.yml} ${containerPath}/docker-compose.yml

        umask 077
        cat > ${containerPath}/.env <<EOF
        CONFIG_PATH=${cfg.configPath}
        CRON_SCHEDULE=${cfg.schedule}
        PUID=${toString cfg.uid}
        PGID=${toString cfg.gid}
        TZ=${cfg.timezone}
        SONARR_API_KEY=$sonarr_key
        RADARR_API_KEY=$radarr_key
        EOF

        mkdir -p ${cfg.configPath}
        install -m 0644 ${./recyclarr.yml} ${cfg.configPath}/recyclarr.yml
        install -m 0644 ${./settings.yml} ${cfg.configPath}/settings.yml
        rm -rf ${cfg.configPath}/custom-formats
        cp -r ${./custom-formats} ${cfg.configPath}/custom-formats
        chmod -R u+w ${cfg.configPath}/custom-formats
        chown -R ${toString cfg.uid}:${toString cfg.gid} ${cfg.configPath}
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
  };
}
