{
  config,
  lib,
  pkgs,
  ...
}: let
  moduleLib = import ../../../lib/module {inherit lib;};
  inherit (moduleLib) mkBoolOpt;
  miseBin = pkgs.callPackage ../../../pkgs/mise/package.nix {};
in {
  options.modules.home.programs.dev-languages = {
    enable = mkBoolOpt false "Enable developer programming languages and runtimes (excluding Python/uv)";
  };

  config = lib.mkIf config.modules.home.programs.dev-languages.enable {
    home.packages = with pkgs; [
      beamPackages.erlang
      gleam
      lua51Packages.lua
      miseBin
      nodejs_24
      vlang
    ];
  };
}
