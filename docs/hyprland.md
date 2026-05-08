# Hyprland Desktop Environment

The Hyprland configuration is modular and includes:

### Core Components (`/home/desktops/hyprland/`)
- `hyprland.nix` - Main Hyprland window manager configuration
- `waybar.nix` - Status bar configuration with Tokyo Night theme
- `hypridle.nix` - Idle management with power-aware timeouts
- `hyprlock.nix` - Lock screen with Mac-style interface
- `wlogout.nix` - Power menu with Stylix colors
- `wofi.nix` - Application launcher with Tokyo Night theme
- `mako.nix` - Notification daemon
- `gtk-settings.nix` - GTK theming

### Theming
- Uses Stylix with Tokyo Night color scheme
- Consistent theming across all applications
- Custom wallpaper support in `/wallpaper/`

### Key Bindings
- `Super+Return/T` - Open terminal (Ghostty)
- `Super+Space` - Application launcher (wofi)
- `Super+L` - Lock screen (hyprlock)
- `Super+Backspace` - Power menu (wlogout)
- `Alt+Tab` - Cycle windows
- `F1-F4` - Audio controls
- `F6-F7` - Brightness controls
- Print screen variations for screenshots
