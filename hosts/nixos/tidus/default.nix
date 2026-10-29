# Tidus - Dell Latitude 7420 laptop with Hyprland
{
  config,
  pkgs,
  lib,
  inputs,
  ...
}: {
  imports = [
    ./hardware-configuration.nix
    inputs.nixos-hardware.nixosModules.dell-latitude-7420
  ];

  # Networking
  modules.nixos.networking.base.hostName = "tidus";

  # Desktop environment
  modules.nixos.desktop.hyprland.enable = true;

  services.logind.settings.Login = {
    HandleLidSwitch = "suspend";
    HandleLidSwitchExternalPower = "ignore";
  };

  # Hardware features
  modules.nixos.hardware = {
    bluetooth.enable = true;
    power.enable = true;
    sound.enable = true;
    graphics.enable = true;
    usbAutomount.enable = true;
  };

  # Storage
  modules.nixos.storage.networkDrives.enable = true;

  # Kernel configuration
  modules.nixos.kernel.type = "zen";

  # Programs
  modules.nixos.programs.nomachine.enable = true;
  modules.nixos.programs.steam.enable = true;

  # Services
  modules.nixos.docker.enable = true;

  # Vesper work (a foreman remote host), as on vincent.
  environment.systemPackages = with pkgs; [
    gcc # cgo: the Vesper site tests build with go
    python3 # the Vesper tests run some tools on the system python3
  ];

  # Vesper's tests and scripts name /bin/bash and /usr/bin/python3. envfs serves /bin and
  # /usr/bin from the caller's PATH, as on a plain Linux host.
  services.envfs.enable = true;

  # Foreman runs host jobs as user units: keep them alive with no login session.
  users.users.danny.linger = true;

  # Stay awake on AC power, so foreman can reach tidus over ssh. A block inhibitor stops every
  # suspend that a user asks for (hypridle, a lid bind, `systemctl suspend`); the screen still
  # dims, locks and turns off (what=sleep only, not idle). On battery the
  # inhibitor is off, and the battery idle rules apply as before. udev starts and stops the
  # unit when the charger state changes; ConditionACPower covers the boot.
  systemd.services.stay-awake-on-ac = {
    description = "Block sleep while tidus is on AC power";
    wantedBy = ["multi-user.target"];
    unitConfig.ConditionACPower = true;
    serviceConfig.ExecStart = "${pkgs.systemd}/bin/systemd-inhibit --what=sleep --who=tidus --why='on AC: stay reachable for foreman work' --mode=block ${pkgs.coreutils}/bin/sleep infinity";
  };
  services.udev.extraRules = ''
    SUBSYSTEM=="power_supply", KERNEL=="AC", ATTR{online}=="1", RUN+="${pkgs.systemd}/bin/systemctl --no-block start stay-awake-on-ac.service"
    SUBSYSTEM=="power_supply", KERNEL=="AC", ATTR{online}=="0", RUN+="${pkgs.systemd}/bin/systemctl --no-block stop stay-awake-on-ac.service"
  '';

  system.stateVersion = "23.11";
}
