# Blog Static Site Container Module
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.modules.nixos.docker.containers.blog;
  containerName = "blog";
  containerPath = "/var/lib/docker-containers/${containerName}";
in {
  options.modules.nixos.docker.containers.blog = {
    enable = lib.mkEnableOption "Blog static site container";

    domain = lib.mkOption {
      type = lib.types.str;
      default = "local.solivan.dev";
      description = "Base domain for blog";
    };

    subdomain = lib.mkOption {
      type = lib.types.str;
      default = "blog";
      description = "Subdomain for blog";
    };

    port = lib.mkOption {
      type = lib.types.int;
      default = 8080;
      description = "Port for blog web server";
    };

    sitePath = lib.mkOption {
      type = lib.types.str;
      default = "/var/www/blog";
      description = "Path to deployed static site files (built artifacts)";
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
      "d ${cfg.sitePath} 0755 danny users -"
    ];

    systemd.services."docker-container-${containerName}" = {
      description = "Blog Static Site Container";
      after = ["docker.service" "docker-network-proxy.service"];
      requires = ["docker.service" "docker-network-proxy.service"];
      wantedBy = ["multi-user.target"];

      preStart = ''
        # Copy docker-compose.yml to runtime directory
        cp ${./docker-compose.yml} ${containerPath}/docker-compose.yml

        # Generate .env file
        cat > ${containerPath}/.env <<EOF
        BLOG_DOMAIN=${cfg.subdomain}.${cfg.domain}
        BLOG_PORT=${toString cfg.port}
        SITE_PATH=${cfg.sitePath}
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

    networking.firewall.allowedTCPPorts = [cfg.port];
  };
}
