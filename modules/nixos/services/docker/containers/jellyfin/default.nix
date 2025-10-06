# Jellyfin Media Server Container Module
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.modules.nixos.docker.containers.jellyfin;
  containerName = "jellyfin";
  containerPath = "/var/lib/docker-containers/${containerName}";
in {
  options.modules.nixos.docker.containers.jellyfin = {
    enable = lib.mkEnableOption "Jellyfin media server container";

    publishedServerUrl = lib.mkOption {
      type = lib.types.str;
      default = "https://jellyfin.local.solivan.dev";
      description = "Published server URL for Jellyfin";
      example = "https://jellyfin.example.com";
    };

    timezone = lib.mkOption {
      type = lib.types.str;
      default = "America/Chicago";
      description = "Timezone for Jellyfin";
    };

    configPath = lib.mkOption {
      type = lib.types.str;
      default = "${containerPath}/config";
      description = "Path to Jellyfin configuration";
    };

    mediaPaths = {
      tvShows = lib.mkOption {
        type = lib.types.str;
        default = "/mnt/titan/TVShows";
        description = "Path to TV shows library";
      };

      movies = lib.mkOption {
        type = lib.types.str;
        default = "/mnt/titan/Movies";
        description = "Path to movies library";
      };
    };

    ports = {
      webUI = lib.mkOption {
        type = lib.types.int;
        default = 8096;
        description = "Web UI port";
      };

      https = lib.mkOption {
        type = lib.types.int;
        default = 8920;
        description = "HTTPS port";
      };

      discovery = lib.mkOption {
        type = lib.types.int;
        default = 7359;
        description = "Client discovery port (UDP)";
      };

      dlna = lib.mkOption {
        type = lib.types.int;
        default = 1900;
        description = "DLNA port (UDP)";
      };
    };

    enableWatchtower = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable Watchtower auto-updates";
    };
  };

  config = lib.mkIf cfg.enable {
    # Ensure Docker is enabled
    virtualisation.docker.enable = true;

    # Create required directories
    systemd.tmpfiles.rules = [
      "d ${containerPath} 0755 root root -"
      "d ${cfg.configPath} 0755 root root -"
    ];

    # Jellyfin container service
    systemd.services."docker-container-${containerName}" = {
      description = "Jellyfin Media Server Container";
      after = ["docker.service" "docker-network-proxy.service"];
      requires = ["docker.service" "docker-network-proxy.service"];
      wantedBy = ["multi-user.target"];

      preStart = ''
        # Copy docker-compose.yml to runtime directory
        cp ${./docker-compose.yml} ${containerPath}/docker-compose.yml

        # Create .env file with configuration
        cat > ${containerPath}/.env <<EOF
        PUBLISHED_SERVER_URL=${cfg.publishedServerUrl}
        TZ=${cfg.timezone}
        WEBUI_PORT=${toString cfg.ports.webUI}
        HTTPS_PORT=${toString cfg.ports.https}
        DISCOVERY_PORT=${toString cfg.ports.discovery}
        DLNA_PORT=${toString cfg.ports.dlna}
        CONFIG_PATH=${cfg.configPath}
        TV_SHOWS_PATH=${cfg.mediaPaths.tvShows}
        MOVIES_PATH=${cfg.mediaPaths.movies}
        WATCHTOWER_ENABLE=${toString cfg.enableWatchtower}
        EOF
      '';

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        WorkingDirectory = containerPath;
        ExecStart = "${pkgs.docker-compose}/bin/docker-compose up -d";
        ExecStop = "${pkgs.docker-compose}/bin/docker-compose down";
        ExecReload = "${pkgs.docker-compose}/bin/docker-compose restart";
      };
    };

    # Open firewall ports
    networking.firewall = {
      allowedTCPPorts = [cfg.ports.webUI cfg.ports.https];
      allowedUDPPorts = [cfg.ports.discovery cfg.ports.dlna];
    };
  };
}
