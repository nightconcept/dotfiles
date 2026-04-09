# Hyprland Desktop Configuration

## Core Components

| File | Purpose |
|------|---------|
| `hyprland.nix` | Main Hyprland window manager config |
| `waybar.nix` | Status bar (Tokyo Night theme) |
| `hypridle.nix` | Idle management with power-aware timeouts |
| `hyprlock.nix` | Lock screen (Mac-style interface) |
| `wlogout.nix` | Power menu (Stylix colors) |
| `wofi.nix` | App launcher (Tokyo Night theme) |
| `mako.nix` | Notification daemon |
| `gtk-settings.nix` | GTK theming |

## Key Bindings

| Binding | Action |
|---------|--------|
| `Super+Return` / `Super+T` | Open terminal (Ghostty) |
| `Super+Space` | App launcher (wofi) |
| `Super+L` | Lock screen (hyprlock) |
| `Super+Backspace` | Power menu (wlogout) |
| `Alt+Tab` | Cycle windows |
| `F1–F4` | Audio controls |
| `F6–F7` | Brightness controls |
| Print screen variations | Screenshots |

## Theming

Uses Stylix with Tokyo Night color scheme. Wallpaper images live in `/wallpaper/`. All components use consistent Stylix colors.
