# git-pages: static sites for forge repos at https://sites.solivan.dev/<user>/<repo>/
#
# Traefik (with the CrowdSec bouncer) fronts a Caddy router, which maps
# /<user>/<rest> onto git-pages. See readme.md and
# home/docs/plans/red-star-site-publishing.md. The LAN name is always routed;
# `public` adds sites.solivan.dev for the Cloudflare Tunnel hostname.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.modules.nixos.docker.containers.git-pages;
  containerName = "git-pages";
  containerPath = "/var/lib/docker-containers/${containerName}";
  rule =
    lib.concatStringsSep " || "
    (map (host: "Host(`${host}`)") ([cfg.lanDomain] ++ lib.optional cfg.public cfg.publicDomain));
in {
  options.modules.nixos.docker.containers.git-pages = {
    enable = lib.mkEnableOption "git-pages static sites for forge repos";

    lanDomain = lib.mkOption {
      type = lib.types.str;
      default = "sites.local.solivan.dev";
      description = "LAN and Tailscale name, routed by Traefik";
    };

    publicDomain = lib.mkOption {
      type = lib.types.str;
      default = "sites.solivan.dev";
      description = "Public name, reached through the Cloudflare Tunnel";
    };

    public = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Also route the public name. Needs the tunnel hostname in Cloudflare first.";
    };

    dataPath = lib.mkOption {
      type = lib.types.str;
      default = "${containerPath}/data";
      description = "Published site data. It can be rebuilt from the repos, so it is not backed up.";
    };
  };

  config = lib.mkIf cfg.enable {
    virtualisation.docker.enable = true;

    systemd.tmpfiles.rules = [
      "d ${containerPath} 0755 root root -"
      # git-pages runs as 1000:100 with a read-only root filesystem.
      "d ${cfg.dataPath} 0750 1000 100 -"
    ];

    systemd.services."docker-container-${containerName}" = {
      description = "git-pages static sites";
      after = ["docker.service" "docker-network-proxy.service"];
      requires = ["docker.service" "docker-network-proxy.service"];
      wantedBy = ["multi-user.target"];

      preStart = ''
        cp ${./docker-compose.yml} ${containerPath}/docker-compose.yml
        cp ${./compose.traefik.yml} ${containerPath}/compose.traefik.yml
        cp ${./config.toml} ${containerPath}/config.toml
        cp ${./Caddyfile} ${containerPath}/Caddyfile

        # Quoted heredoc: the rule contains backticks the shell must not run.
        cat > ${containerPath}/.env <<'EOF'
        COMPOSE_FILE=docker-compose.yml:compose.traefik.yml
        DATA_PATH=${cfg.dataPath}
        SITES_RULE="${rule}"
        EOF
      '';

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        WorkingDirectory = containerPath;
        ExecStart = "${pkgs.docker-compose}/bin/docker-compose up -d --wait --wait-timeout 120";
        ExecStop = "${pkgs.docker-compose}/bin/docker-compose down";
      };
    };
  };
}
