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

### WezTerm Clipboard on Windows

The WezTerm config in `modules/home/programs/wezterm/config.lua` adds Windows
clipboard shortcuts:

- Select text with the mouse to copy it automatically.
- **Ctrl+C** copies selected terminal text and clears the selection. With no
  selection, it sends Ctrl+C to the running program to interrupt it as usual.
- **Ctrl+V** or **right-click** pastes from the Windows clipboard.
- **Ctrl+Insert** copies and **Shift+Insert** pastes using the Windows clipboard.
- The default **Ctrl+Shift+C/V** shortcuts also work.

When an application captures the mouse (such as tmux or Vim), hold **Shift** while
selecting text or right-clicking to use WezTerm's clipboard behavior.

Windows loads `%USERPROFILE%\.config\wezterm\wezterm.lua`; an older installation
may use separate `keybinds.lua` and `mousebinds.lua` files there. Changes to the
repository do not automatically update those installed files. WezTerm normally
reloads saved configuration changes automatically; **Ctrl+Shift+R** reloads them
manually.

### Why This Approach?

Using native package managers for GUI applications on non-NixOS systems:
- Avoids nixGL complexity and OpenGL library conflicts
- Works reliably with system graphics drivers
- Simpler to maintain and update
- Configuration still fully declarative via Nix
