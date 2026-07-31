# Paseo Module for Terra

Pyinfra-managed Docker stack for Paseo daemon & web UI with preinstalled agent CLIs on `terra`.

## Architecture & Integration
- Container name: `paseo`
- Web UI & Daemon Port: `http://terra:6767`
- Persistent state: `/opt/paseo/home` -> `/home/paseo` inside container
- Workspace mount: `/home/danny/git` -> `/workspace` inside container
- Base image: `ghcr.io/getpaseo/paseo:latest`
- Included Agent CLIs: `@anthropic-ai/claude-code`, `@openai/codex`, `opencode-ai`

## Deployment
Run `just terra` from the `dotfiles` repo.
