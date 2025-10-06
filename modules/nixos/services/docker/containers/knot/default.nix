# Knot (Tangled) Git Server Container Module
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.modules.nixos.docker.containers.knot;
  containerName = "knot";
  containerPath = "/var/lib/docker-containers/${containerName}";
in {
  options.modules.nixos.docker.containers.knot = {
    enable = lib.mkEnableOption "Knot (Tangled) git server container";

    hostname = lib.mkOption {
      type = lib.types.str;
      default = "knot.local.solivan.dev";
      description = "Hostname for the Knot server";
      example = "git.example.com";
    };

    owner = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "DID (Decentralized Identifier) of the knot owner";
      example = "did:plc:yourdidgoeshere";
    };

    secret = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "Secret key from tangled.sh registration";
    };

    secretFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Path to file containing the secret key";
    };

    serverPort = lib.mkOption {
      type = lib.types.int;
      default = 443;
      description = "Server port for HTTPS";
    };

    ports = {
      ssh = lib.mkOption {
        type = lib.types.int;
        default = 2223;
        description = "SSH port for git operations";
      };

      http = lib.mkOption {
        type = lib.types.int;
        default = 8082;
        description = "HTTP port for web interface";
      };
    };

    dataPath = lib.mkOption {
      type = lib.types.str;
      default = "${containerPath}/data";
      description = "Path to Knot data directory";
    };

    configPath = lib.mkOption {
      type = lib.types.str;
      default = "${containerPath}/config";
      description = "Path to Knot config directory";
    };

    enableWatchtower = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable Watchtower auto-updates";
    };

    imageTag = lib.mkOption {
      type = lib.types.str;
      default = "v1.4.0-alpha";
      description = "Docker image tag to use";
    };
  };

  config = lib.mkIf cfg.enable {
    # Ensure Docker is enabled
    virtualisation.docker.enable = true;

    # Create required directories
    systemd.tmpfiles.rules = [
      "d ${containerPath} 0755 root root -"
      "d ${cfg.dataPath} 0755 root root -"
      "d ${cfg.configPath} 0755 root root -"
    ];

    # Knot container service
    systemd.services."docker-container-${containerName}" = {
      description = "Knot (Tangled) Git Server Container";
      after = ["docker.service" "docker-network-proxy.service"];
      requires = ["docker.service" "docker-network-proxy.service"];
      wantedBy = ["multi-user.target"];

      preStart = ''
        # Copy docker-compose.yml to runtime directory
        cp ${./docker-compose.yml} ${containerPath}/docker-compose.yml

        # Get secret from file if specified
        SECRET="${cfg.secret}"
        ${lib.optionalString (cfg.secretFile != null) ''
          if [ -f "${cfg.secretFile}" ]; then
            SECRET=$(cat "${cfg.secretFile}")
          fi
        ''}

        # Create .env file with configuration
        cat > ${containerPath}/.env <<EOF
        KNOT_SERVER_HOSTNAME=${cfg.hostname}
        KNOT_SERVER_OWNER=${cfg.owner}
        KNOT_SERVER_PORT=${toString cfg.serverPort}
        KNOT_SERVER_SECRET=$SECRET
        SSH_PORT=${toString cfg.ports.ssh}
        HTTP_PORT=${toString cfg.ports.http}
        DATA_PATH=${cfg.dataPath}
        CONFIG_PATH=${cfg.configPath}
        IMAGE_TAG=${cfg.imageTag}
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
    networking.firewall.allowedTCPPorts = [
      cfg.ports.ssh
      cfg.ports.http
    ];
  };
}
