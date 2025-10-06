# Obsidian LiveSync with CouchDB Container Module
{ config, lib, pkgs, ... }:

let
  cfg = config.modules.nixos.docker.containers.obsidian-sync;
  containerName = "obsidian-sync";
  containerPath = "/var/lib/docker-containers/${containerName}";
in
{
  options.modules.nixos.docker.containers.obsidian-sync = {
    enable = lib.mkEnableOption "Obsidian LiveSync with CouchDB";

    domain = lib.mkOption {
      type = lib.types.str;
      default = "solivan.dev";
      description = "Base domain for CouchDB";
    };

    subdomain = lib.mkOption {
      type = lib.types.str;
      default = "obsidian-db";
      description = "Subdomain for CouchDB";
    };

    port = lib.mkOption {
      type = lib.types.int;
      default = 5984;
      description = "Port for CouchDB web interface";
    };

    timezone = lib.mkOption {
      type = lib.types.str;
      default = "America/New_York";
      description = "Timezone for container";
    };

    couchdbUser = lib.mkOption {
      type = lib.types.str;
      default = "obsidian_user";
      description = "CouchDB admin username";
    };

    couchdbPassword = lib.mkOption {
      type = lib.types.str;
      default = "changeme";
      description = "CouchDB admin password";
    };

    dataPath = lib.mkOption {
      type = lib.types.str;
      default = "/mnt/titan/docker/obsidian-sync";
      description = "Path for CouchDB data and configuration";
    };

    enableWatchtower = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable Watchtower auto-updates";
    };
  };

  config = lib.mkIf cfg.enable {
    virtualisation.docker.enable = true;

    systemd.tmpfiles.rules = [
      "d ${containerPath} 0755 root root -"
      "d ${cfg.dataPath} 0755 5984 5984 -"
      "d ${cfg.dataPath}/couchdb 0755 5984 5984 -"
      "d ${cfg.dataPath}/couchdb/data 0755 5984 5984 -"
      "d ${cfg.dataPath}/couchdb/etc 0755 5984 5984 -"
    ];

    systemd.services."docker-container-${containerName}" = {
      description = "Obsidian LiveSync CouchDB Container";
      after = [ "docker.service" "docker-network-proxy.service" ];
      requires = [ "docker.service" "docker-network-proxy.service" ];
      wantedBy = [ "multi-user.target" ];

      preStart = ''
        # Copy docker-compose.yml to runtime directory
        cp ${./docker-compose.yml} ${containerPath}/docker-compose.yml

        # Generate .env file
        cat > ${containerPath}/.env <<EOF
        COUCHDB_DOMAIN=${cfg.subdomain}.${cfg.domain}
        COUCHDB_PORT=${toString cfg.port}
        COUCHDB_USER=${cfg.couchdbUser}
        COUCHDB_PASSWORD=${cfg.couchdbPassword}
        DATA_PATH=${cfg.dataPath}
        TZ=${cfg.timezone}
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

    networking.firewall.allowedTCPPorts = [ cfg.port ];
  };
}
