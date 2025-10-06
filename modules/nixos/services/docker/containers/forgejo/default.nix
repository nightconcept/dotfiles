# Forgejo Git Forge Container Module
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.modules.nixos.docker.containers.forgejo;
  containerName = "forgejo";
  containerPath = "/var/lib/docker-containers/${containerName}";
in {
  options.modules.nixos.docker.containers.forgejo = {
    enable = lib.mkEnableOption "Forgejo git forge";

    domain = lib.mkOption {
      type = lib.types.str;
      default = "forge.solivan.dev";
      description = "Domain for Forgejo";
    };

    sshPort = lib.mkOption {
      type = lib.types.int;
      default = 2222;
      description = "SSH port for git operations";
    };

    httpPort = lib.mkOption {
      type = lib.types.int;
      default = 3000;
      description = "HTTP port for web interface";
    };

    dbPassword = lib.mkOption {
      type = lib.types.str;
      default = "forgejo_db_password";
      description = "Database password for PostgreSQL";
    };

    enableActions = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable Forgejo Actions";
    };

    actionsUrl = lib.mkOption {
      type = lib.types.str;
      default = "https://github.com";
      description = "Default Actions URL (github.com for GitHub Actions compatibility, data.forgejo.org for FOSS actions)";
    };

    localDbPath = lib.mkOption {
      type = lib.types.str;
      default = "${containerPath}/db";
      description = "Local path for PostgreSQL database";
    };

    remoteDataPath = lib.mkOption {
      type = lib.types.str;
      default = "/mnt/titan/docker/forgejo";
      description = "Remote path for Forgejo data and repositories";
    };
  };

  config = lib.mkIf cfg.enable {
    virtualisation.docker.enable = true;

    systemd.tmpfiles.rules = [
      "d ${containerPath} 0755 root root -"
      "d ${cfg.localDbPath} 0755 999 999 -"
      "d ${cfg.remoteDataPath} 0755 1000 1000 -"
    ];

    systemd.services."docker-container-${containerName}" = {
      description = "Forgejo Git Forge Container";
      after = ["docker.service" "docker-network-proxy.service"];
      requires = ["docker.service" "docker-network-proxy.service"];
      wantedBy = ["multi-user.target"];

      preStart = ''
        # Copy docker-compose.yml to runtime directory
        cp ${./docker-compose.yml} ${containerPath}/docker-compose.yml

        # Generate .env file with proper environment variables
        cat > ${containerPath}/.env <<EOF
        DB_PASSWORD=${cfg.dbPassword}
        LOCAL_DB_PATH=${cfg.localDbPath}
        REMOTE_DATA_PATH=${cfg.remoteDataPath}
        FORGEJO_DOMAIN=${cfg.domain}
        FORGEJO_SSH_PORT=${toString cfg.sshPort}
        FORGEJO_HTTP_PORT=${toString cfg.httpPort}
        FORGEJO_ACTIONS_ENABLED=${
          if cfg.enableActions
          then "true"
          else "false"
        }
        FORGEJO_ACTIONS_URL=${cfg.actionsUrl}
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

    networking.firewall.allowedTCPPorts = [cfg.sshPort];
  };
}
