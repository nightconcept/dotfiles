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
  usesTitan = lib.hasPrefix "/mnt/titan" cfg.remoteDataPath;
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

    enableCommitSigning = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable GPG/SSH commit signing for web interface commits";
    };

    signingKey = lib.mkOption {
      type = lib.types.str;
      default = "default";
      description = "GPG signing key (default = use Forgejo server key, or specify key ID)";
    };

    signingName = lib.mkOption {
      type = lib.types.str;
      default = "Forgejo";
      description = "Name to use for signed commits";
    };

    signingEmail = lib.mkOption {
      type = lib.types.str;
      default = "noreply@forgejo.local";
      description = "Email to use for signed commits";
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
      "d ${cfg.remoteDataPath}/git 0755 1000 1000 -"
      "d ${cfg.remoteDataPath}/git/.ssh 0700 1000 1000 -"
    ];

    systemd.services."docker-container-${containerName}" = {
      description = "Forgejo Git Forge Container";
      after =
        ["docker.service" "docker-network-proxy.service"]
        ++ lib.optionals usesTitan ["mnt-titan.mount"];
      requires =
        ["docker.service" "docker-network-proxy.service"]
        ++ lib.optionals usesTitan ["mnt-titan.mount"];
      wantedBy = ["multi-user.target"];
      unitConfig = lib.mkIf usesTitan {
        RequiresMountsFor = [cfg.remoteDataPath];
      };

      preStart = ''
        # Copy docker-compose.yml to runtime directory
        cp ${./docker-compose.yml} ${containerPath}/docker-compose.yml

        # Create SSH signing key for Forgejo
        cat > ${cfg.remoteDataPath}/git/.ssh/signing_key.pub <<EOF
        ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMJKTm63zFmYfGauCBlUWq7lvHFq+NVPT5RqIfjLM7MN danny@solivan.dev
        EOF
        chown 1000:1000 ${cfg.remoteDataPath}/git/.ssh/signing_key.pub
        chmod 0644 ${cfg.remoteDataPath}/git/.ssh/signing_key.pub

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
        FORGEJO_SIGNING_ENABLED=${
          if cfg.enableCommitSigning
          then "true"
          else "false"
        }
        FORGEJO_SIGNING_KEY=${cfg.signingKey}
        FORGEJO_SIGNING_NAME=${cfg.signingName}
        FORGEJO_SIGNING_EMAIL=${cfg.signingEmail}
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
