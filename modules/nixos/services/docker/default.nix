{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.modules.nixos.docker;
in {
  imports = [
    ./health-check.nix

    # Core infrastructure
    ./containers/traefik
    ./containers/portainer
    ./containers/watchtower
    ./containers/crowdsec

    # CI/CD runners
    ./containers/forgejo-runner

    # Media services
    ./containers/jellyfin
    ./containers/libbyrip-converter

    # *arr stack
    ./containers/prowlarr
    ./containers/radarr
    ./containers/sonarr

    ./containers/audiobookshelf

    # Add other containers as default.nix files are created

    ./containers/cloudflare-tunnel
    ./containers/ddclient
    # ./containers/enshrouded
    ./containers/flaresolverr
    ./containers/forgejo
    ./containers/freshrss
    ./containers/headscale
    ./containers/homepage
    ./containers/immich
    # ./containers/minecraft
    ./containers/nextcloud
    ./containers/opengist
    ./containers/seerr
    # ./containers/open-webui
    # ./containers/palworld
    ./containers/prowlarr-abb
    # ./containers/readarr
    # ./containers/readarr-books
    # ./containers/searxng
    ./containers/uptime-kuma
    ./containers/vaultwarden
    # ./containers/wg-easy
    ./containers/zotero-webdav
  ];

  options.modules.nixos.docker = {
    enable = lib.mkEnableOption "Docker container runtime";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.docker;
      defaultText = lib.literalExpression "pkgs.docker";
      description = "The Docker package to use";
    };

    composePackage = lib.mkOption {
      type = lib.types.package;
      default = pkgs.docker-compose;
      defaultText = lib.literalExpression "pkgs.docker-compose";
      description = "The docker-compose package to use";
    };

    dockerComposeProjects = lib.mkOption {
      type = lib.types.attrs;
      default = {};
      description = "Docker Compose projects to manage";
    };

    swarm = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable Docker Swarm mode (disables live-restore)";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    virtualisation.docker = {
      enable = true;
      package = cfg.package;
      enableOnBoot = true;
      autoPrune = {
        enable = true;
        dates = "weekly";
        flags = ["--all"];
      };
      # Swarm mode requires live-restore to be disabled
      daemon.settings = lib.mkIf cfg.swarm.enable {
        live-restore = false;
      };
    };

    users.users.danny.extraGroups = ["docker"];

    environment.systemPackages = [
      cfg.composePackage
      pkgs.lazydocker
      pkgs.yq # For manipulating docker-compose.yml files
    ];

    # Create base directories
    systemd.tmpfiles.rules = [
      "d /var/lib/docker-containers 0755 root root -"
    ];

    # Create proxy network for containers
    systemd.services.docker-network-proxy = {
      description = "Create Docker proxy network";
      after = ["docker.service"];
      requires = ["docker.service"];
      wantedBy = ["multi-user.target"];
      script = ''
        ${pkgs.docker}/bin/docker network ls | grep -q proxy || \
        ${pkgs.docker}/bin/docker network create proxy
      '';
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
    };
  };
}
