# Artifacts: single-file HTML pages written by agents, at https://artifacts.solivan.dev/<id>
#
# nginx serves /<id> and takes PUT/DELETE under /_api/ with a bearer token;
# a systemd timer runs sweep.py to expire them. See readme.md and
# home/docs/plans/artifacts-hosting.md. The LAN name is always routed; `public`
# adds artifacts.solivan.dev for the Cloudflare Tunnel hostname.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.modules.nixos.docker.containers.artifacts;
  containerName = "artifacts";
  containerPath = "/var/lib/docker-containers/${containerName}";
  tokenPath = config.sops.secrets.artifacts-write-token.path;
  rule =
    lib.concatStringsSep " || "
    (map (host: "Host(`${host}`)") ([cfg.lanDomain] ++ lib.optional cfg.public cfg.publicDomain));
  sweep = "${pkgs.python3}/bin/python3 ${./sweep.py} --data ${cfg.dataPath} --quota-bytes ${toString (cfg.quotaGiB * 1024 * 1024 * 1024)} --max-items ${toString cfg.maxItems}";
in {
  options.modules.nixos.docker.containers.artifacts = {
    enable = lib.mkEnableOption "artifact hosting for agent-written HTML pages";

    lanDomain = lib.mkOption {
      type = lib.types.str;
      default = "artifacts.local.solivan.dev";
      description = "LAN and Tailscale name, routed by Traefik";
    };

    publicDomain = lib.mkOption {
      type = lib.types.str;
      default = "artifacts.solivan.dev";
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
      description = "Artifacts and the index. They expire, so this is not backed up.";
    };

    quotaGiB = lib.mkOption {
      type = lib.types.ints.positive;
      default = 2;
      description = "Total size above which the sweeper removes the soonest-expiring artifacts";
    };

    maxItems = lib.mkOption {
      type = lib.types.ints.positive;
      default = 500;
      description = "Count above which the sweeper removes the soonest-expiring artifacts";
    };
  };

  config = lib.mkIf cfg.enable {
    virtualisation.docker.enable = true;

    sops.secrets.artifacts-write-token = {
      sopsFile = ../../../../security/sops/artifacts.yaml;
      key = "write_token";
      mode = "0400";
    };

    systemd.tmpfiles.rules = [
      "d ${containerPath} 0755 root root -"
      # nginx-unprivileged runs as uid 101 with a read-only root filesystem.
      "d ${cfg.dataPath} 0755 101 101 -"
    ];

    systemd.services."docker-container-${containerName}" = {
      description = "Artifact hosting";
      after = ["docker.service" "docker-network-proxy.service" "sops-install-secrets.service"];
      requires = ["docker.service" "docker-network-proxy.service" "sops-install-secrets.service"];
      wantedBy = ["multi-user.target"];

      preStart = ''
        test -s ${tokenPath}
        cp ${./docker-compose.yml} ${containerPath}/docker-compose.yml
        cp ${./compose.traefik.yml} ${containerPath}/compose.traefik.yml
        cp ${./nginx.conf} ${containerPath}/nginx.conf

        # The write token, in the shape nginx reads. Owned by nginx's uid, mode 400.
        install -m 400 -o 101 -g 101 /dev/null ${containerPath}/auth.conf
        {
          echo 'map $http_authorization $writer {'
          echo '    default 0;'
          echo "    \"Bearer $(cat ${tokenPath})\" 1;"
          echo '}'
        } > ${containerPath}/auth.conf

        # Quoted heredoc: the rule contains backticks the shell must not run.
        cat > ${containerPath}/.env <<'EOF'
        COMPOSE_FILE=docker-compose.yml:compose.traefik.yml
        DATA_PATH=${cfg.dataPath}
        ARTIFACTS_RULE="${rule}"
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

    # Expiry and the index. Every five minutes: it only scans one folder, and
    # it is what makes a new artifact show up in `artifact list`.
    systemd.services.artifacts-sweep = {
      description = "Expire artifacts and rebuild the index";
      after = ["docker-container-${containerName}.service"];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = sweep;
        ProtectSystem = "strict";
        ReadWritePaths = [cfg.dataPath];
        ProtectHome = true;
        PrivateTmp = true;
        NoNewPrivileges = true;
      };
    };

    systemd.timers.artifacts-sweep = {
      wantedBy = ["timers.target"];
      timerConfig = {
        OnBootSec = "2min";
        OnUnitActiveSec = "5min";
      };
    };
  };
}
