{
  config,
  lib,
  pkgs,
  ...
}: {
  config = lib.mkIf (config.desktops.hyprland.enable or false) {
    # Hyprlock configuration
    xdg.configFile."hypr/hyprlock.conf".text = ''
      background {
        monitor =
        path = ${config.home.homeDirectory}/git/dotfiles-nix/wallpaper/laptop.jpg
        blur_passes = 1
        blur_size = 3
        noise = 0.0117
        contrast = 0.9
        brightness = 0.95
        vibrancy = 0.1696
        vibrancy_darkness = 0.0
      }

      input-field {
        monitor =
        size = 250, 50
        outline_thickness = 3
        dots_size = 0.2
        dots_spacing = 0.64
        dots_center = true
        dots_rounding = -1
        outer_color = rgb(151515)
        inner_color = rgb(1a1b26)
        font_color = rgb(c0caf5)
        fade_on_empty = true
        fade_timeout = 1000
        placeholder_text = <i>Password...</i>
        hide_input = false
        rounding = -1
        check_color = rgb(9ece6a)
        fail_color = rgb(f7768e)
        fail_text = <i>$FAIL <b>($ATTEMPTS)</b></i>
        fail_transition = 300
        capslock_color = -1
        numlock_color = -1
        bothlock_color = -1
        invert_numlock = false
        swap_font_color = false

        position = 0, -300
        halign = center
        valign = center
      }

      label {
        monitor =
        text = cmd[update:1000] echo "$TIME"
        color = rgb(c0caf5)
        font_size = 55
        font_family = SF Mono Nerd Font
        position = 0, -200
        halign = center
        valign = center
      }

      label {
        monitor =
        text = Welcome back, $USER
        color = rgb(c0caf5)
        font_size = 20
        font_family = SF Mono Nerd Font
        position = 0, -400
        halign = center
        valign = center
      }
    '';
  };
}
