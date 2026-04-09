# Home Program Modules

## Terminal Emulator Pattern (`configOnly` mode)

GUI terminal emulators (Ghostty, WezTerm) use `configOnly` mode on non-NixOS systems to avoid OpenGL/graphics library conflicts:

| System | Approach |
|--------|---------|
| NixOS | Full install via nixpkgs |
| Non-NixOS Linux | `configOnly = true` — Nix manages config only; binary installed manually |
| macOS | `configOnly = true` — binary installed via Homebrew (`modules/darwin/homebrew/`) |

### Ghostty manual install (non-NixOS Linux)
- Arch: `yay -S ghostty`
- Debian/Ubuntu: download from mkasberg/ghostty-ubuntu releases

### Why not nixGL?
Avoids nixGL complexity and OpenGL library conflicts with system graphics drivers.
