{
  config,
  lib,
  ...
}: let
  # Import our custom lib functions
  moduleLib = import ../../../lib/module {inherit lib;};
  inherit (moduleLib) mkBoolOpt enabled disabled;
in {
  options.modules.home.programs.xdg = {
    enable = mkBoolOpt false "Enable XDG user directories and MIME associations";
  };

  config = lib.mkIf config.modules.home.programs.xdg.enable {
    xdg = {
      enable = true;
      cacheHome = config.home.homeDirectory + "/.local/cache";

      mimeApps = {
        enable = true;
        associations.added = {
          "video/mp4" = ["io.github.celluloid_player.Celluloid.desktop"];
          "video/quicktime" = ["io.github.celluloid_player.Celluloid.desktop"];
          "video/webm" = ["io.github.celluloid_player.Celluloid.desktop"];
          "image/png" = ["org.gnome.Loupe.desktop"];
          "image/jpg" = ["org.gnome.Loupe.desktop"];
          "image/jpeg" = ["org.gnome.Loupe.desktop"];
        };
        defaultApplications = {
          "application/x-extension-htm" = "firefox";
          "application/x-extension-html" = "firefox";
          "application/x-extension-shtml" = "firefox";
          "application/x-extension-xht" = "firefox";
          "application/x-extension-xhtml" = "firefox";
          "application/xhtml+xml" = "firefox";
          "text/html" = "firefox";
          "x-scheme-handler/about" = "firefox";
          "x-scheme-handler/chrome" = ["chromium-browser.desktop"];
          "x-scheme-handler/ftp" = "firefox";
          "x-scheme-handler/http" = "firefox";
          "x-scheme-handler/https" = "firefox";
          "x-scheme-handler/unknown" = "firefox";

          "audio/*" = ["mpv.desktop"];
          "video/*" = ["org.gnome.Totem.dekstop"];
          "video/mp4" = ["org.gnome.Totem.dekstop"];
          "image/*" = ["org.gnome.loupe.desktop"];
          "image/png" = ["org.gnome.loupe.desktop"];
          "image/jpg" = ["org.gnome.loupe.desktop"];
          "application/json" = ["gnome-text-editor.desktop"];
          "application/pdf" = "firefox";
          "x-scheme-handler/discord" = ["discord.desktop"];
          "x-scheme-handler/spotify" = ["spotify.desktop"];
          "x-scheme-handler/x-github-desktop-dev-auth" = "github-desktop.desktop";
          "application/toml" = "org.gnome.TextEditor.desktop";
          "text/plain" = "org.gnome.TextEditor.desktop";
        };
      };

      userDirs = {
        enable = true;
        createDirectories = true;
        extraConfig = {
          SCREENSHOTS = "${config.xdg.userDirs.pictures}/Screenshots";
        };
      };
    };
  };
}
