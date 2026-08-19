# Radarr Movie Manager Container Module
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.modules.nixos.docker.containers.radarr;
  containerName = "radarr";
  containerPath = "/var/lib/docker-containers/${containerName}";
in {
  options.modules.nixos.docker.containers.radarr = {
    enable = lib.mkEnableOption "Radarr movie manager container";

    domain = lib.mkOption {
      type = lib.types.str;
      default = "local.solivan.dev";
      description = "Base domain for Radarr";
    };

    subdomain = lib.mkOption {
      type = lib.types.str;
      default = "radarr";
      description = "Subdomain for Radarr";
    };

    configPath = lib.mkOption {
      type = lib.types.str;
      default = "/home/danny/docker/radarr/config";
      description = "Path to Radarr configuration";
    };

    downloadsPath = lib.mkOption {
      type = lib.types.str;
      default = "/mnt/titan/downloads";
      description = "Path to downloads directory";
    };

    moviesPath = lib.mkOption {
      type = lib.types.str;
      default = "/mnt/titan/Movies";
      description = "Path to movies library";
    };

    port = lib.mkOption {
      type = lib.types.int;
      default = 7878;
      description = "Port for Radarr web interface";
    };

    uid = lib.mkOption {
      type = lib.types.int;
      default = 1000;
      description = "User ID for Radarr";
    };

    gid = lib.mkOption {
      type = lib.types.int;
      default = 1000;
      description = "Group ID for Radarr";
    };

    timezone = lib.mkOption {
      type = lib.types.str;
      default = "America/Los_Angeles";
      description = "Timezone for Radarr";
    };
  };

  config = lib.mkIf cfg.enable {
    # Ensure Docker is enabled
    virtualisation.docker.enable = true;

    # Create required directories
    systemd.tmpfiles.rules = [
      "d ${containerPath} 0755 root root -"
      "d /home/danny/docker/radarr 0755 danny users -"
      "d ${cfg.configPath} 0755 ${toString cfg.uid} ${toString cfg.gid} -"
    ];

    # Container service
    systemd.services."docker-container-${containerName}" = {
      description = "Radarr Movie Manager Container";
      after = ["docker.service" "docker-network-proxy.service" "mnt-titan.mount"];
      # Make Titan mount a hard requirement if paths use it
      requires =
        if (lib.hasPrefix "/mnt/titan" cfg.downloadsPath || lib.hasPrefix "/mnt/titan" cfg.moviesPath)
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
        ${lib.optionalString (lib.hasPrefix "/mnt/titan" cfg.moviesPath) ''
          echo "Waiting for movies path: ${cfg.moviesPath}"
          while [ ! -d "${cfg.moviesPath}" ]; do
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
        MOVIES_PATH=${cfg.moviesPath}
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
