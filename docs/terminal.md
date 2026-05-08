# Terminal Emulator Installation

Terminal emulators (Ghostty, WezTerm) use `configOnly` mode on non-NixOS systems to avoid OpenGL/graphics library conflicts. This means:

- **Configuration**: Managed by Nix/home-manager
- **Binary installation**: Manual via native package managers

### Ghostty Installation

**NixOS:**
- Installed via nixpkgs: `modules.home.programs.ghostty.enable = true`

**Non-NixOS Linux:**
- Uses `configOnly` mode
- Manual installation required:
  - Arch: `yay -S ghostty`
  - Debian/Ubuntu: Download from https://github.com/mkasberg/ghostty-ubuntu/releases

**macOS:**
- Uses `configOnly` mode
- Installed via Homebrew (managed in `modules/darwin/homebrew/`)

### WezTerm Installation

Same pattern as Ghostty:
- **NixOS**: Via nixpkgs
- **Non-NixOS**: Manual installation via package manager
- **macOS**: Via Homebrew

### Why This Approach?

Using native package managers for GUI applications on non-NixOS systems:
- Avoids nixGL complexity and OpenGL library conflicts
- Works reliably with system graphics drivers
- Simpler to maintain and update
- Configuration still fully declarative via Nix
