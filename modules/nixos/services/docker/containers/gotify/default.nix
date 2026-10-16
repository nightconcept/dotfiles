# Gotify Push Notification Container Module
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.modules.nixos.docker.containers.gotify;
  containerName = "gotify";
  containerPath = "/var/lib/docker-containers/${containerName}";

  # Gotify 3 returns an application token only when it is created or rotated,
  # so each token is captured once and kept in tokenDir. A missing token file
  # for an existing application triggers a rotation.
  provisioner = pkgs.writeShellApplication {
    name = "provision-gotify";
    runtimeInputs = with pkgs; [coreutils curl jq];
    text = ''
      url="$1"
      username="$2"
      password_file="$3"
      token_dir="$4"
      shift 4

      auth="$username:$(cat "$password_file")"
      api() {
        curl --fail --silent --show-error --user "$auth" "$@"
      }

      for _ in $(seq 1 30); do
        api "$url/current/user" >/dev/null 2>&1 && break
        sleep 2
      done

      umask 077
      mkdir -p "$token_dir"
      applications=$(api "$url/application")

      for name in "$@"; do
        token_file="$token_dir/$name.token"
        id=$(jq -r --arg name "$name" 'map(select(.name == $name)) | first | .id // empty' <<<"$applications")

        if [[ -z "$id" ]]; then
          response=$(api -X POST -H 'Content-Type: application/json' \
            --data "$(jq -n --arg name "$name" '{name: $name, description: "[managed-by-nix]", defaultPriority: 5}')" \
            "$url/application")
        elif [[ ! -s "$token_file" ]]; then
          response=$(api -X PUT -H 'Content-Type: application/json' \
            --data '{"regenerateToken": true}' "$url/application/$id/security")
        else
          continue
        fi

        token=$(jq -r '.token // .regenerateToken.token // empty' <<<"$response")
        if [[ -z "$token" ]]; then
          echo "Gotify returned no token for application $name" >&2
          exit 1
        fi
        printf '%s\n' "$token" >"$token_file"
      done
    '';
  };
  applications = cfg.applications ++ lib.optional cfg.diskAlert.enable "host-alerts";

  # Alerts when a filesystem crosses the threshold, repeats daily while it
  # stays above, and reports once when it recovers.
  diskAlert = pkgs.writeShellApplication {
    name = "gotify-disk-alert";
    runtimeInputs = with pkgs; [coreutils curl findutils];
    text = ''
      url="$1"
      token_file="$2"
      threshold="$3"
      state_dir="$4"
      shift 4

      mkdir -p "$state_dir"
      host=$(cat /proc/sys/kernel/hostname)

      send() {
        curl --fail --silent --show-error --output /dev/null \
          --form-string "title=$1" --form-string "message=$2" --form-string "priority=$3" \
          "$url/message?token=$(cat "$token_file")"
      }

      for path in "$@"; do
        read -r used avail < <(df --output=pcent,avail -h "$path" | tail -n 1 | tr -d '%')
        state="$state_dir/$(printf '%s' "$path" | tr '/' '_')"

        if (( used >= threshold )); then
          if [[ ! -e "$state" ]] || [[ -n "$(find "$state" -mmin +1440)" ]]; then
            send "$host: $path is $used% full" \
              "Only $avail free on $path (alert threshold $threshold%)." 8
            touch "$state"
          fi
        elif [[ -e "$state" ]]; then
          send "$host: $path recovered" "$path is now $used% full ($avail free)." 4
          rm -f "$state"
        fi
      done
    '';
  };
in {
  options.modules.nixos.docker.containers.gotify = {
    enable = lib.mkEnableOption "Gotify push notification server";

    port = lib.mkOption {
      type = lib.types.port;
      default = 8070;
      description = "Host port for the Gotify web UI and API";
    };

    listenAddress = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = "Host address on which to publish Gotify.";
    };

    dataPath = lib.mkOption {
      type = lib.types.str;
      default = "${containerPath}/data";
      description = "Path to Gotify data";
    };

    adminUsername = lib.mkOption {
      type = lib.types.str;
      default = "admin";
      description = "Administrator created on first start and used by the provisioner.";
    };

    adminPasswordFile = lib.mkOption {
      type = lib.types.str;
      default = "${containerPath}/admin-password";
      description = "Persistent file containing the Gotify administrator password.";
    };

    applications = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "Gotify applications to create. Each token is written to tokenDir/<name>.token.";
    };

    diskAlert = {
      enable = lib.mkEnableOption "Gotify alerts for low disk space on this host";

      paths = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = ["/"];
        description = "Filesystems to check.";
      };

      threshold = lib.mkOption {
        type = lib.types.ints.between 1 100;
        default = 85;
        description = "Usage percentage at which to alert.";
      };
    };

    tokenDir = lib.mkOption {
      type = lib.types.str;
      default = "${containerPath}/tokens";
      readOnly = true;
      description = "Directory containing provisioned application tokens.";
    };

    internalUrl = lib.mkOption {
      type = lib.types.str;
      default = "http://${containerName}:80";
      readOnly = true;
      description = "URL that containers on the proxy network use to reach Gotify.";
    };
  };

  config = lib.mkIf cfg.enable {
    virtualisation.docker.enable = true;

    systemd.tmpfiles.rules = [
      "d ${containerPath} 0755 root root -"
      "d ${cfg.dataPath} 0755 root root -"
    ];

    systemd.services."docker-container-${containerName}" = {
      description = "Gotify Push Notification Container";
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
        ADMIN_USERNAME=${cfg.adminUsername}
        ADMIN_PASSWORD_FILE=${cfg.adminPasswordFile}
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

    systemd.services.gotify-provision = lib.mkIf (applications != []) {
      description = "Provision declarative Gotify applications";
      after = ["docker-container-${containerName}.service"];
      requires = ["docker-container-${containerName}.service"];
      wantedBy = ["multi-user.target"];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${lib.getExe provisioner} http://127.0.0.1:${toString cfg.port} ${lib.escapeShellArg cfg.adminUsername} ${lib.escapeShellArg cfg.adminPasswordFile} ${cfg.tokenDir} ${lib.escapeShellArgs applications}";
        Restart = "on-failure";
        RestartSec = 10;
      };
    };

    systemd.services.gotify-disk-alert = lib.mkIf cfg.diskAlert.enable {
      description = "Send a Gotify alert when disk space is low";
      after = ["gotify-provision.service"];
      wants = ["gotify-provision.service"];
      serviceConfig = {
        Type = "oneshot";
        StateDirectory = "gotify-disk-alert";
        ExecStart = "${lib.getExe diskAlert} http://127.0.0.1:${toString cfg.port} ${cfg.tokenDir}/host-alerts.token ${toString cfg.diskAlert.threshold} /var/lib/gotify-disk-alert ${lib.escapeShellArgs cfg.diskAlert.paths}";
      };
    };

    systemd.timers.gotify-disk-alert = lib.mkIf cfg.diskAlert.enable {
      wantedBy = ["timers.target"];
      timerConfig = {
        OnBootSec = "5min";
        OnUnitActiveSec = "1h";
      };
    };

    networking.firewall.allowedTCPPorts = [cfg.port];
  };
}
