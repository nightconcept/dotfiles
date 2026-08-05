{
  config,
  lib,
  pkgs,
  ...
}: let
  moduleLib = import ../../../lib/module {inherit lib;};
  inherit (moduleLib) mkBoolOpt;
in {
  options.modules.home.programs.dev-tools = {
    enable = mkBoolOpt false "Enable developer tools, formatters, and environment managers";
  };

  config = lib.mkIf config.modules.home.programs.dev-tools.enable {
    home.packages = with pkgs; [
      any-nix-shell
      desktop-file-utils
      devenv
      kondo
      nix-prefetch-github
      nixpkgs-review
    ];
  };
}
