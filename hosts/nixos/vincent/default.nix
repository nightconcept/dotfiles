# Vincent - CI/CD Runner Host
# Purpose: Container orchestration for GitHub and Forgejo runners
{
  config,
  pkgs,
  lib,
  inputs,
  ...
}: let
  ping = name: hostname: {
    inherit name hostname;
    type = "ping";
    description = "Direct infrastructure reachability; independent of Traefik and Cloudflare.";
  };
  port = name: hostname: servicePort: {
    inherit name hostname;
    type = "port";
    port = servicePort;
    description = "Direct LAN TCP service check; independent of Cloudflare.";
  };
  http = name: url: {
    inherit name url;
    type = "http";
  };
in {
  imports = [
    ./hardware-configuration.nix
  ];

  # Networking
  modules.nixos.networking.base.hostName = "vincent";

  # Bootloader configuration (override systemd-boot for BIOS/MBR systems)
  modules.nixos.core.bootloader.enable = false;
  boot.loader = {
    systemd-boot.enable = false;
    efi.canTouchEfiVariables = false;
    grub = {
      enable = true;
      device = "/dev/sda"; # Update this to match your actual disk
    };
  };

  # Standard NixOS modules
  modules.nixos = {
    kernel.type = "lts";

    network = {
      networkManager = true;
      mdns = true;
    };

    # Enable SOPS for secrets management
    security.sops.enable = true;
  };

  # System packages for server management
  environment.systemPackages = with pkgs; [
    home-manager
  ];

  # Enable Docker
  modules.nixos.docker.enable = true;

  modules.nixos.docker.healthCheck = {
    enable = true;
    listenAddress = "192.168.1.185";
    expectedContainers = [
      "forgejo-dind"
      "forgejo-runner-1"
      "forgejo-runner-2"
      "forgejo-runner-3"
      "portainer"
      "uptimekuma"
    ];
    httpChecks = [
      {
        name = "Portainer direct";
        url = "http://127.0.0.1:9000/api/status";
      }
      {
        name = "Uptime Kuma direct";
        url = "http://192.168.1.185:3001/";
      }
    ];
    afterUnits = [
      "docker-container-forgejo-runners.service"
      "docker-container-portainer.service"
      "docker-container-uptimekuma.service"
    ];
  };

  # Forgejo Runners
  modules.nixos.docker.containers.forgejo-runner = {
    enable = true;
    replicas = 3;
    labels = ["docker" "amd64" "linux" "vincent" "ubuntu-latest:docker://ghcr.io/catthehacker/ubuntu:act-22.04"];
  };

  # Additional container management
  modules.nixos.docker.containers = {
    # Container management
    portainer = {
      enable = true;
      port = 9000;
    };

    # Auto-update containers (optional)
    watchtower = {
      enable = false; # Disabled by default for CI runners
      schedule = "0 0 4 * * *";
    };

    uptime-kuma = {
      enable = true;
      listenAddress = "192.168.1.185";
      monitors = [
        # Host and network reachability. These use direct addresses so a DNS,
        # reverse-proxy, or Cloudflare incident does not collapse every signal.
        (ping "Router" "192.168.1.1")
        (ping "Pi-hole" "192.168.1.101")
        (ping "Rinoa" "192.168.1.110")
        (ping "Terra" "192.168.1.111")
        (ping "Barrett" "192.168.1.114")
        (ping "Aerith" "192.168.1.118")
        (ping "Valefor" "192.168.1.119")
        (ping "Mog" "192.168.1.167")
        (ping "Locke" "192.168.1.188")
        (ping "Vincent" "192.168.1.185")

        (port "Pi-hole DNS" "192.168.1.101" 53)
        (port "Rinoa SSH" "192.168.1.110" 22)
        (port "Terra SSH" "192.168.1.111" 22)
        (port "Barrett SSH" "192.168.1.114" 22)
        (port "Aerith SSH" "192.168.1.118" 22)
        (port "Valefor Proxmox" "192.168.1.119" 8006)
        (port "Mog SMB" "192.168.1.167" 445)
        (port "Locke Proxmox" "192.168.1.188" 8006)
        (port "Plex direct" "192.168.1.118" 32400)
        (port "qBittorrent direct" "192.168.1.114" 8112)

        (http "Pi-hole direct" "http://192.168.1.101:8089/admin/")
        ((http "Plex HTTP direct" "http://192.168.1.118:32400/")
          // {
            accepted_statuscodes = ["200-399" "401"];
          })
        (http "qBittorrent HTTP direct" "http://192.168.1.114:8112/")
        ((http "Terra Calibre direct" "http://192.168.1.111:8085/")
          // {
            accepted_statuscodes = ["200-399" "401"];
          })
        (http "Terra Calibre Web direct" "http://192.168.1.111:8083/")
        ((http "Terra Paseo direct" "http://192.168.1.111:6767/")
          // {
            accepted_statuscodes = ["200-399" "401" "403"];
          })
        (http "Terra model API direct" "http://192.168.1.111:8080/v1/models")

        # Host-local aggregators inspect expected containers, Docker health,
        # application endpoints, and required mounts on their own host.
        (http "Rinoa container readiness" "http://192.168.1.110:3002/health")
        (http "Vincent container readiness" "http://192.168.1.185:3002/health")
        (http "Uptime Kuma direct" "http://192.168.1.185:3001/")

        # User-facing LAN paths validate local DNS, TLS, Traefik, and the app.
        (http "Traefik dashboard" "https://traefik-dashboard.local.solivan.dev/")
        (http "Portainer" "https://portainer.local.solivan.dev/")
        (http "Vaultwarden LAN" "https://vaultwarden.local.solivan.dev/alive")
        (http "Prowlarr" "https://prowlarr.local.solivan.dev/ping")
        (http "Prowlarr ABB" "https://prowlarr-abb.local.solivan.dev/ping")
        (http "Sonarr" "https://sonarr.local.solivan.dev/ping")
        (http "Radarr" "https://radarr.local.solivan.dev/ping")
        (http "Jellyfin LAN" "https://jellyfin.local.solivan.dev/health")
        (http "Audiobookshelf LAN" "https://audiobookshelf.local.solivan.dev/healthcheck")
        (http "Forgejo LAN" "https://forge.local.solivan.dev/api/healthz")
        ((http "Zotero WebDAV LAN" "https://zotero.local.solivan.dev/") // {accepted_statuscodes = ["200" "401"];})
        (http "OpenGist LAN" "https://gist.local.solivan.dev/")
        ((http "Plex routed" "https://plex.local.solivan.dev/") // {accepted_statuscodes = ["200-399" "401"];})
        (http "Pi-hole routed" "https://pihole.local.solivan.dev/admin/")
        (http "qBittorrent routed" "https://qbittorrent.local.solivan.dev/")
        ((http "Calibre" "https://calibre.local.solivan.dev/") // {accepted_statuscodes = ["200-399" "401"];})
        (http "Calibre Web" "https://books.local.solivan.dev/")
        (http "Libby converter" "https://converter.local.solivan.dev/")
        (http "Valefor routed" "https://valefor.local.solivan.dev/")
        (http "Locke routed" "https://locke.local.solivan.dev/")
        (http "Mog routed" "https://mog.local.solivan.dev/")
        (http "Router routed" "https://router.local.solivan.dev/")

        # These intentionally include public DNS, Cloudflare, the tunnel,
        # Traefik, TLS, and the application. They are not substitutes for the
        # direct checks above.
        (http "Forgejo public" "https://forge.solivan.dev/api/healthz")
        (http "Vaultwarden public" "https://vaultwarden.solivan.dev/alive")
        (http "Jellyfin public" "https://jellyfin.solivan.dev/health")
        (http "Audiobookshelf public" "https://audiobookshelf.solivan.dev/healthcheck")
        ((http "Zotero WebDAV public" "https://zotero.solivan.dev/") // {accepted_statuscodes = ["200" "401"];})
        (http "OpenGist public" "https://gist.solivan.dev/")
      ];
    };
  };

  # System state version
  system.stateVersion = "24.11";
}
