# Zotero WebDAV Container Module
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.modules.nixos.docker.containers.zotero-webdav;
  containerName = "zotero-webdav";
  containerPath = "/var/lib/docker-containers/${containerName}";
in {
  options.modules.nixos.docker.containers.zotero-webdav = {
    enable = lib.mkEnableOption "Zotero WebDAV server";

    domain = lib.mkOption {
      type = lib.types.str;
      default = "local.solivan.dev";
      description = "Base domain for Zotero WebDAV";
    };

    subdomain = lib.mkOption {
      type = lib.types.str;
      default = "zotero";
      description = "Subdomain for Zotero WebDAV";
    };

    dataPath = lib.mkOption {
      type = lib.types.str;
      default = "/home/danny/docker/zotero/data";
      description = "Path to WebDAV data directory";
    };

    usernameFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default =
        if config.modules.nixos.security.sops.enable
        then "/run/secrets/services/zotero/username"
        else null;
      description = "Path to file containing WebDAV username";
    };

    passwordFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default =
        if config.modules.nixos.security.sops.enable
        then "/run/secrets/services/zotero/password"
        else null;
      description = "Path to file containing WebDAV password";
    };
  };

  config = lib.mkIf cfg.enable {
    virtualisation.docker.enable = true;

    systemd.tmpfiles.rules = [
      "d ${containerPath} 0755 root root -"
      "d /home/danny/docker/zotero 0755 danny users -"
      "d ${cfg.dataPath} 0755 danny users -"
    ];

    systemd.services."docker-container-${containerName}" = {
      description = "Zotero WebDAV Container";
      after = ["docker.service" "docker-network-proxy.service"];
      requires = ["docker.service" "docker-network-proxy.service"];
      wantedBy = ["multi-user.target"];

      preStart = ''
        # Copy docker-compose.yml to runtime directory
        cp ${./docker-compose.yml} ${containerPath}/docker-compose.yml

        # Generate .env file
        cat > ${containerPath}/.env <<EOF
        DOMAIN=${cfg.domain}
        SUBDOMAIN=${cfg.subdomain}
        DATA_PATH=${cfg.dataPath}
        AUTH_TYPE=Basic
        ${lib.optionalString (cfg.usernameFile != null) ''
          USERNAME=$(cat ${cfg.usernameFile})
        ''}
        ${lib.optionalString (cfg.passwordFile != null) ''
          PASSWORD=$(cat ${cfg.passwordFile})
        ''}
        EOF
      '';

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        WorkingDirectory = containerPath;
        ExecStart = "${pkgs.docker-compose}/bin/docker-compose up -d --wait --wait-timeout 180";
        ExecStop = "${pkgs.docker-compose}/bin/docker-compose down";
        ExecReload = "${pkgs.docker-compose}/bin/docker-compose restart";
      };
    };
  };
}
