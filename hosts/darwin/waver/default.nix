# Waver - MacBook Pro M1 (laptop)
{pkgs, ...}: {
  # Enable Darwin modules for laptop
  modules.darwin = {
    core.enable = true;
    homebrew = {
      enable = true;
      systemType = "laptop";
      extraCasks = [
        "ungoogled-chromium"
        "tailscale-app"
      ];
    };
    systemSettings = {
      enable = true;
      systemType = "laptop";
    };
  };

  # System specific packages
  environment.systemPackages = with pkgs; [
    aldente
  ];
}
