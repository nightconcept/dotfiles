# Portainer Docker Management Container Module
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.modules.nixos.docker.containers.portainer;
  containerName = "portainer";
  containerPath = "/var/lib/docker-containers/${containerName}";
in {
  options.modules.nixos.docker.containers.portainer = {
    enable = lib.mkEnableOption "Portainer Docker management UI";

    port = lib.mkOption {
      type = lib.types.int;
      default = 9000;
      description = "Port for Portainer web interface";
    };

    edgePort = lib.mkOption {
      type = lib.types.int;
      default = 8000;
      description = "Port for Portainer Edge agent";
    };

    dataPath = lib.mkOption {
      type = lib.types.str;
      default = "${containerPath}/data";
      description = "Path to Portainer data";
    };
  };

  config = lib.mkIf cfg.enable {
    virtualisation.docker.enable = true;

    systemd.tmpfiles.rules = [
      "d ${containerPath} 0755 root root -"
      "d ${cfg.dataPath} 0755 root root -"
    ];

    systemd.services."docker-container-${containerName}" = {
      description = "Portainer Docker Management Container";
      after = ["docker.service" "docker-network-proxy.service"];
      requires = ["docker.service" "docker-network-proxy.service"];
      wantedBy = ["multi-user.target"];

      preStart = ''
        # Copy docker-compose.yml to runtime directory
        cp ${./docker-compose.yml} ${containerPath}/docker-compose.yml

        # Generate .env file
        cat > ${containerPath}/.env <<EOF
        DATA_PATH=${cfg.dataPath}
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
