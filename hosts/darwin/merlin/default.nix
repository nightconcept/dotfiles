# Merlin - Mac Mini M1 (desktop)
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
