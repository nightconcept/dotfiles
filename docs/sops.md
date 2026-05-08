# SOPS Secret Management

Secrets are managed using sops-nix:
- System secrets configured in `/modules/nixos/security/sops/`
- User secrets configured in `/modules/home/secrets/`
- Age keys derived from SSH keys
- Automatic deployment to runtime directories

### Secret Storage Conventions

#### SOPS Encryption Key
**ALWAYS use `danny_personal` age key for all secrets**. Do not use host-specific keys as the personal key provides access across all systems.

#### Deployed Secret Paths
System services (NixOS) should use:
- `/run/secrets/<service>-<secret>` - Standard SOPS deployment path
- Example: `/run/secrets/nordvpn-token`

User services (home-manager) should use:
- `$XDG_RUNTIME_DIR/secrets/<secret>` - User runtime directory (tmpfs)
- Expands to `/run/user/1000/secrets/<secret>`
- Example: `/run/user/1000/secrets/brave_api_key`

#### Adding New Secrets
1. Edit the encrypted YAML file using `sops`
2. Add the secret definition in the appropriate module's sops configuration
3. Follow the path conventions above for consistency
