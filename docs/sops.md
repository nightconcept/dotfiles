# SOPS Secret Management

Secrets are managed using sops-nix:
- System secrets configured in `/modules/nixos/security/sops/`
- User secrets configured in `/modules/home/secrets/`
- Age keys derived from SSH keys
- Automatic deployment to runtime directories

Barrett's native SABnzbd service uses a pyinfra-managed SOPS integration.
Its encrypted file is `hosts/linux/barrett/secrets/sabnzbd.yaml`, using only
the personal age recipient. See [SABnzbd setup](network.md#sabnzbd-on-barrett)
for the schema and deployment commands. The service decrypts credentials in
memory at startup and writes them to SABnzbd's private configuration file.

### Reasonix API key

Run `sops modules/home/secrets/reasonix.yaml` and set `deepseek_api_key` to
your DeepSeek API key. The file uses only the personal age recipient.

Rebuild your Home Manager configuration to deploy the secret. SOPS renders
`~/.reasonix/.env` with mode `0400`; Reasonix 1.18.0 reads provider credentials
from this file rather than the process environment. Restart Reasonix after deployment.

The activation step updates the old `deepseek-v4-flash` model name to
`deepseek-flash` and preserves the other settings in `~/.reasonix/config.toml`.

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
