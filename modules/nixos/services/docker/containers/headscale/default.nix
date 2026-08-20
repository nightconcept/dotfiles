# Headscale Container Module
#
# Self-hosted, open-source control server for the Tailscale mesh VPN. The
# official Tailscale clients (including mobile) connect to it in place of
# Tailscale's SaaS coordination server via `tailscale up --login-server`.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.modules.nixos.docker.containers.headscale;
  containerName = "headscale";
  containerPath = "/var/lib/docker-containers/${containerName}";
in {
  options.modules.nixos.docker.containers.headscale = {
    enable = lib.mkEnableOption "Headscale";

    domain = lib.mkOption {
      type = lib.types.str;
      default = "solivan.dev";
      description = "Base domain for Headscale";
    };

    localDomain = lib.mkOption {
      type = lib.types.str;
      default = "local.solivan.dev";
      description = "Local domain for Headscale";
    };

    subdomain = lib.mkOption {
      type = lib.types.str;
      default = "hs";
      description = "Subdomain for Headscale's control server (server_url)";
    };

    magicDnsDomain = lib.mkOption {
      type = lib.types.str;
      default = "ts.solivan.dev";
      description = "Base domain used for tailnet MagicDNS names (not publicly resolved)";
    };

    dataPath = lib.mkOption {
      type = lib.types.str;
      default = "/home/danny/docker/headscale/data";
      description = "Path to Headscale data directory (sqlite db, node keys)";
    };
  };

  config = lib.mkIf cfg.enable {
    # Ensure Docker is enabled
    virtualisation.docker.enable = true;

    # Create required directories
    systemd.tmpfiles.rules = [
      "d ${containerPath} 0755 root root -"
      "d ${containerPath}/config 0755 root root -"
      "d /home/danny/docker/headscale 0755 danny users -"
    ];

    # Headscale container service
    systemd.services."docker-container-${containerName}" = {
      description = "Headscale Container";
      after = ["docker.service" "docker-network-proxy.service"];
      requires = ["docker.service" "docker-network-proxy.service"];
      wantedBy = ["multi-user.target"];

      preStart = ''
        # Copy docker-compose.yml to runtime directory
        cp ${./docker-compose.yml} ${containerPath}/docker-compose.yml

        # Generate .env file
        cat > ${containerPath}/.env <<EOF
        CONFIG_PATH=${containerPath}/config
        DATA_PATH=${cfg.dataPath}
        DOMAIN=${cfg.domain}
        LOCAL_DOMAIN=${cfg.localDomain}
        SUBDOMAIN=${cfg.subdomain}
        EOF

        # Render config.yaml from template with the .env values
        set -a
        . ${containerPath}/.env
        MAGIC_DNS_DOMAIN=${cfg.magicDnsDomain}
        set +a
        ${pkgs.gettext}/bin/envsubst \
          '$SUBDOMAIN $DOMAIN $MAGIC_DNS_DOMAIN' \
          < ${./config/config.yaml} \
          > ${containerPath}/config/config.yaml

        # Ensure data directory has correct permissions
        mkdir -p ${cfg.dataPath}
        chown -R danny:users ${cfg.dataPath}
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
