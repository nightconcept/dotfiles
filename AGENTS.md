# AGENTS.md (Hub)

Personal dotfiles as a Nix flake supporting NixOS, nix-darwin, and home-manager.
⚠ This file is hard-limited to ≤100 lines. Update spokes, not the hub.

## Documentation Hub (Spokes)

- [Architecture](docs/architecture.md) - Directory structure, hierarchy, and profiles.
- [Bootstrap](docs/bootstrap.md) - How to install and setup new systems.
- [SOPS](docs/sops.md) - Secret management and storage conventions.
- [Docker](docs/docker.md) - Container modules and networking.
- [Hyprland](docs/hyprland.md) - Desktop environment components and keybindings.
- [Terminal](docs/terminal.md) - Installation guide for Ghostty and WezTerm.

## Common Commands

### Rebuild & Deployment Commands
- **NixOS**: `nixos-rebuild switch --flake .#<hostname>`
- **Darwin**: `sudo darwin-rebuild switch --flake .#<hostname>`
- **Home Manager**: `home-manager switch --flake '.#<profile_or_hostname>'`
- **Linux (pyinfra + home-manager)**: `flake-rebuild <hostname>` — auto-detects local vs remote; use `just <hostname>` to invoke pyinfra directly
- Use `just <hostname>` only to deploy the full named host. Never add or use one-off deployment entrypoints.

### Windows (yuki)
Run `yuki` from the `windows/` directory to manage packages.

## Engineering Standards

- **Python**: Follow [Google's Python Style Guide](https://google.github.io/styleguide/pyguide.html). Use **Ruff** and **ty**.
- **Conventional Commits**: Use [Conventional Commits](https://www.conventionalcommits.org/) for all PRs and commits.
  - `feat:` for new features
  - `fix:` for bug fixes
  - `docs:` for documentation changes
  - `style:` for formatting, missing semi colons, etc; no code change
  - `refactor:` for refactoring production code
  - `test:` for adding missing tests, refactoring tests; no production code change
  - `chore:` for updating grunt tasks etc; no production code change
- **Credential Protection**: Never log, print, or commit secrets. Protect `.env`, `.git`, and system configs.
- **Contextual Precedence**: `CLAUDE.md` files in subdirectories take absolute precedence for local context.

## Project Overview

Nix flake configuration for personal dotfiles using `nixpkgs-unstable`. Each major directory has a `CLAUDE.md` with area-specific context.
