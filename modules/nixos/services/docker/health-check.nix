{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.modules.nixos.docker.healthCheck;
  inherit (lib) concatMapStringsSep escapeShellArg mkEnableOption mkIf mkOption types;

  containerArgs = lib.escapeShellArgs cfg.expectedContainers;
  mountChecks =
    concatMapStringsSep "\n" (path: ''
      check_mount ${escapeShellArg path}
    '')
    cfg.mounts;
  httpChecks =
    concatMapStringsSep "\n" (check: ''
      check_http ${escapeShellArg check.name} ${escapeShellArg check.url} ${escapeShellArg (lib.concatStringsSep "," check.acceptedStatusCodes)}
    '')
    cfg.httpChecks;

  healthChecker = pkgs.writeShellApplication {
    name = "docker-services-health";
    runtimeInputs = with pkgs; [coreutils curl docker util-linux];
    text = ''
      set +e

      wait_mode=false
      wait_timeout=${toString cfg.startupTimeout}
      if [[ "''${1:-}" == "--wait" ]]; then
        wait_mode=true
        wait_timeout="''${2:-$wait_timeout}"
      fi

      check_once() {
        local failures=()
        local container status health

        for container in ${containerArgs}; do
          if ! status=$(docker inspect --format '{{.State.Status}}' "$container" 2>/dev/null); then
            failures+=("container $container is missing")
            continue
          fi
          if [[ "$status" != "running" ]]; then
            failures+=("container $container is $status")
            continue
          fi
          health=$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$container" 2>/dev/null)
          if [[ "$health" != "none" && "$health" != "healthy" ]]; then
            failures+=("container $container is $health")
          fi
        done

        ${lib.optionalString (cfg.mounts != []) ''
          check_mount() {
            local path="$1"
          if ! findmnt --target "$path" >/dev/null 2>&1; then
            failures+=("mount $path is not mounted")
          elif ! timeout 10 ls "$path" >/dev/null 2>&1; then
            failures+=("mount $path is not readable")
          fi
        }
      ''}

        ${lib.optionalString (cfg.httpChecks != []) ''
          check_http() {
            local name="$1"
            local url="$2"
            local accepted="$3"
            local code
          code=$(curl --silent --show-error --output /dev/null --write-out '%{http_code}' --connect-timeout 5 --max-time 15 "$url" 2>/dev/null)
          if [[ ",$accepted," != *",$code,"* ]]; then
            failures+=("HTTP $name returned ''${code:-no response}")
          fi
        }
      ''}

        ${mountChecks}
        ${httpChecks}

        if (( ''${#failures[@]} > 0 )); then
          printf '%s\n' "''${failures[@]}" >&2
          return 1
        fi

        echo "all expected Docker services are healthy"
        return 0
      }

      deadline=$((SECONDS + wait_timeout))
      while ! output=$(check_once 2>&1); do
        if ! $wait_mode || (( SECONDS >= deadline )); then
          echo "$output" >&2
          exit 1
        fi
        sleep 5
      done

      echo "$output"
      ${lib.optionalString (cfg.externalHeartbeatUrlFile != null) ''
        if [[ -s ${escapeShellArg cfg.externalHeartbeatUrlFile} ]]; then
          curl --silent --show-error --fail --max-time 15 "$(<${escapeShellArg cfg.externalHeartbeatUrlFile})" >/dev/null
        fi
      ''}
    '';
  };

  endpoint = pkgs.writeText "docker-health-endpoint.py" ''
    import http.server
    import subprocess


    class Handler(http.server.BaseHTTPRequestHandler):
        def do_GET(self):
            if self.path != "/health":
                self.send_error(404)
                return
            result = subprocess.run(
                ["${healthChecker}/bin/docker-services-health"],
                capture_output=True,
                check=False,
                text=True,
                timeout=${toString (cfg.startupTimeout + 30)},
            )
            body = (result.stdout + result.stderr).strip().encode()
            self.send_response(200 if result.returncode == 0 else 503)
            self.send_header("Content-Type", "text/plain; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def log_message(self, format, *args):
            return


    http.server.ThreadingHTTPServer(("${cfg.listenAddress}", ${toString cfg.port}), Handler).serve_forever()
  '';
in {
  options.modules.nixos.docker.healthCheck = {
    enable = mkEnableOption "host-local Docker service readiness checks";

    expectedContainers = mkOption {
      type = types.listOf types.str;
      default = [];
      description = "Containers which must exist, be running, and be healthy when they define a Docker health check.";
    };

    mounts = mkOption {
      type = types.listOf types.str;
      default = [];
      description = "Mounts which must be mounted and readable.";
    };

    httpChecks = mkOption {
      type = types.listOf (types.submodule {
        options = {
          name = mkOption {type = types.str;};
          url = mkOption {type = types.str;};
          acceptedStatusCodes = mkOption {
            type = types.listOf types.str;
            default = ["200"];
          };
        };
      });
      default = [];
      description = "Host-local HTTP checks performed in addition to Docker state inspection.";
    };

    afterUnits = mkOption {
      type = types.listOf types.str;
      default = [];
      description = "Container units that should be started before the initial readiness gate.";
    };

    startupTimeout = mkOption {
      type = types.ints.positive;
      default = 300;
      description = "Seconds to wait for all checks to pass during boot.";
    };

    recheckTimeout = mkOption {
      type = types.ints.positive;
      default = 60;
      description = "Seconds to tolerate transient failures during recurring checks.";
    };

    interval = mkOption {
      type = types.str;
      default = "1min";
      description = "Interval for continuous readiness checks.";
    };

    port = mkOption {
      type = types.port;
      default = 3002;
      description = "LAN-only HTTP readiness endpoint port.";
    };

    listenAddress = mkOption {
      type = types.str;
      default = "127.0.0.1";
      description = "Address on which to expose the readiness endpoint.";
    };

    externalHeartbeatUrlFile = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Optional file containing an external dead-man heartbeat URL.";
    };
  };

  config = mkIf cfg.enable {
    systemd.services.docker-services-ready = {
      description = "Verify all required Docker services are healthy";
      after = ["docker.service" "network-online.target"] ++ cfg.afterUnits;
      wants = ["network-online.target"] ++ cfg.afterUnits;
      requires = ["docker.service"];
      wantedBy = ["multi-user.target"];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${healthChecker}/bin/docker-services-health --wait";
      };
    };

    systemd.services.docker-services-health = {
      description = "Recheck all required Docker services";
      after = ["docker.service"] ++ cfg.afterUnits;
      requires = ["docker.service"];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${healthChecker}/bin/docker-services-health --wait ${toString cfg.recheckTimeout}";
      };
    };

    systemd.timers.docker-services-health = {
      description = "Continuously verify required Docker services";
      wantedBy = ["timers.target"];
      timerConfig = {
        OnBootSec = "5min";
        OnUnitActiveSec = cfg.interval;
        Unit = "docker-services-health.service";
      };
    };

    systemd.services.docker-health-endpoint = {
      description = "Expose host-local Docker readiness to the monitoring network";
      after = ["docker.service"];
      requires = ["docker.service"];
      wantedBy = ["multi-user.target"];
      serviceConfig = {
        ExecStart = "${pkgs.python3}/bin/python ${endpoint}";
        Restart = "on-failure";
        RestartSec = 5;
      };
    };

    networking.firewall.allowedTCPPorts = [cfg.port];
  };
}
