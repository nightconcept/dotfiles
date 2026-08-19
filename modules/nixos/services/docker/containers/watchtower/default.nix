# Watchtower Auto-Update Container Module
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.modules.nixos.docker.containers.watchtower;
  containerName = "watchtower";
  containerPath = "/var/lib/docker-containers/${containerName}";
in {
  options.modules.nixos.docker.containers.watchtower = {
    enable = lib.mkEnableOption "Watchtower container auto-updater";

    schedule = lib.mkOption {
      type = lib.types.str;
      default = "0 0 4 * * *";
      description = "Cron schedule for updates";
    };

    apiTokenFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default =
        if config.modules.nixos.security.sops.enable
        then "/run/secrets/services/watchtower/api_token"
        else null;
      description = "Path to file containing Watchtower API token";
    };
  };

  config = lib.mkIf cfg.enable {
    virtualisation.docker.enable = true;

    systemd.tmpfiles.rules = [
      "d ${containerPath} 0755 root root -"
    ];

    systemd.services."docker-container-${containerName}" = {
      description = "Watchtower Auto-Update Container";
      after = ["docker.service" "docker-network-proxy.service"];
      requires = ["docker.service" "docker-network-proxy.service"];
      wantedBy = ["multi-user.target"];

      preStart = ''
        # Use docker-compose.yml with proxy network
        if [ -f ${./docker-compose.yml} ]; then
          cp ${./docker-compose.yml} ${containerPath}/docker-compose.yml
        else
          cat > ${containerPath}/docker-compose.yml <<'COMPOSE'
        services:
          watchtower:
            container_name: watchtower
            image: containrrr/watchtower:latest
            restart: unless-stopped
            environment:
              - WATCHTOWER_CLEANUP=true
              - WATCHTOWER_LABEL_ENABLE=true
              - WATCHTOWER_SCHEDULE=${cfg.schedule}
            volumes:
              - /var/run/docker.sock:/var/run/docker.sock
            networks:
              - proxy

        networks:
          proxy:
            external: true
        COMPOSE
        fi

        # Generate .env file
        cat > ${containerPath}/.env <<EOF
        WATCHTOWER_SCHEDULE=${cfg.schedule}
        ${lib.optionalString (cfg.apiTokenFile != null) ''
          WATCHTOWER_HTTP_API_TOKEN=$(cat ${cfg.apiTokenFile})
        ''}
        EOF
      '';

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        WorkingDirectory = containerPath;
        ExecStart = "${pkgs.docker-compose}/bin/docker-compose up -d --wait --wait-timeout 180";
        ExecStop = "${pkgs.docker-compose}/bin/docker-compose down";
      };
    };
  };
}
