# events: self-hosted Facebook Events replacement (forge: nightconcept/events).
#
# The image builds on Rinoa from the pinned `events` flake input. The
# Cloudflare Tunnel routes the public hostname to http://events:8080. Login
# texts go through the httpSMS module on the same host.
{
  config,
  inputs,
  lib,
  pkgs,
  ...
}: let
  cfg = config.modules.nixos.docker.containers.events;
  containerName = "events";
  containerPath = "/var/lib/docker-containers/${containerName}";
  secretDir = "/run/secrets/services/events";
  secretUnits =
    lib.optionals config.modules.nixos.security.sops.enable ["sops-install-secrets.service"];
  usesTitan = lib.hasPrefix "/mnt/titan" cfg.backupPath;
  sourceTag = builtins.substring 0 12 (cfg.source.rev or "local");
  # The app trusts CF-Connecting-IP, so only cloudflared may reach it: it is
  # not on the shared proxy network. It reaches httpSMS (and gets the webhook)
  # on a network shared only with httpsms-api. Both networks allow egress.
  edgeNetwork = "events-edge";
  smsNetwork = "events-sms";
  networkUnits = map (n: "docker-network-${n}.service") [edgeNetwork smsNetwork];
in {
  options.modules.nixos.docker.containers.events = {
    enable = lib.mkEnableOption "events web app";

    source = lib.mkOption {
      type = lib.types.path;
      default = inputs.events;
      description = "Pinned events source used as the Docker build context";
    };

    baseUrl = lib.mkOption {
      type = lib.types.str;
      default = "https://events.solivan.dev";
      description = "Public URL. Login links in texts point here.";
    };

    dataPath = lib.mkOption {
      type = lib.types.str;
      default = "${containerPath}/data";
      description = "SQLite database and photos";
    };

    backupPath = lib.mkOption {
      type = lib.types.str;
      default = "/mnt/titan/backups/events";
      description = "Nightly database snapshots and photo mirror (14 days)";
    };
  };

  config = lib.mkIf cfg.enable {
    virtualisation.docker.enable = true;

    modules.nixos.docker = {
      networks = [edgeNetwork smsNetwork];
      containers.cloudflare-tunnel.extraNetworks = [edgeNetwork];
      containers.httpsms.apiExtraNetworks = [smsNetwork];
    };

    systemd.tmpfiles.rules = [
      "d ${containerPath} 0700 root root -"
      "d ${cfg.dataPath} 0750 1000 100 -"
    ];

    systemd.services."docker-container-${containerName}" = {
      description = "events Web App Container";
      after =
        ["docker.service" "docker-container-httpsms.service"]
        ++ networkUnits
        ++ secretUnits
        ++ lib.optionals usesTitan ["mnt-titan.mount"];
      requires =
        ["docker.service"]
        ++ networkUnits
        ++ secretUnits
        ++ lib.optionals usesTitan ["mnt-titan.mount"];
      # The app works without the gateway: texts queue, and the admin can
      # copy personal links.
      wants = ["docker-container-httpsms.service"];
      wantedBy = ["multi-user.target"];
      unitConfig = lib.mkIf usesTitan {
        RequiresMountsFor = [cfg.backupPath];
      };
      restartTriggers = [./docker-compose.yml];
      path = [pkgs.coreutils pkgs.gnugrep pkgs.util-linux];

      preStart = ''
        set -euo pipefail
        secret() { cat ${secretDir}/"$1"; }

        for key in admin_password turnstile_sitekey turnstile_secret httpsms_api_key httpsms_from httpsms_webhook_key; do
          if [ ! -r ${secretDir}/"$key" ]; then
            echo "events secret $key is unavailable" >&2
            exit 1
          fi
          if grep -qx CHANGEME ${secretDir}/"$key"; then
            echo "events secret $key is still CHANGEME; see docs/docker.md#events-on-rinoa" >&2
            exit 1
          fi
        done

        ${lib.optionalString usesTitan ''
          if ! mountpoint -q /mnt/titan; then
            echo "Titan is not mounted at /mnt/titan" >&2
            exit 1
          fi
        ''}
        install -d -o 1000 -g 100 -m 0750 ${lib.escapeShellArg cfg.dataPath}
        install -d ${lib.escapeShellArg cfg.backupPath}

        install -m 0644 ${./docker-compose.yml} ${containerPath}/docker-compose.yml
        umask 077
        {
          printf 'ADMIN_PASSWORD=%s\n' "$(secret admin_password)"
          printf 'TURNSTILE_SITEKEY=%s\n' "$(secret turnstile_sitekey)"
          printf 'TURNSTILE_SECRET=%s\n' "$(secret turnstile_secret)"
          printf 'HTTPSMS_API_KEY=%s\n' "$(secret httpsms_api_key)"
          printf 'HTTPSMS_FROM=%s\n' "$(secret httpsms_from)"
          printf 'HTTPSMS_WEBHOOK_KEY=%s\n' "$(secret httpsms_webhook_key)"
        } > ${containerPath}/app.env
        {
          printf 'EVENTS_SOURCE=%s\n' ${cfg.source}
          printf 'EVENTS_TAG=%s\n' ${sourceTag}
          printf 'BASE_URL=%s\n' ${lib.escapeShellArg cfg.baseUrl}
          printf 'DATA_PATH=%s\n' ${lib.escapeShellArg cfg.dataPath}
          printf 'BACKUP_PATH=%s\n' ${lib.escapeShellArg cfg.backupPath}
        } > ${containerPath}/.env
      '';

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        WorkingDirectory = containerPath;
        TimeoutStartSec = "15min";
        ExecStart = "${pkgs.docker-compose}/bin/docker-compose up -d --wait --wait-timeout 300";
        ExecStop = "${pkgs.docker-compose}/bin/docker-compose down";
        ExecReload = "${pkgs.docker-compose}/bin/docker-compose restart";
      };
    };
  };
}
