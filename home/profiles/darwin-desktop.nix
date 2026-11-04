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
    colab.enable = true;
    dev-languages.enable = true;
    dev-tools.enable = true;
    ghostty.enable = true;
    herdr.enable = true;
    opencode.enable = true;
    reasonix.enable = true;
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
    (callPackage ../../pkgs/neo-writer/package.nix {})
    karabiner-elements
  ];
}
