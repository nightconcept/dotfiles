# Artifacts: HTML pages written by agents, hosted by Artifact Share
# (https://forge.solivan.dev/nightconcept/artifact-share, a fork of
# AlexDobrushskiy/artifact-share). One owner; pages are private until made public.
#
# The image builds on Rinoa from the pinned `artifact-share` flake input. Traefik
# routes one name: the LAN name, or the public name when `public` is set, because
# the app needs a single base URL for its sign-in cookie and links. See readme.md.
{
  config,
  inputs,
  lib,
  pkgs,
  ...
}: let
  cfg = config.modules.nixos.docker.containers.artifacts;
  containerName = "artifacts";
  containerPath = "/var/lib/docker-containers/${containerName}";
  host =
    if cfg.public
    then cfg.publicDomain
    else cfg.lanDomain;
  sourceTag = builtins.substring 0 12 (cfg.source.rev or "local");
in {
  options.modules.nixos.docker.containers.artifacts = {
    enable = lib.mkEnableOption "artifact hosting for agent-written HTML pages";

    source = lib.mkOption {
      type = lib.types.path;
      default = inputs.artifact-share;
      description = "Pinned artifact-share source used as the Docker build context";
    };

    lanDomain = lib.mkOption {
      type = lib.types.str;
      default = "artifacts.local.solivan.dev";
      description = "LAN and Tailscale name, routed by Traefik";
    };

    publicDomain = lib.mkOption {
      type = lib.types.str;
      default = "artifacts.solivan.dev";
      description = "Public name, reached through the Cloudflare Tunnel";
    };

    public = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Serve the public name instead of the LAN name. Needs the tunnel hostname in Cloudflare first.";
    };

    dataPath = lib.mkOption {
      type = lib.types.str;
      default = "${containerPath}/data";
      description = "SQLite database: every artifact, revision, comment and publisher key digest";
    };
  };

  config = lib.mkIf cfg.enable {
    virtualisation.docker.enable = true;

    systemd.tmpfiles.rules = [
      "d ${containerPath} 0755 root root -"
      # The image runs as uid 10001 with a read-only root filesystem.
      "d ${cfg.dataPath} 0700 10001 10001 -"
    ];

    systemd.services."docker-container-${containerName}" = {
      description = "Artifact hosting";
      after = ["docker.service" "docker-network-proxy.service"];
      requires = ["docker.service" "docker-network-proxy.service"];
      wantedBy = ["multi-user.target"];
      restartTriggers = [./docker-compose.yml];

      preStart = ''
        install -m 0644 ${./docker-compose.yml} ${containerPath}/docker-compose.yml

        # Quoted heredoc: the rule contains backticks the shell must not run.
        cat > ${containerPath}/.env <<'EOF'
        ARTIFACTS_SOURCE=${cfg.source}
        ARTIFACTS_TAG=${sourceTag}
        ARTIFACTS_BASE_URL=https://${host}
        DATA_PATH=${cfg.dataPath}
        ARTIFACTS_RULE="Host(`${host}`)"
        EOF
      '';

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        WorkingDirectory = containerPath;
        TimeoutStartSec = "15min";
        ExecStart = "${pkgs.docker-compose}/bin/docker-compose up -d --build --wait --wait-timeout 300";
        ExecStop = "${pkgs.docker-compose}/bin/docker-compose down";
      };
    };
  };
}
