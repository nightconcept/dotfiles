# Uptime Kuma Monitoring Container Module
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.modules.nixos.docker.containers.uptime-kuma;
  containerName = "uptimekuma";
  containerPath = "/var/lib/docker-containers/${containerName}";
  python = pkgs.python3.withPackages (ps: [ps."uptime-kuma-api"]);
  monitorFile = pkgs.writeText "uptime-kuma-monitors.json" (builtins.toJSON cfg.monitors);
  provisioner = pkgs.writeText "provision-uptime-kuma.py" ''
    import json
    import pathlib
    import sys

    from uptime_kuma_api import MonitorType, UptimeKumaApi


    url, username, password_file, monitors_file = sys.argv[1:]
    password = pathlib.Path(password_file).read_text().strip()
    desired = json.loads(pathlib.Path(monitors_file).read_text())
    marker = "[managed-by-nix]"

    with UptimeKumaApi(url, timeout=30) as api:
        if api.need_setup():
            api.setup(username, password)
        api.login(username, password)

        current = {monitor["name"]: monitor for monitor in api.get_monitors()}
        desired_names = {monitor["name"] for monitor in desired}
        default_notifications = [
            notification["id"]
            for notification in api.get_notifications()
            if notification.get("isDefault")
        ]

        for monitor in desired:
            spec = {key: value for key, value in monitor.items() if value is not None}
            spec["type"] = MonitorType(spec["type"])
            detail = spec.get("description", "")
            spec["description"] = f"{marker} {detail}".strip()
            existing = current.get(spec["name"])
            if existing:
                spec["notificationIDList"] = (
                    existing.get("notificationIDList") or default_notifications
                )
                api.edit_monitor(existing["id"], **spec)
            else:
                spec["notificationIDList"] = default_notifications
                api.add_monitor(**spec)

        for name, monitor in current.items():
            if name not in desired_names and str(monitor.get("description", "")).startswith(marker):
                api.delete_monitor(monitor["id"])
  '';
in {
  options.modules.nixos.docker.containers.uptime-kuma = {
    enable = lib.mkEnableOption "Uptime Kuma monitoring service";

    domain = lib.mkOption {
      type = lib.types.str;
      default = "local.solivan.dev";
      description = "Base domain for Uptime Kuma";
    };

    subdomain = lib.mkOption {
      type = lib.types.str;
      default = "status";
      description = "Subdomain for Uptime Kuma";
    };

    port = lib.mkOption {
      type = lib.types.int;
      default = 3001;
      description = "Port for Uptime Kuma web interface";
    };

    listenAddress = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = "Host address on which to publish Uptime Kuma.";
    };

    dataPath = lib.mkOption {
      type = lib.types.str;
      default = "${containerPath}/data";
      description = "Path to Uptime Kuma data";
    };

    adminUsername = lib.mkOption {
      type = lib.types.str;
      default = "admin";
      description = "Administrator used by the idempotent monitor provisioner.";
    };

    adminPasswordFile = lib.mkOption {
      type = lib.types.str;
      default = "${containerPath}/admin-password";
      description = "Persistent file containing the Uptime Kuma administrator password.";
    };

    monitors = lib.mkOption {
      type = lib.types.listOf (lib.types.submodule {
        options = {
          name = lib.mkOption {type = lib.types.str;};
          type = lib.mkOption {
            type = lib.types.enum ["http" "ping" "port"];
          };
          url = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
          };
          hostname = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
          };
          port = lib.mkOption {
            type = lib.types.nullOr lib.types.port;
            default = null;
          };
          description = lib.mkOption {
            type = lib.types.str;
            default = "";
          };
          interval = lib.mkOption {
            type = lib.types.ints.positive;
            default = 60;
          };
          retryInterval = lib.mkOption {
            type = lib.types.ints.positive;
            default = 30;
          };
          maxretries = lib.mkOption {
            type = lib.types.ints.positive;
            default = 3;
          };
          accepted_statuscodes = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = ["200-299" "300-399"];
          };
          expiryNotification = lib.mkOption {
            type = lib.types.bool;
            default = true;
          };
        };
      });
      default = [];
      description = "Declarative monitors reconciled into Uptime Kuma by name.";
    };
  };

  config = lib.mkIf cfg.enable {
    virtualisation.docker.enable = true;

    systemd.tmpfiles.rules = [
      "d ${containerPath} 0755 root root -"
      "d ${cfg.dataPath} 0755 root root -"
    ];

    systemd.services."docker-container-${containerName}" = {
      description = "Uptime Kuma Monitoring Container";
      after = ["docker.service" "docker-network-proxy.service" "network-online.target"];
      requires = ["docker.service" "docker-network-proxy.service"];
      wants = ["network-online.target"];
      wantedBy = ["multi-user.target"];

      preStart = ''
        # Copy docker-compose.yml to runtime directory
        cp ${./docker-compose.yml} ${containerPath}/docker-compose.yml

        # Generate .env file
        cat > ${containerPath}/.env <<EOF
        DATA_PATH=${cfg.dataPath}
        PORT=${toString cfg.port}
        LISTEN_ADDRESS=${cfg.listenAddress}
        DOMAIN=${cfg.subdomain}.${cfg.domain}
        EOF

        if [ ! -s ${cfg.adminPasswordFile} ]; then
          umask 077
          ${pkgs.openssl}/bin/openssl rand -base64 36 > ${cfg.adminPasswordFile}
        fi
      '';

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        WorkingDirectory = containerPath;
        ExecStart = "${pkgs.docker-compose}/bin/docker-compose up -d --wait --wait-timeout 180";
        ExecStop = "${pkgs.docker-compose}/bin/docker-compose down";
      };
    };

    systemd.services.uptime-kuma-provision = lib.mkIf (cfg.monitors != []) {
      description = "Reconcile declarative Uptime Kuma monitors";
      after = ["docker-container-${containerName}.service"];
      requires = ["docker-container-${containerName}.service"];
      wantedBy = ["multi-user.target"];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${python}/bin/python ${provisioner} http://${cfg.listenAddress}:${toString cfg.port} ${lib.escapeShellArg cfg.adminUsername} ${lib.escapeShellArg cfg.adminPasswordFile} ${monitorFile}";
        Restart = "on-failure";
        RestartSec = 10;
      };
    };

    networking.firewall.allowedTCPPorts = [cfg.port];
  };
}
