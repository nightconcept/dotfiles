# Uptime Kuma Monitoring Container Module
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.modules.nixos.docker.containers.uptime-kuma;
  containerName = "uptimekuma";
  containerPath = "/var/lib/docker-containers/${containerName}";
in {
  options.modules.nixos.docker.containers.uptime-kuma = {
    enable = lib.mkEnableOption "Uptime Kuma monitoring service";

    domain = lib.mkOption {
      type = lib.types.str;
      default = "local.solivan.dev";
      description = "Base domain for Uptime Kuma";
    };

    subdomain = lib.mkOption {
      type = lib.types.str;
      default = "status";
      description = "Subdomain for Uptime Kuma";
    };

    port = lib.mkOption {
      type = lib.types.int;
      default = 3001;
      description = "Port for Uptime Kuma web interface";
    };

    dataPath = lib.mkOption {
      type = lib.types.str;
      default = "${containerPath}/data";
      description = "Path to Uptime Kuma data";
    };

  };

  config = lib.mkIf cfg.enable {
    virtualisation.docker.enable = true;

    systemd.tmpfiles.rules = [
      "d ${containerPath} 0755 root root -"
      "d ${cfg.dataPath} 0755 root root -"
    ];

    systemd.services."docker-container-${containerName}" = {
      description = "Uptime Kuma Monitoring Container";
      after = ["docker.service" "docker-network-proxy.service"];
      requires = ["docker.service" "docker-network-proxy.service"];
      wantedBy = ["multi-user.target"];

      preStart = ''
        # Copy docker-compose.yml to runtime directory
        cp ${./docker-compose.yml} ${containerPath}/docker-compose.yml

        # Generate .env file
        cat > ${containerPath}/.env <<EOF
        DATA_PATH=${cfg.dataPath}
        PORT=${toString cfg.port}
        DOMAIN=${cfg.subdomain}.${cfg.domain}
        EOF
      '';

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        WorkingDirectory = containerPath;
        ExecStart = "${pkgs.docker-compose}/bin/docker-compose up -d";
        ExecStop = "${pkgs.docker-compose}/bin/docker-compose down";
      };
    };

    networking.firewall.allowedTCPPorts = [cfg.port];
  };
}
