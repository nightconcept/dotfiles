{pkgs, ...}: let
  cleanup = pkgs.writers.writePython3Bin "tv-season-cleanup" {flakeIgnore = ["E501"];} (builtins.readFile ./cleanup.py);
in {
  environment.systemPackages = [cleanup];

  systemd.services.tv-season-cleanup = {
    description = "Remove old seasons of selected TV shows";
    after = ["mnt-titan.mount" "network-online.target" "docker.service"];
    requires = ["mnt-titan.mount"];
    wants = ["network-online.target"];
    serviceConfig = {
      Type = "oneshot";
      User = "danny";
      Group = "users";
      ExecStart = "${cleanup}/bin/tv-season-cleanup ${./shows.json} --apply";
    };
  };

  systemd.timers.tv-season-cleanup = {
    description = "Monthly cleanup of selected TV shows";
    wantedBy = ["timers.target"];
    timerConfig = {
      OnCalendar = "monthly";
      Persistent = true;
    };
  };
}
