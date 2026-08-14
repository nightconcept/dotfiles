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
| `setup-keys.sh` | SSH key setup |
| `install-terminal.sh` | Install terminal emulator (Ghostty/WezTerm) |
| `switch-to-upstream-nix.sh` | Switch from distro Nix to upstream |
| `bench-muse-glimmer.sh` | Swap terra's llama-swap to Muse Glimmer 30B, benchmark vs qwen3-35b-mtp, restore config |
| `switch-terra-default-model.sh` | Permanently deploy Muse Glimmer 30B on terra and point Hermes's default model at it |
| `watchtower` | One-shot update for all Docker containers on local or remote host |
