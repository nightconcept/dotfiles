# Forgejo Runner Container Module
# Manages Forgejo Actions runners in Docker containers with privileged mode for ISO building
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.modules.nixos.docker.containers.forgejo-runner;
  containerName = "forgejo-runners";
  containerPath = "/var/lib/docker-containers/${containerName}";
in {
  options.modules.nixos.docker.containers.forgejo-runner = {
    enable = lib.mkEnableOption "Forgejo Actions runners";

    image = lib.mkOption {
      type = lib.types.str;
      default = "code.forgejo.org/forgejo/runner:11";
      description = "Docker image to use for Forgejo runners";
    };

    replicas = lib.mkOption {
      type = lib.types.int;
      default = 3;
      description = "Number of concurrent Forgejo runners";
    };

    instanceUrl = lib.mkOption {
      type = lib.types.str;
      default = "https://forge.solivan.dev";
      description = "URL of your Forgejo instance";
      example = "https://forge.solivan.dev";
    };

    runnerName = lib.mkOption {
      type = lib.types.str;
      default = "${config.networking.hostName}-runner";
      description = "Base name for the Forgejo runners";
    };

    labels = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = ["ubuntu-latest:docker://ubuntu:22.04" "docker:host" "linux" "amd64"];
      description = "Labels for the Forgejo runners";
    };

    tokenFile = lib.mkOption {
      type = lib.types.path;
      default = "/run/secrets/forgejo_runner_token";
      description = "Path to file containing Forgejo registration token";
    };

    environment = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = {};
      description = "Additional environment variables for runners";
    };

    enablePrivileged = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable privileged mode for containers (required for ISO building with mkarchiso)";
    };
  };

  config = lib.mkIf cfg.enable {
    # Ensure Docker is enabled
    virtualisation.docker.enable = true;

    # Create required directories with proper permissions
    systemd.tmpfiles.rules = [
      "d ${containerPath} 0755 root root -"
    ];

    # Forgejo Runners Service
    systemd.services."docker-container-${containerName}" = {
      description = "Forgejo Actions Runners";
      after = ["docker.service" "network.target"];
      requires = ["docker.service"];
      wantedBy = ["multi-user.target"];

      preStart = ''
        # Generate config.yml with privileged mode enabled
        mkdir -p ${containerPath}/config
        cat > ${containerPath}/config/config.yml <<'EOF'
        log:
          level: info

        runner:
          file: .runner
          capacity: 1
          timeout: 3h
          insecure: false
          fetch_timeout: 5s
          fetch_interval: 2s
          labels: []

        cache:
          enabled: true
          dir: ""
          host: ""
          port: 0
          external_server: ""

        container:
          network: ""
          privileged: ${
          if cfg.enablePrivileged
          then "true"
          else "false"
        }
          options: ""
          workdir_parent: ""
          valid_volumes: []
          docker_host: ""
          force_pull: true

        host:
          workdir_parent: ""
        EOF

        # Generate docker-compose.yml
        cat > ${containerPath}/docker-compose.yml <<'EOF'
        services:
          docker-in-docker:
            image: docker:dind
            container_name: forgejo-dind
            privileged: true
            command: ['dockerd', '-H', 'tcp://0.0.0.0:2375', '--tls=false']
            restart: unless-stopped
            healthcheck:
              test: ['CMD', 'docker', '--host', 'tcp://127.0.0.1:2375', 'info']
              interval: 30s
              timeout: 10s
              retries: 3
              start_period: 30s
            networks:
              - runner-network

        ${lib.concatStringsSep "\n" (lib.genList (i: let
            runnerNum = i + 1;
          in ''
              forgejo-runner-${toString runnerNum}:
                image: ${cfg.image}
                container_name: forgejo-runner-${toString runnerNum}
                restart: unless-stopped
                depends_on:
                  - docker-in-docker
                environment:
                  DOCKER_HOST: 'tcp://docker-in-docker:2375'
                  FORGEJO_INSTANCE_URL: '${cfg.instanceUrl}'
                  FORGEJO_RUNNER_NAME: '${cfg.runnerName}-${toString runnerNum}'
                  FORGEJO_RUNNER_LABELS: '${lib.concatStringsSep "," cfg.labels}'
            ${lib.concatStringsSep "\n" (lib.mapAttrsToList (name: value: "      ${name}: '${value}'") cfg.environment)}
                env_file:
                  - ${containerPath}/.env
                volumes:
                  - forgejo-runner-data-${toString runnerNum}:/data
                  - ${containerPath}/config/config.yml:/data/config.yml:ro
                networks:
                  - runner-network
                user: "0:0"
                command:
                  - sh
                  - -c
                  - |
                    cd /data
                    if [ ! -f .runner ]; then
                      sleep 5
                      echo "Registering runner: ${cfg.runnerName}-${toString runnerNum}"
                      forgejo-runner register --no-interactive \
                        --instance "${cfg.instanceUrl}" \
                        --token "''${FORGEJO_RUNNER_REGISTRATION_TOKEN}" \
                        --name "${cfg.runnerName}-${toString runnerNum}" \
                        --labels "${lib.concatStringsSep "," cfg.labels}"
                    fi
                    forgejo-runner daemon --config /data/config.yml
          '')
          cfg.replicas)}

        volumes:
        ${lib.concatStringsSep "\n" (lib.genList (i: "  forgejo-runner-data-${toString (i + 1)}:") cfg.replicas)}

        networks:
          runner-network:
            driver: bridge
        EOF

        # Generate .env file with registration token
        echo "FORGEJO_RUNNER_REGISTRATION_TOKEN=$(cat ${cfg.tokenFile})" > ${containerPath}/.env
      '';

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        WorkingDirectory = containerPath;
        ExecStart = "${pkgs.docker-compose}/bin/docker-compose up -d --wait --wait-timeout 180";
        ExecStop = "${pkgs.docker-compose}/bin/docker-compose down";
        Restart = "on-failure";
      };
    };
  };
}
