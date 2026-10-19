# Sonarr Anime Container Module
# A second Sonarr for anime, so anime gets its own series type, quality
# profile, and library (/mnt/titan/Anime) apart from regular TV.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.modules.nixos.docker.containers.sonarr-anime;
  containerName = "sonarr-anime";
  containerPath = "/var/lib/docker-containers/${containerName}";
in {
  options.modules.nixos.docker.containers.sonarr-anime = {
    enable = lib.mkEnableOption "Sonarr anime series manager container";

    domain = lib.mkOption {
      type = lib.types.str;
      default = "local.solivan.dev";
      description = "Base domain for Sonarr Anime";
    };

    subdomain = lib.mkOption {
      type = lib.types.str;
      default = "sonarr-anime";
      description = "Subdomain for Sonarr Anime";
    };

    configPath = lib.mkOption {
      type = lib.types.str;
      default = "/home/danny/docker/sonarr-anime/config";
      description = "Path to Sonarr configuration";
    };

    downloadsPath = lib.mkOption {
      type = lib.types.str;
      default = "/mnt/titan/downloads";
      description = "Path to downloads directory";
    };

    animePath = lib.mkOption {
      type = lib.types.str;
      default = "/mnt/titan/Anime";
      description = "Path to anime library";
    };

    port = lib.mkOption {
      type = lib.types.int;
      default = 8990;
      description = "Host port for the Sonarr Anime web interface";
    };

    uid = lib.mkOption {
      type = lib.types.int;
      default = 1000;
      description = "User ID for Sonarr Anime";
    };

    gid = lib.mkOption {
      type = lib.types.int;
      default = 1000;
      description = "Group ID for Sonarr Anime";
    };

    timezone = lib.mkOption {
      type = lib.types.str;
      default = "America/Los_Angeles";
      description = "Timezone for Sonarr Anime";
    };
  };

  config = lib.mkIf cfg.enable {
    # Ensure Docker is enabled
    virtualisation.docker.enable = true;

    # Create required directories
    systemd.tmpfiles.rules = [
      "d ${containerPath} 0755 root root -"
      "d /home/danny/docker/sonarr-anime 0755 danny users -"
      "d ${cfg.configPath} 0755 ${toString cfg.uid} ${toString cfg.gid} -"
    ];

    # Container service
    systemd.services."docker-container-${containerName}" = {
      description = "Sonarr Anime Container";
      after = ["docker.service" "docker-network-proxy.service" "mnt-titan.mount"];
      # Make Titan mount a hard requirement if paths use it
      requires =
        if (lib.hasPrefix "/mnt/titan" cfg.downloadsPath || lib.hasPrefix "/mnt/titan" cfg.animePath)
        then ["docker.service" "docker-network-proxy.service" "mnt-titan.mount"]
        else ["docker.service" "docker-network-proxy.service"];
      wantedBy = ["multi-user.target"];

      preStart = ''
        # Wait for mount paths to be available
        ${lib.optionalString (lib.hasPrefix "/mnt/titan" cfg.downloadsPath) ''
          echo "Waiting for downloads path: ${cfg.downloadsPath}"
          while [ ! -d "${cfg.downloadsPath}" ]; do
            echo "Path not available yet, waiting..."
            sleep 2
          done
        ''}
        ${lib.optionalString (lib.hasPrefix "/mnt/titan" cfg.animePath) ''
          echo "Waiting for anime path: ${cfg.animePath}"
          while [ ! -d "${cfg.animePath}" ]; do
            echo "Path not available yet, waiting..."
            sleep 2
          done
        ''}

        # Copy docker-compose.yml to runtime directory
        cp ${./docker-compose.yml} ${containerPath}/docker-compose.yml

        # Generate .env file
        cat > ${containerPath}/.env <<EOF
        PUID=${toString cfg.uid}
        PGID=${toString cfg.gid}
        TZ=${cfg.timezone}
        CONFIG_PATH=${cfg.configPath}
        DOWNLOADS_PATH=${cfg.downloadsPath}
        ANIME_PATH=${cfg.animePath}
        WEBUI_PORT=${toString cfg.port}
        DOMAIN=${cfg.domain}
        SUBDOMAIN=${cfg.subdomain}
        EOF
      '';

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        WorkingDirectory = containerPath;
        ExecStart = "${pkgs.docker-compose}/bin/docker-compose up -d --wait --wait-timeout 180";
        ExecStop = "${pkgs.docker-compose}/bin/docker-compose stop";
        ExecReload = "${pkgs.docker-compose}/bin/docker-compose restart";
      };
    };
  };
}
