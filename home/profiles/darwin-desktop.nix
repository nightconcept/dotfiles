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
    # Zotero 10.0.4 bundles Firefox ESR 140, now EOL and marked insecure. Re-enable once Zotero moves to ESR 153.
    zotero.enable = false;
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
