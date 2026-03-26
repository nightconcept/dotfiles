{
  config,
  lib,
  pkgs,
  ...
}: let
  moduleLib = import ../../../lib/module {inherit lib;};
  inherit (moduleLib) mkBoolOpt;
in {
  options.modules.home.programs.zotero = {
    enable = mkBoolOpt false "Enable Zotero reference manager";
  };

  config = lib.mkIf config.modules.home.programs.zotero.enable {
    home.packages = with pkgs; [
      zotero
    ];
  };
}
