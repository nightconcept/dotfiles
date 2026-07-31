# Scripts

## Bootstrap

New systems bootstrap via:
```bash
wget -qO- https://raw.githubusercontent.com/nightconcept/dotfiles-nix/main/bootstrap.sh | bash
```

The script:
- Detects OS (NixOS, Linux, macOS)
- Installs Nix if needed
- Clones this repository
- NixOS: offers host selection (tidus/aerith)
- Linux: sets up Home Manager with profile selection
- macOS: provides manual instructions

## Other Scripts

| Script | Purpose |
|--------|---------|
| `add-host-to-sops.sh` | Register a new host's key with SOPS |
| `barrett-setup.sh` | Initial barrett server setup |
| `buzz-agents.sh` | Start/stop the codex/claude-code/goose ACP harnesses against the local Buzz relay (wraps block/buzz's own script) |
| `setup-keys.sh` | SSH key setup |
| `install-terminal.sh` | Install terminal emulator (Ghostty/WezTerm) |
| `switch-to-upstream-nix.sh` | Switch from distro Nix to upstream |
| `watchtower` | One-shot update for all Docker containers on local or remote host |
