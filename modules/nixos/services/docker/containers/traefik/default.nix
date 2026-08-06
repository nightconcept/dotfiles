# Traefik Reverse Proxy Container Module
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.modules.nixos.docker.containers.traefik;
  containerName = "traefik";
  containerPath = "/var/lib/docker-containers/${containerName}";
in {
  options.modules.nixos.docker.containers.traefik = {
    enable = lib.mkEnableOption "Traefik reverse proxy container";

    domain = lib.mkOption {
      type = lib.types.str;
      default = "local.solivan.dev";
      description = "Base domain for Traefik";
    };

    dashboard = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable Traefik dashboard";
      };

      subdomain = lib.mkOption {
        type = lib.types.str;
        default = "traefik-dashboard";
        description = "Subdomain for Traefik dashboard";
      };
    };

    configPath = lib.mkOption {
      type = lib.types.str;
      default = "${containerPath}/config";
      description = "Path to Traefik configuration files";
    };

    ports = {
      http = lib.mkOption {
        type = lib.types.int;
        default = 80;
        description = "HTTP port";
      };

      https = lib.mkOption {
        type = lib.types.int;
        default = 443;
        description = "HTTPS port";
      };
    };

    cloudflareTokenFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default =
        if config.modules.nixos.security.sops.enable
        then "/run/secrets/services/traefik/cloudflare_token"
        else null;
      description = "Path to file containing Cloudflare DNS API token";
      example = "/run/secrets/cloudflare-dns-token";
    };

    dokployIntegration = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable routing to Dokploy instance on Vincent";
      };

      host = lib.mkOption {
        type = lib.types.str;
        default = "vincent.local";
        description = "Hostname of the Dokploy server";
      };

      dashboardSubdomain = lib.mkOption {
        type = lib.types.str;
        default = "dokploy";
        description = "Subdomain for Dokploy dashboard";
      };

      appsSubdomain = lib.mkOption {
        type = lib.types.str;
        default = "apps";
        description = "Base subdomain for Dokploy-deployed applications (*.apps.domain)";
      };

      ports = {
        dashboard = lib.mkOption {
          type = lib.types.int;
          default = 3000;
          description = "Dokploy dashboard port";
        };

        traefik = lib.mkOption {
          type = lib.types.int;
          default = 8443;
          description = "Dokploy's Traefik HTTPS port";
        };
      };
    };
  };

  config = lib.mkIf cfg.enable {
    # Ensure Docker is enabled
    virtualisation.docker.enable = true;

    # Create required directories
    systemd.tmpfiles.rules = [
      "d ${containerPath} 0755 root root -"
      "d ${cfg.configPath} 0755 root root -"
      "d ${containerPath}/logs 0755 root root -"
    ];

    # Traefik container service
    systemd.services."docker-container-${containerName}" = {
      description = "Traefik Reverse Proxy Container";
      after = ["docker.service" "docker-network-proxy.service"];
      requires = ["docker.service" "docker-network-proxy.service"];
      wantedBy = ["multi-user.target"];

      preStart = ''
        # Copy docker-compose.yml to runtime directory
        cp ${./docker-compose.yml} ${containerPath}/docker-compose.yml

        # Generate .env file
        cat > ${containerPath}/.env <<EOF
        ${lib.optionalString (cfg.cloudflareTokenFile != null) ''
          CLOUDFLARE_DNS_API_TOKEN=$(cat ${cfg.cloudflareTokenFile})
        ''}
        CONFIG_PATH=${cfg.configPath}
        DOMAIN=${cfg.domain}
        DASHBOARD_SUBDOMAIN=${cfg.dashboard.subdomain}
        EOF

        # Always copy traefik.yml from module to ensure updates are applied
        ${lib.optionalString (builtins.pathExists ./config/traefik.yml) ''
          cp -f ${./config/traefik.yml} ${cfg.configPath}/traefik.yml
        ''}
        ${lib.optionalString (builtins.pathExists ./config/config.yml) ''
          cp -f ${./config/config.yml} ${cfg.configPath}/config.yml
        ''}

        # Generate Dokploy routing configuration if enabled
        ${lib.optionalString cfg.dokployIntegration.enable ''
            cat > ${cfg.configPath}/dokploy-routing.yml <<'DOKPLOY_CONFIG'
          # Dokploy routing configuration - auto-generated
          http:
            services:
              # Dokploy dashboard service
              dokploy-dashboard:
                loadBalancer:
                  servers:
                    - url: "http://${cfg.dokployIntegration.host}:${toString cfg.dokployIntegration.ports.dashboard}"

              # Dokploy Traefik service (for deployed applications)
              dokploy-apps:
                loadBalancer:
                  servers:
                    - url: "https://${cfg.dokployIntegration.host}:${toString cfg.dokployIntegration.ports.traefik}"
                  serversTransport: dokploy-transport

            routers:
              # Route for Dokploy dashboard
              dokploy-dashboard:
                rule: "Host(\`${cfg.dokployIntegration.dashboardSubdomain}.${cfg.domain}\`)"
                entryPoints:
                  - https
                service: dokploy-dashboard
                tls:
                  certResolver: cloudflare

              # Wildcard route for all Dokploy-deployed applications
              dokploy-apps:
                rule: "HostRegexp(\`{subdomain:[a-z0-9-]+}.${cfg.dokployIntegration.appsSubdomain}.${cfg.domain}\`)"
                entryPoints:
                  - https
                service: dokploy-apps
                tls:
                  certResolver: cloudflare
                  domains:
                    - main: "*.${cfg.dokployIntegration.appsSubdomain}.${cfg.domain}"

            serversTransports:
              # Transport configuration for Dokploy's Traefik
              dokploy-transport:
                insecureSkipVerify: true  # Skip cert verification for internal traffic
                maxIdleConnsPerHost: 10
          DOKPLOY_CONFIG
        ''}

        # Ensure acme.json exists with correct permissions
        touch ${cfg.configPath}/acme.json
        chmod 600 ${cfg.configPath}/acme.json

        # Create basic traefik.yml if it doesn't exist
        if [ ! -f ${cfg.configPath}/traefik.yml ]; then
          cat > ${cfg.configPath}/traefik.yml <<'TRAEFIK_CONFIG'
        api:
          dashboard: ${toString cfg.dashboard.enable}
          debug: false

        entryPoints:
          http:
            address: ":80"
            http:
              redirections:
                entrypoint:
                  to: https
                  scheme: https
          https:
            address: ":443"

        providers:
          docker:
            endpoint: "unix:///var/run/docker.sock"
            exposedByDefault: false
            network: proxy
          file:
            filename: /config.yml
            watch: true

        certificatesResolvers:
          cloudflare:
            acme:
              email: admin@${cfg.domain}
              storage: /acme.json
              dnsChallenge:
                provider: cloudflare
                resolvers:
                  - "1.1.1.1:53"
                  - "1.0.0.1:53"

        log:
          level: INFO
          filePath: /var/log/traefik/traefik.log

        accessLog:
          filePath: /var/log/traefik/access.log
        TRAEFIK_CONFIG
        fi

        # Create basic config.yml if it doesn't exist
        if [ ! -f ${cfg.configPath}/config.yml ]; then
          cat > ${cfg.configPath}/config.yml <<'DYNAMIC_CONFIG'
        http:
          middlewares:
            default-headers:
              headers:
                frameDeny: true
                browserXssFilter: true
                contentTypeNosniff: true
                forceSTSHeader: true
                stsIncludeSubdomains: true
                stsPreload: true
                stsSeconds: 15552000
                customFrameOptionsValue: SAMEORIGIN
        DYNAMIC_CONFIG
        fi
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

    # Open firewall ports
    networking.firewall.allowedTCPPorts = [cfg.ports.http cfg.ports.https];
  };
}
