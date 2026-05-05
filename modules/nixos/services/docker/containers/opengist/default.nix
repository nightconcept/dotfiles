# Opengist Container Module
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.modules.nixos.docker.containers.opengist;
  containerName = "opengist";
  containerPath = "/var/lib/docker-containers/${containerName}";
in {
  options.modules.nixos.docker.containers.opengist = {
    enable = lib.mkEnableOption "Opengist";

    domain = lib.mkOption {
      type = lib.types.str;
      default = "solivan.dev";
      description = "Base domain for Opengist";
    };

    localDomain = lib.mkOption {
      type = lib.types.str;
      default = "local.solivan.dev";
      description = "Local domain for Opengist";
    };

    subdomain = lib.mkOption {
      type = lib.types.str;
      default = "gist";
      description = "Subdomain for Opengist";
    };

    dataPath = lib.mkOption {
      type = lib.types.str;
      default = "/home/danny/docker/opengist/data";
      description = "Path to Opengist data directory";
    };
  };

  config = lib.mkIf cfg.enable {
    # Ensure Docker is enabled
    virtualisation.docker.enable = true;

    # Create required directories
    systemd.tmpfiles.rules = [
      "d ${containerPath} 0755 root root -"
      "d /home/danny/docker/opengist 0755 danny users -"
    ];

    # Opengist container service
    systemd.services."docker-container-${containerName}" = {
      description = "Opengist Container";
      after = ["docker.service" "docker-network-proxy.service"];
      requires = ["docker.service" "docker-network-proxy.service"];
      wantedBy = ["multi-user.target"];

      preStart = ''
        # Copy docker-compose.yml to runtime directory
        cp ${./docker-compose.yml} ${containerPath}/docker-compose.yml

        # Generate .env file
        cat > ${containerPath}/.env <<EOF
        DATA_PATH=${cfg.dataPath}
        DOMAIN=${cfg.domain}
        LOCAL_DOMAIN=${cfg.localDomain}
        SUBDOMAIN=${cfg.subdomain}
        EOF

        # Ensure data directory has correct permissions
        mkdir -p ${cfg.dataPath}
        chown -R danny:users ${cfg.dataPath}
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
  };
}
