# Authelia Authentication Container Module
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.modules.nixos.docker.containers.authelia;
  containerName = "authelia";
  containerPath = "/var/lib/docker-containers/${containerName}";
in {
  options.modules.nixos.docker.containers.authelia = {
    enable = lib.mkEnableOption "Authelia authentication service";

    domain = lib.mkOption {
      type = lib.types.str;
      default = "local.solivan.dev";
      description = "Base domain for Authelia";
    };

    subdomain = lib.mkOption {
      type = lib.types.str;
      default = "auth";
      description = "Subdomain for Authelia (e.g., auth.domain.com)";
    };

    configPath = lib.mkOption {
      type = lib.types.str;
      default = "${containerPath}/config";
      description = "Path to Authelia configuration files";
    };

    secrets = {
      jwtSecretFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default =
          if config.modules.nixos.security.sops.enable
          then "/run/secrets/services/authelia/jwt_secret"
          else null;
        description = "Path to file containing JWT secret";
      };

      sessionSecretFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default =
          if config.modules.nixos.security.sops.enable
          then "/run/secrets/services/authelia/session_secret"
          else null;
        description = "Path to file containing session secret";
      };

      encryptionKeyFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default =
          if config.modules.nixos.security.sops.enable
          then "/run/secrets/services/authelia/encryption_key"
          else null;
        description = "Path to file containing encryption key";
      };

      hmacSecretFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default =
          if config.modules.nixos.security.sops.enable
          then "/run/secrets/services/authelia/hmac_secret"
          else null;
        description = "Path to file containing HMAC secret";
      };

      storageEncryptionKeyFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default =
          if config.modules.nixos.security.sops.enable
          then "/run/secrets/services/authelia/storage_encryption_key"
          else null;
        description = "Path to file containing storage encryption key";
      };
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

    # Authelia container service
    systemd.services."docker-container-${containerName}" = {
      description = "Authelia Authentication Service Container";
      after = ["docker.service" "docker-network-proxy.service"];
      requires = ["docker.service" "docker-network-proxy.service"];
      wantedBy = ["multi-user.target"];

      preStart = ''
        # Copy docker-compose.yml to runtime directory
        cp ${./docker-compose.yml} ${containerPath}/docker-compose.yml

        # Generate .env file with secrets
        cat > ${containerPath}/.env <<EOF
        CONFIG_PATH=${cfg.configPath}
        DOMAIN=${cfg.domain}
        SUBDOMAIN=${cfg.subdomain}
        ${lib.optionalString (cfg.secrets.jwtSecretFile != null) ''
          AUTHELIA_JWT_SECRET=$(cat ${cfg.secrets.jwtSecretFile})
        ''}
        ${lib.optionalString (cfg.secrets.sessionSecretFile != null) ''
          AUTHELIA_SESSION_SECRET=$(cat ${cfg.secrets.sessionSecretFile})
        ''}
        ${lib.optionalString (cfg.secrets.encryptionKeyFile != null) ''
          AUTHELIA_STORAGE_ENCRYPTION_KEY=$(cat ${cfg.secrets.encryptionKeyFile})
        ''}
        EOF

        # Copy static config if it exists in the module
        ${lib.optionalString (builtins.pathExists ./config/configuration.yml) ''
          cp ${./config/configuration.yml} ${cfg.configPath}/configuration.yml
        ''}

        # Create users database if it doesn't exist
        if [ ! -f ${cfg.configPath}/users_database.yml ]; then
          cat > ${cfg.configPath}/users_database.yml <<'USERS_DB'
        users: {}
        USERS_DB
        fi
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
