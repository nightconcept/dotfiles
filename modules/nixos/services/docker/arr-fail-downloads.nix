# Marks Sonarr and Radarr grabs containing executables (.exe, .bat, .cmd, .sh)
# or potentially dangerous files (.lnk, .scr, .ps1, .vbs, ...) as failed so the
# release is removed and blocklisted. Only *arr grabs are affected; torrents
# added to qBittorrent directly are not checked.
#
# The setting lives per indexer in each app's database, and indexers synced by
# Prowlarr arrive with it empty, so a timer re-applies it to every indexer.
{
  config,
  lib,
  pkgs,
  ...
}: let
  containers = config.modules.nixos.docker.containers;

  # Sonarr/Radarr FailDownloads enum: 0 = Executables, 1 = Potentially Dangerous.
  enforcer = pkgs.writeShellApplication {
    name = "arr-fail-downloads";
    runtimeInputs = with pkgs; [coreutils curl gnused jq];
    text = ''
      # Arguments: repeated <name> <url> <config.xml> triples.
      while (( $# >= 3 )); do
        name="$1"
        url="$2"
        config_xml="$3"
        shift 3

        api_key=$(sed -n 's:.*<ApiKey>\(.*\)</ApiKey>.*:\1:p' "$config_xml")
        if [[ -z "$api_key" ]]; then
          echo "$name: no ApiKey in $config_xml" >&2
          exit 1
        fi
        api() {
          curl --fail --silent --show-error --header "X-Api-Key: $api_key" "$@"
        }

        for _ in $(seq 1 30); do
          api "$url/ping" >/dev/null 2>&1 && break
          sleep 2
        done

        api "$url/api/v3/indexer" | jq -c '.[]' | while read -r indexer; do
          updated=$(jq -c '
            .fields |= map(
              if .name == "failDownloads" then .value = ((.value // []) + [0, 1] | unique)
              elif .name == "rejectTorrentFilesWithBlockedExtensionsWhileGrabbing" then .value = true
              else . end)' <<<"$indexer")
          if [[ "$updated" == "$indexer" ]]; then
            continue
          fi

          id=$(jq -r '.id' <<<"$indexer")
          api -X PUT -H 'Content-Type: application/json' --data "$updated" \
            "$url/api/v3/indexer/$id?forceSave=true" >/dev/null
          echo "$name: enabled Fail Downloads on indexer $(jq -r '.name' <<<"$indexer")"
        done
      done
    '';
  };

  apps =
    lib.optional containers.sonarr.enable {
      name = "sonarr";
      inherit (containers.sonarr) port configPath;
    }
    ++ lib.optional containers.sonarr-anime.enable {
      name = "sonarr-anime";
      inherit (containers.sonarr-anime) port configPath;
    }
    ++ lib.optional containers.radarr.enable {
      name = "radarr";
      inherit (containers.radarr) port configPath;
    };
  appArgs = lib.escapeShellArgs (lib.concatMap (app: [
      app.name
      "http://127.0.0.1:${toString app.port}"
      "${app.configPath}/config.xml"
    ])
    apps);
  appServices = map (app: "docker-container-${app.name}.service") apps;
in {
  config = lib.mkIf (apps != []) {
    systemd.services.arr-fail-downloads = {
      description = "Enable Fail Downloads on every Sonarr and Radarr indexer";
      after = appServices;
      wants = appServices;
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${lib.getExe enforcer} ${appArgs}";
      };
    };

    systemd.timers.arr-fail-downloads = {
      wantedBy = ["timers.target"];
      timerConfig = {
        OnBootSec = "5min";
        OnUnitActiveSec = "1h";
      };
    };
  };
}
