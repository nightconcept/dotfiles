# Nightly flake.lock updater: builds every gated output against the newest nixos-unstable and
# pushes the lock to main when all of them pass. Policy and runbook: docs/yuffie.md.
{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.modules.nixos.services.flakeUpdater;
  stateDir = "/var/lib/flake-updater";

  updater = pkgs.writeShellApplication {
    name = "flake-updater";
    runtimeInputs = [pkgs.python3 pkgs.git pkgs.openssh config.nix.package];
    text = ''exec python3 ${./flake_updater.py} "$@"'';
  };
  args = concatStringsSep " " ([
      "--state-dir ${stateDir}"
      "--repo-url ${cfg.repoUrl}"
      "--branch ${cfg.branch}"
      "--cooldown-days ${toString cfg.cooldownDays}"
      "--max-attempts ${toString cfg.maxAttempts}"
      "--alert-after ${toString cfg.alertAfter}"
      "--gotify-url ${cfg.gotifyUrl}"
      "--gotify-token-file ${cfg.gotifyTokenFile}"
    ]
    ++ optional (cfg.darwinHosts != []) "--darwin-hosts ${concatStringsSep " " cfg.darwinHosts}"
    ++ optional (cfg.homeProfiles != []) "--home-profiles ${concatStringsSep " " cfg.homeProfiles}");

  unit = description: extraArgs: {
    inherit description;
    after = ["network-online.target"];
    wants = ["network-online.target"];
    environment = {
      GIT_SSH_COMMAND = concatStringsSep " " [
        "ssh -i ${cfg.sshKeyFile} -o IdentitiesOnly=yes"
        "-o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=${stateDir}/known_hosts"
      ];
      XDG_CACHE_HOME = "${stateDir}/cache";
    };
    serviceConfig = {
      Type = "oneshot";
      User = "flake-updater";
      Group = "flake-updater";
      StateDirectory = "flake-updater";
      # Stop before the next night's run.
      TimeoutStartSec = "23h";
      ExecStart = "${updater}/bin/flake-updater ${args}${extraArgs}";
    };
  };
in {
  options.modules.nixos.services.flakeUpdater = {
    enable = mkEnableOption "nightly flake.lock update, build gate and push";

    repoUrl = mkOption {
      type = types.str;
      default = "ssh://git@192.168.1.110:2222/nightconcept/dotfiles.git";
      description = "Repository to update. Forgejo on rinoa mirrors main to GitHub.";
    };

    branch = mkOption {
      type = types.str;
      default = "main";
      description = "Branch that receives the flake.lock commit.";
    };

    schedule = mkOption {
      type = types.str;
      default = "*-*-* 00:00:00";
      description = "systemd OnCalendar time for the nightly run. A missed run is not caught up.";
    };

    cooldownDays = mkOption {
      type = types.int;
      default = 7;
      description = "Days to wait after a push before the next update.";
    };

    maxAttempts = mkOption {
      type = types.int;
      default = 2;
      description = "Failed runs on one nixpkgs revision before waiting for a newer one.";
    };

    alertAfter = mkOption {
      type = types.int;
      default = 3;
      description = "Consecutive failed runs before each failure sends a Gotify alert.";
    };

    darwinHosts = mkOption {
      type = types.listOf types.str;
      default = ["waver" "merlin"];
      description = "Darwin configurations to evaluate. Linux cannot build them.";
    };

    homeProfiles = mkOption {
      type = types.listOf types.str;
      default = ["desktop" "laptop" "server"];
      description = "Standalone home-manager configurations to build.";
    };

    sshKeyFile = mkOption {
      type = types.str;
      description = "Private SSH key of a Forgejo deploy key with write access.";
    };

    gotifyUrl = mkOption {
      type = types.str;
      default = "http://192.168.1.185:8070";
      description = "Gotify server on vincent.";
    };

    gotifyTokenFile = mkOption {
      type = types.str;
      default = "${stateDir}/gotify.token";
      description = "Token of the flake-updater Gotify application. Without it, alerts are only logged.";
    };
  };

  config = mkIf cfg.enable {
    users.users.flake-updater = {
      isSystemUser = true;
      group = "flake-updater";
      home = stateDir;
    };
    users.groups.flake-updater = {};

    systemd.services = {
      flake-updater = unit "Update flake.lock, build the gate and push" "";
      # Manual validation: systemctl start flake-updater-dry-run (no timer).
      flake-updater-dry-run = unit "Update flake.lock and build the gate without pushing" " --no-push";
    };

    systemd.timers.flake-updater = {
      wantedBy = ["timers.target"];
      timerConfig = {
        OnCalendar = cfg.schedule;
        # A missed midnight run waits for the next night, so it never builds in the daytime.
        Persistent = false;
      };
    };
  };
}
