{
  config,
  lib,
  pkgs,
  inputs,
  osConfig ? {},
  ...
}:
with lib; let
  cfg = config.modules.home.programs.nvim;

  # Distribution packages abstraction
  distroPackages = {
    basic = [pkgs.neovim];
    nvchad = [inputs.nvchad.packages.${pkgs.system}.nvchad];
    lazyvim = [inputs.lazyvim-nixvim.packages.${pkgs.system}.default];
  };
in {
  options.modules.home.programs.nvim = {
    enable = mkEnableOption "neovim configuration";

    distro = mkOption {
      type = types.enum ["basic" "nvchad" "lazyvim"];
      default = "basic";
      description = "The neovim distribution to use";
    };

    extraPackages = mkOption {
      type = types.listOf types.package;
      default = [];
      description = "Additional packages to install alongside nvim";
      example = literalExpression "[ pkgs.ripgrep pkgs.fd ]";
    };

    aliases = {
      vim = mkOption {
        type = types.bool;
        default = true;
        description = "Create 'vim' alias for nvim";
      };

      vi = mkOption {
        type = types.bool;
        default = true;
        description = "Create 'vi' alias for nvim";
      };
    };
  };

  config = mkIf cfg.enable (mkMerge [
    # Base configuration for all distros
    {
      home.packages =
        (distroPackages.${cfg.distro} or [])
        ++ cfg.extraPackages;

      # Create shell aliases if requested
      programs.fish.shellAliases = mkIf config.programs.fish.enable {
        vim = mkIf cfg.aliases.vim (mkForce "nvim");
        vi = mkIf cfg.aliases.vi (mkForce "nvim");
      };

      programs.bash.shellAliases = mkIf config.programs.bash.enable {
        vim = mkIf cfg.aliases.vim (mkForce "nvim");
        vi = mkIf cfg.aliases.vi (mkForce "nvim");
      };

      programs.zsh.shellAliases = mkIf config.programs.zsh.enable {
        vim = mkIf cfg.aliases.vim (mkForce "nvim");
        vi = mkIf cfg.aliases.vi (mkForce "nvim");
      };

      # Set default editor
      home.sessionVariables = {
        EDITOR = "nvim";
        VISUAL = "nvim";
      };
    }
  ]);
}
