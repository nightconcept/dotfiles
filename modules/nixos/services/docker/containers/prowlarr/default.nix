# Prowlarr Indexer Manager Container Module
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.modules.nixos.docker.containers.prowlarr;
  containerName = "prowlarr";
  containerPath = "/var/lib/docker-containers/${containerName}";
in {
  options.modules.nixos.docker.containers.prowlarr = {
    enable = lib.mkEnableOption "Prowlarr indexer manager container";

    subdomain = lib.mkOption {
      type = lib.types.str;
      default = "prowlarr";
      description = "Subdomain for Prowlarr";
    };

    domain = lib.mkOption {
      type = lib.types.str;
      default = "local.solivan.dev";
      description = "Base domain";
    };

    timezone = lib.mkOption {
      type = lib.types.str;
      default = "America/Chicago";
      description = "Timezone for the container";
    };

    configPath = lib.mkOption {
      type = lib.types.str;
      default = "${containerPath}/config";
      description = "Path to Prowlarr configuration";
    };

    port = lib.mkOption {
      type = lib.types.int;
      default = 9696;
      description = "Port for Prowlarr web interface";
    };

    uid = lib.mkOption {
      type = lib.types.int;
      default = 1000;
      description = "User ID for Prowlarr";
    };

    gid = lib.mkOption {
      type = lib.types.int;
      default = 1000;
      description = "Group ID for Prowlarr";
    };

    enableTraefik = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable Traefik reverse proxy integration";
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
      "d ${cfg.configPath} 0755 ${toString cfg.uid} ${toString cfg.gid} -"
    ];

    # Prowlarr container service
    systemd.services."docker-container-${containerName}" = {
      description = "Prowlarr Indexer Manager Container";
      after = ["docker.service"] ++ lib.optional cfg.enableTraefik "docker-network-proxy.service";
      requires = ["docker.service"] ++ lib.optional cfg.enableTraefik "docker-network-proxy.service";
      wantedBy = ["multi-user.target"];

      preStart = ''
        # Copy docker-compose.yml to runtime directory
        cp ${./docker-compose.yml} ${containerPath}/docker-compose.yml

        # Generate .env file
        cat > ${containerPath}/.env <<EOF
        PUID=${toString cfg.uid}
        PGID=${toString cfg.gid}
        TZ=${cfg.timezone}
        CONFIG_PATH=${cfg.configPath}
        WEBUI_PORT=${toString cfg.port}
        DOMAIN=${cfg.domain}
        SUBDOMAIN=${cfg.subdomain}
        EOF

        # Update docker-compose.yml with runtime values
        ${pkgs.yq}/bin/yq -i -y '
          .services.prowlarr.environment[0] = "PUID=${toString cfg.uid}" |
          .services.prowlarr.environment[1] = "PGID=${toString cfg.gid}" |
          .services.prowlarr.environment[2] = "TZ=${cfg.timezone}" |
          .services.prowlarr.volumes[0].source = "${cfg.configPath}" |
          .services.prowlarr.ports[0] = "${toString cfg.port}:9696"
        ' ${containerPath}/docker-compose.yml

        # Update Traefik labels if enabled
        ${lib.optionalString cfg.enableTraefik ''
          ${pkgs.yq}/bin/yq -i -y '
            .services.prowlarr.labels[1] = "traefik.http.routers.prowlarr.rule=Host(`${cfg.subdomain}.${cfg.domain}`)" |
            .services.prowlarr.labels[5] = "traefik.http.routers.prowlarr-secure.rule=Host(`${cfg.subdomain}.${cfg.domain}`)" |
            .services.prowlarr.labels[8] = "traefik.http.services.prowlarr.loadbalancer.server.port=9696"
          ' ${containerPath}/docker-compose.yml
        ''}

        # Disable Traefik if not needed
        ${lib.optionalString (!cfg.enableTraefik) ''
          ${pkgs.yq}/bin/yq -i -y '
            .services.prowlarr.labels[0] = "traefik.enable=false" |
            del(.services.prowlarr.networks) |
            del(.networks)
          ' ${containerPath}/docker-compose.yml
        ''}



        # Update Watchtower label
        ${pkgs.yq}/bin/yq -i -y '
          .services.prowlarr.labels = [.services.prowlarr.labels[] | if test("watchtower") then "com.centurylinklabs.watchtower.enable=${toString cfg.enableWatchtower}" else . end]
        ' ${containerPath}/docker-compose.yml
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

    # Open firewall port if not using Traefik
    networking.firewall.allowedTCPPorts = lib.optional (!cfg.enableTraefik) cfg.port;
  };
}
