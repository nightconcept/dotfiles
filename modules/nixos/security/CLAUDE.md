# SOPS Secret Management

Secrets managed via sops-nix. Age keys derived from SSH keys.

## Key Rule

**Always use the `danny_personal` age key** for all secrets — not host-specific keys. This provides access across all systems.

## Secret Path Conventions

| Type | Path pattern | Example |
|------|-------------|---------|
| NixOS system | `/run/secrets/<service>-<secret>` | `/run/secrets/nordvpn-token` |
| Home Manager | `$XDG_RUNTIME_DIR/secrets/<secret>` | `/run/user/1000/secrets/gemini_api_key` |

## Adding a Secret

1. `sops <encrypted-file.yaml>` — edit the encrypted YAML
2. Add the secret definition in the module's sops configuration
3. Use the path conventions above
