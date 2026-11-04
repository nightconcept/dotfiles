# Self-hosted httpSMS: SMS gateway API, web UI, PostgreSQL, and Redis.
#
# The API and web images build on Rinoa from the pinned `httpsms` flake input.
# Both routes are LAN/Tailscale only (secured@file). The gateway phone reaches
# the API on the LAN; other containers use http://httpsms-api:8000 on `proxy`.
#
# Firebase is required: FCM wakes the phone, and the web UI signs in through
# Firebase Auth. See docs/docker.md#httpsms-on-rinoa for the setup steps.
{
  config,
  inputs,
  lib,
  pkgs,
  ...
}: let
  cfg = config.modules.nixos.docker.containers.httpsms;
  containerName = "httpsms";
  containerPath = "/var/lib/docker-containers/${containerName}";
  secretDir = "/run/secrets/services/httpsms";
  secretUnits =
    lib.optionals config.modules.nixos.security.sops.enable ["sops-install-secrets.service"];
  sourceTag = builtins.substring 0 12 (cfg.source.rev or "local");
  webKeys = ["api_key" "auth_domain" "project_id" "storage_bucket" "messaging_sender_id" "app_id"];
  # The API seeds this user for its in-process events queue (README step 7).
  systemUserId = "system-user-id";
in {
  options.modules.nixos.docker.containers.httpsms = {
    enable = lib.mkEnableOption "self-hosted httpSMS gateway";

    source = lib.mkOption {
      type = lib.types.path;
      default = inputs.httpsms;
      description = "Pinned httpSMS source used as the Docker build context";
    };

    localDomain = lib.mkOption {
      type = lib.types.str;
      default = "local.solivan.dev";
      description = "Local base domain for the web UI and API";
    };

    webSubdomain = lib.mkOption {
      type = lib.types.str;
      default = "httpsms";
      description = "Subdomain for the httpSMS web UI";
    };

    apiSubdomain = lib.mkOption {
      type = lib.types.str;
      default = "httpsms-api";
      description = "Subdomain for the httpSMS API (the phone app server URL)";
    };

    dataPath = lib.mkOption {
      type = lib.types.str;
      default = "${containerPath}/data";
      description = "Persistent PostgreSQL data";
    };
  };

  config = lib.mkIf cfg.enable (let
    apiHost = "${cfg.apiSubdomain}.${cfg.localDomain}";
    webHost = "${cfg.webSubdomain}.${cfg.localDomain}";
  in {
    virtualisation.docker.enable = true;

    systemd.tmpfiles.rules = [
      "d ${containerPath} 0700 root root -"
      "d ${cfg.dataPath} 0700 root root -"
    ];

    systemd.services."docker-container-${containerName}" = {
      description = "httpSMS Gateway Containers";
      after = ["docker.service" "docker-network-proxy.service"] ++ secretUnits;
      requires = ["docker.service" "docker-network-proxy.service"] ++ secretUnits;
      wantedBy = ["multi-user.target"];
      restartTriggers = [./docker-compose.yml];
      path = [pkgs.coreutils pkgs.gnugrep pkgs.jq pkgs.docker];

      preStart = ''
        set -euo pipefail
        secret() { cat ${secretDir}/"$1"; }

        for key in db_password system_api_key firebase_credentials ${lib.concatMapStringsSep " " (k: "firebase_web/${k}") webKeys}; do
          if [ ! -r ${secretDir}/"$key" ]; then
            echo "httpSMS secret $key is unavailable" >&2
            exit 1
          fi
          if grep -qx CHANGEME ${secretDir}/"$key"; then
            echo "httpSMS secret $key is still CHANGEME; see docs/docker.md#httpsms-on-rinoa" >&2
            exit 1
          fi
        done
        if ! jq -e '.type == "service_account"' ${secretDir}/firebase_credentials >/dev/null; then
          echo "firebase_credentials is not a Firebase service account JSON" >&2
          exit 1
        fi
        if ! secret system_api_key | grep -Eqx '[A-Za-z0-9_-]{20,}'; then
          echo "system_api_key must be 20+ URL-safe characters" >&2
          exit 1
        fi

        install -d -m 0700 ${cfg.dataPath}/postgres
        install -m 0644 ${./docker-compose.yml} ${containerPath}/docker-compose.yml

        # The web UI is a static Nuxt build: its config is read at build time,
        # so build from a writable copy that holds the .env file.
        webBuild=${containerPath}/web-build
        rm -rf "$webBuild"
        cp -r ${cfg.source}/web "$webBuild"
        chmod -R u+w "$webBuild"
        # Upstream installs dependencies before it copies pnpm-workspace.yaml,
        # so current pnpm rejects the approved build scripts. Copy it first.
        if ! grep -q '^COPY .*pnpm-workspace.yaml' "$webBuild/Dockerfile"; then
          sed -i 's|^COPY package.json pnpm-lock.yaml ./$|COPY package.json pnpm-lock.yaml pnpm-workspace.yaml ./|' "$webBuild/Dockerfile"
          grep -q '^COPY .*pnpm-workspace.yaml' "$webBuild/Dockerfile" || {
            echo "httpSMS web Dockerfile changed; update the pnpm-workspace.yaml patch" >&2
            exit 1
          }
        fi
        umask 077
        {
          printf 'API_BASE_URL=https://%s\n' ${lib.escapeShellArg apiHost}
          printf 'APP_URL=https://%s\n' ${lib.escapeShellArg webHost}
          printf 'APP_NAME=httpSMS\n'
          printf 'APP_ENV=production\n'
          printf 'FIREBASE_API_KEY=%s\n' "$(secret firebase_web/api_key)"
          printf 'FIREBASE_AUTH_DOMAIN=%s\n' "$(secret firebase_web/auth_domain)"
          printf 'FIREBASE_PROJECT_ID=%s\n' "$(secret firebase_web/project_id)"
          printf 'FIREBASE_STORAGE_BUCKET=%s\n' "$(secret firebase_web/storage_bucket)"
          printf 'FIREBASE_MESSAGING_SENDER_ID=%s\n' "$(secret firebase_web/messaging_sender_id)"
          printf 'FIREBASE_APP_ID=%s\n' "$(secret firebase_web/app_id)"
        } > "$webBuild/.env"
        chmod 0644 "$webBuild/.env"
        # A config change gets a new tag, so compose builds a new image.
        webTag="${sourceTag}-$(sha256sum "$webBuild/.env" | cut -c1-12)"

        dbPassword="$(secret db_password)"
        dbUrl="postgresql://httpsms:$dbPassword@postgres:5432/httpsms"
        {
          printf 'ENV=local\n'
          printf 'USE_HTTP_LOGGER=false\n'
          printf 'ENTITLEMENT_ENABLED=false\n'
          printf 'GCP_PROJECT_ID=%s\n' "$(secret firebase_web/project_id)"
          printf 'EVENTS_QUEUE_TYPE=emulator\n'
          printf 'EVENTS_QUEUE_NAME=events-local\n'
          printf 'EVENTS_QUEUE_ENDPOINT=http://127.0.0.1:8000/v1/events\n'
          printf 'EVENTS_QUEUE_USER_ID=${systemUserId}\n'
          printf 'EVENTS_QUEUE_USER_API_KEY=%s\n' "$(secret system_api_key)"
          printf "FIREBASE_CREDENTIALS='%s'\n" "$(jq -c . ${secretDir}/firebase_credentials)"
          printf 'APP_URL=https://%s\n' ${lib.escapeShellArg webHost}
          printf 'APP_NAME=httpSMS\n'
          printf 'APP_PORT=8000\n'
          printf 'SWAGGER_HOST=%s\n' ${lib.escapeShellArg apiHost}
          printf 'DATABASE_URL=%s\n' "$dbUrl"
          printf 'DATABASE_URL_DEDICATED=%s\n' "$dbUrl"
          printf 'REDIS_URL=redis://redis:6379\n'
          # No SMTP: offline-phone emails are not sent. The events admin panel
          # shows a banner for stale texts instead.
          printf 'SMTP_FROM_NAME=httpSMS\n'
          printf 'SMTP_FROM_EMAIL=httpsms@%s\n' ${lib.escapeShellArg cfg.localDomain}
        } > ${containerPath}/api.env

        {
          printf 'DB_PASSWORD=%s\n' "$dbPassword"
          printf 'DATA_PATH=%s\n' ${lib.escapeShellArg cfg.dataPath}
          printf 'SOURCE_PATH=%s\n' ${cfg.source}
          printf 'WEB_BUILD_PATH=%s\n' "$webBuild"
          printf 'API_TAG=%s\n' ${sourceTag}
          printf 'WEB_TAG=%s\n' "$webTag"
          printf 'API_HOST=%s\n' ${lib.escapeShellArg apiHost}
          printf 'WEB_HOST=%s\n' ${lib.escapeShellArg webHost}
        } > ${containerPath}/.env
      '';

      # Seed the system user after the API migrates the schema. The key is
      # checked above, so it is safe to put in SQL.
      postStart = ''
        set -euo pipefail
        key="$(cat ${secretDir}/system_api_key)"
        docker exec httpsms-db psql -v ON_ERROR_STOP=1 -U httpsms -d httpsms -c \
          "INSERT INTO users (id, api_key, email, created_at, updated_at)
           VALUES ('${systemUserId}', '$key', 'system@${cfg.localDomain}', now(), now())
           ON CONFLICT (id) DO UPDATE SET api_key = EXCLUDED.api_key;" >/dev/null
      '';

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        WorkingDirectory = containerPath;
        # The first start builds both images (the web build takes minutes).
        TimeoutStartSec = "30min";
        ExecStart = "${pkgs.docker-compose}/bin/docker-compose up -d --wait --wait-timeout 600";
        ExecStop = "${pkgs.docker-compose}/bin/docker-compose down";
        ExecReload = "${pkgs.docker-compose}/bin/docker-compose restart";
      };
    };
  });
}
