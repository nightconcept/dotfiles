# macOS (desktop) specific configuration
{
  config,
  lib,
  pkgs,
  ...
}: {
  imports = [
    ./base.nix
    ../../modules/home
  ];

  modules.home.programs = {
    dev-languages.enable = true;
    dev-tools.enable = true;
    ghostty.enable = true;
    herdr.enable = true;
    zotero.enable = true;
    shell = {
      fish.enable = true;
      starship.enable = true;
      zoxide.enable = true;
    };
  };

  fonts.fontconfig.enable = true;

  home.sessionVariables = {
    VFLAGS = "-cc clang";
  };

  home.packages = with pkgs; [
    karabiner-elements
  ];
}
