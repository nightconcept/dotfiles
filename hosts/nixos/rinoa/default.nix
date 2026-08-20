# Rinoa - Server configuration
{
  config,
  pkgs,
  lib,
  inputs,
  ...
}: {
  imports = [
    ./hardware-configuration.nix
  ];

  # Bootloader configuration (override any systemd-boot settings)
  boot.loader = {
    systemd-boot.enable = lib.mkForce false;
    efi.canTouchEfiVariables = lib.mkForce false;
    grub = {
      enable = true;
      device = "/dev/sda";
    };
  };

  # Swap configuration - 8GB swap file
  swapDevices = [
    {
      device = "/swapfile";
      size = 8192; # 8GB in MB
    }
  ];

  # Networking
  modules.nixos.networking.base.hostName = "rinoa";

  # Standard NixOS modules
  modules.nixos = {
    kernel.type = "lts";

    network = {
      networkManager = true;
      mdns = true;
    };

    # Enable SOPS for secret management
    security.sops.enable = true;

    # Enable titan network drive mount
    storage.networkDrives = {
      enable = true;
      enableTitan = true;
      # Disable automount timeout to prevent services from stopping
      # Sonarr and Radarr require this mount, and the 60s timeout causes them to stop
      titanIdleTimeout = 0;
    };
  };

  # Enable Docker
  modules.nixos.docker.enable = true;

  # Compose returning successfully only proves that Docker accepted the start
  # request. This gate verifies the resulting container and application state.
  modules.nixos.docker.healthCheck = {
    enable = true;
    listenAddress = "192.168.1.110";
    expectedContainers = [
      "traefik"
      "crowdsec"
      "crowdsec-bouncer-traefik"
      "ddclient"
      "portainer"
      "flaresolverr"
      "cloudflare-tunnel"
      "vaultwarden"
      "prowlarr-abb"
      "prowlarr"
      "sonarr"
      "radarr"
      "jellyfin"
      "audiobookshelf"
      "libbyrip-converter"
      "forgejo-db"
      "forgejo"
      "zotero-webdav"
      "opengist"
      "headscale"
    ];
    mounts = ["/mnt/titan"];
    httpChecks = [
      {
        name = "Portainer direct";
        url = "http://127.0.0.1:9000/api/status";
      }
      {
        name = "Flaresolverr direct";
        url = "http://127.0.0.1:8191/";
      }
      {
        name = "Prowlarr direct";
        url = "http://127.0.0.1:9696/ping";
      }
      {
        name = "Prowlarr ABB direct";
        url = "http://127.0.0.1:9697/ping";
      }
      {
        name = "Sonarr direct";
        url = "http://127.0.0.1:8989/ping";
      }
      {
        name = "Radarr direct";
        url = "http://127.0.0.1:7878/ping";
      }
      {
        name = "Jellyfin direct";
        url = "http://127.0.0.1:8096/health";
      }
      {
        name = "Forgejo routed";
        url = "https://forge.local.solivan.dev/api/healthz";
      }
      {
        name = "Vaultwarden routed";
        url = "https://vaultwarden.local.solivan.dev/alive";
      }
      {
        name = "Audiobookshelf routed";
        url = "https://audiobookshelf.local.solivan.dev/healthcheck";
      }
      {
        name = "Zotero WebDAV routed";
        url = "https://zotero.local.solivan.dev/";
        acceptedStatusCodes = ["200" "401"];
      }
      {
        name = "OpenGist routed";
        url = "https://gist.local.solivan.dev/";
      }
      {
        name = "Actual Budget routed";
        url = "https://budget.local.solivan.dev/";
      }
      {
        name = "Paisa Ledger routed";
        url = "https://ledger.local.solivan.dev/";
      }
    ];
    afterUnits = [
      "docker-container-traefik.service"
      "docker-container-crowdsec.service"
      "docker-container-ddclient.service"
      "docker-container-portainer.service"
      "docker-container-flaresolverr.service"
      "docker-container-cloudflare-tunnel.service"
      "docker-container-vaultwarden.service"
      "docker-container-prowlarr-abb.service"
      "docker-container-prowlarr.service"
      "docker-container-sonarr.service"
      "docker-container-radarr.service"
      "docker-container-jellyfin.service"
      "docker-container-audiobookshelf.service"
      "docker-container-libbyrip-converter.service"
      "docker-container-forgejo.service"
      "docker-container-zotero-webdav.service"
      "docker-container-opengist.service"
    ];
  };

  # Enable Docker containers
  modules.nixos.docker.containers = {
    traefik = {
      enable = true;
      domain = "local.solivan.dev";
      dashboard.enable = true;
      # cloudflareTokenFile automatically uses SOPS when sops.enable = true
    };
    crowdsec = {
      enable = true;
      domain = "local.solivan.dev";
      subdomain = "crowdsec";
    };
    ddclient.enable = true;
    portainer.enable = true;
    watchtower.enable = false;
    flaresolverr.enable = true;
    cloudflare-tunnel.enable = true;
    vaultwarden.enable = true;
    prowlarr-abb.enable = true;
    prowlarr.enable = true;
    sonarr.enable = true;
    radarr.enable = true;
    jellyfin.enable = true;
    audiobookshelf.enable = true;
    libbyrip-converter.enable = true;
    nextcloud.enable = false;
    forgejo = {
      enable = true;
      signingKey = "1C5E44D950920340"; # Your GPG key ID
      signingName = "Danny Solivan";
      signingEmail = "dark@nightconcept.net";
    };
    zotero-webdav.enable = true;
    opengist.enable = true;
    headscale.enable = true;
  };

  # System packages for server management
  environment.systemPackages = with pkgs; [
    home-manager
  ];

  system.stateVersion = "24.05";
}
