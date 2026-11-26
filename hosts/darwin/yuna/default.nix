# Yuna - Mac Mini M1 (desktop, same settings as merlin)
{pkgs, ...}: {
  # Enable Darwin modules for desktop
  modules.darwin = {
    core.enable = true;
    homebrew = {
      enable = true;
      systemType = "desktop";
      extraCasks = [
        "ungoogled-chromium"
      ];
    };
    systemSettings = {
      enable = true;
      systemType = "desktop";
    };
  };
}
