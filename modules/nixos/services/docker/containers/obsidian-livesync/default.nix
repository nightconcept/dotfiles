# Self-hosted LiveSync CouchDB container module
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.modules.nixos.docker.containers.obsidian-livesync;
  containerName = "obsidian-livesync";
  containerPath = "/var/lib/docker-containers/${containerName}";
  usesTitan = lib.hasPrefix "/mnt/titan" cfg.dataPath;
  secretUnits =
    lib.optionals config.modules.nixos.security.sops.enable ["sops-install-secrets.service"];
in {
  options.modules.nixos.docker.containers.obsidian-livesync = {
    enable = lib.mkEnableOption "Self-hosted LiveSync CouchDB server";

    domain = lib.mkOption {
      type = lib.types.str;
      default = "solivan.dev";
      description = "Public base domain for Self-hosted LiveSync";
    };

    localDomain = lib.mkOption {
      type = lib.types.str;
      default = "local.solivan.dev";
      description = "Local base domain for Self-hosted LiveSync";
    };

    subdomain = lib.mkOption {
      type = lib.types.str;
      default = "obsidian-db";
      description = "Subdomain for Self-hosted LiveSync";
    };

    database = lib.mkOption {
      type = lib.types.str;
      default = "obsidiannotes";
      description = "CouchDB database used by Self-hosted LiveSync";
    };

    dataPath = lib.mkOption {
      type = lib.types.str;
      default = "/mnt/titan/docker/obsidian-livesync/data";
      description = "Persistent CouchDB data directory";
    };

    usernameFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default =
        if config.modules.nixos.security.sops.enable
        then "/run/secrets/services/obsidian-livesync/username"
        else null;
      description = "File containing the CouchDB administrator username";
    };

    passwordFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default =
        if config.modules.nixos.security.sops.enable
        then "/run/secrets/services/obsidian-livesync/password"
        else null;
      description = "File containing the CouchDB administrator password";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.usernameFile != null && cfg.passwordFile != null;
        message = "obsidian-livesync requires usernameFile and passwordFile";
      }
    ];

    virtualisation.docker.enable = true;

    systemd.tmpfiles.rules = [
      "d ${containerPath} 0700 root root -"
    ];

    systemd.services."docker-container-${containerName}" = {
      description = "Self-hosted LiveSync CouchDB Container";
      after =
        ["docker.service" "docker-network-proxy.service"]
        ++ secretUnits
        ++ lib.optionals usesTitan ["mnt-titan.mount"];
      requires =
        ["docker.service" "docker-network-proxy.service"]
        ++ secretUnits
        ++ lib.optionals usesTitan ["mnt-titan.mount"];
      wantedBy = ["multi-user.target"];
      unitConfig = lib.mkIf usesTitan {
        RequiresMountsFor = [cfg.dataPath];
      };
      restartTriggers = [
        ./couchdb-init.sh
        ./docker-compose.yml
        ./livesync.ini
      ];

      preStart = ''
        ${lib.optionalString usesTitan ''
          if ! ${pkgs.util-linux}/bin/mountpoint -q /mnt/titan; then
            echo "Titan is not mounted at /mnt/titan" >&2
            exit 1
          fi
          if ! ${pkgs.util-linux}/bin/findmnt --raw --noheadings --output FSTYPE --target ${lib.escapeShellArg cfg.dataPath} \
            | ${pkgs.gnugrep}/bin/grep -Fxq cifs; then
            echo "${cfg.dataPath} is not backed by the Titan CIFS mount" >&2
            exit 1
          fi
        ''}

        ${pkgs.coreutils}/bin/install -d -m 0755 ${lib.escapeShellArg cfg.dataPath}
        ${pkgs.coreutils}/bin/install -m 0644 ${./docker-compose.yml} ${containerPath}/docker-compose.yml
        ${pkgs.coreutils}/bin/install -m 0644 ${./livesync.ini} ${containerPath}/livesync.ini
        ${pkgs.coreutils}/bin/install -m 0755 ${./couchdb-init.sh} ${containerPath}/couchdb-init.sh

        if [ ! -r ${lib.escapeShellArg cfg.usernameFile} ] || [ ! -r ${lib.escapeShellArg cfg.passwordFile} ]; then
          echo "Self-hosted LiveSync credentials are unavailable" >&2
          exit 1
        fi

        ${pkgs.coreutils}/bin/touch ${lib.escapeShellArg "${cfg.dataPath}/.rinoa-write-probe"}
        ${pkgs.coreutils}/bin/unlink ${lib.escapeShellArg "${cfg.dataPath}/.rinoa-write-probe"}

        umask 077
        {
          printf 'COUCHDB_USER=%s\n' "$(<${lib.escapeShellArg cfg.usernameFile})"
          printf 'COUCHDB_PASSWORD=%s\n' "$(<${lib.escapeShellArg cfg.passwordFile})"
          printf 'COUCHDB_DATABASE=%s\n' ${lib.escapeShellArg cfg.database}
          printf 'DATA_PATH=%s\n' ${lib.escapeShellArg cfg.dataPath}
          printf 'PUID=1000\n'
          printf 'PGID=100\n'
          printf 'DOMAIN=%s\n' ${lib.escapeShellArg cfg.domain}
          printf 'LOCAL_DOMAIN=%s\n' ${lib.escapeShellArg cfg.localDomain}
          printf 'SUBDOMAIN=%s\n' ${lib.escapeShellArg cfg.subdomain}
          printf 'TRAEFIK_ENABLE=true\n'
        } > ${containerPath}/.env
      '';

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        WorkingDirectory = containerPath;
        ExecStart = "${pkgs.docker-compose}/bin/docker-compose up -d --wait --wait-timeout 180";
        ExecStop = "${pkgs.docker-compose}/bin/docker-compose down";
        ExecReload = "${pkgs.docker-compose}/bin/docker-compose restart couchdb";
      };
    };
  };
}
