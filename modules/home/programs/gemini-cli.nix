{
  config,
  lib,
  pkgs,
  ...
}: {
  options.modules.home.programs.gemini-cli = {
    enable = lib.mkEnableOption "gemini-cli AI agent";

    useBinVersion = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether to use gemini-cli-bin (faster updates) or gemini-cli (source build)";
    };

    package = lib.mkOption {
      type = lib.types.package;
      default =
        if config.modules.home.programs.gemini-cli.useBinVersion
        then pkgs.gemini-cli-bin
        else pkgs.gemini-cli;
      description = "The gemini-cli package to use";
    };
  };

  config = lib.mkIf config.modules.home.programs.gemini-cli.enable {
    home.packages = [config.modules.home.programs.gemini-cli.package];
  };
}
