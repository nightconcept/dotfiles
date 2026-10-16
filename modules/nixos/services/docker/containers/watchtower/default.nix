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

    gotify = lib.mkOption {
      type = lib.types.nullOr (lib.types.submodule {
        options = {
          host = lib.mkOption {
            type = lib.types.str;
            description = "Gotify host and port reachable from the Watchtower container.";
          };
          tokenFile = lib.mkOption {
            type = lib.types.str;
            description = "Host file containing the Gotify application token.";
          };
        };
      });
      default = null;
      description = "Send update reports to Gotify.";
    };
  };

  config = lib.mkIf cfg.enable {
    virtualisation.docker.enable = true;

    systemd.tmpfiles.rules = [
      "d ${containerPath} 0755 root root -"
    ];

    systemd.services."docker-container-${containerName}" = {
      description = "Watchtower Auto-Update Container";
      after = ["docker.service" "docker-network-proxy.service"] ++ lib.optional (cfg.gotify != null) "gotify-provision.service";
      requires = ["docker.service" "docker-network-proxy.service"];
      wants = lib.optional (cfg.gotify != null) "gotify-provision.service";
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
            image: ghcr.io/nicholas-fedor/watchtower:latest
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
        umask 077
        cat > ${containerPath}/.env <<EOF
        WATCHTOWER_SCHEDULE=${cfg.schedule}
        WATCHTOWER_CLEANUP=true
        WATCHTOWER_LABEL_ENABLE=true
        WATCHTOWER_INCLUDE_RESTARTING=true
        EOF
        ${lib.optionalString (cfg.gotify != null) ''
          cat >> ${containerPath}/.env <<EOF
          WATCHTOWER_NOTIFICATION_URL=gotify://${cfg.gotify.host}/$(cat ${cfg.gotify.tokenFile})?disabletls=yes
          WATCHTOWER_NOTIFICATIONS_HOSTNAME=${config.networking.hostName}
          EOF
        ''}
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
