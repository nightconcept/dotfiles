# Zotero WebDAV Container

WebDAV server for Zotero library sync, based on [louisaslett/zotero-webdav](https://github.com/louisaslett/zotero-webdav).

## Overview

This container provides a self-hosted WebDAV endpoint for syncing Zotero attachment files. It uses HTTP Basic Authentication, which is required for Zotero 8+.

## Configuration

The container is managed as a NixOS module at `modules.nixos.docker.containers.zotero-webdav`.

### Module Options

| Option | Default | Description |
|--------|---------|-------------|
| `enable` | `false` | Enable the container |
| `domain` | `local.solivan.dev` | Base domain |
| `subdomain` | `zotero` | Subdomain (resolves to `zotero.local.solivan.dev`) |
| `dataPath` | `/home/danny/docker/zotero/data` | WebDAV data directory |
| `usernameFile` | SOPS: `/run/secrets/services/zotero/username` | Path to username secret file |
| `passwordFile` | SOPS: `/run/secrets/services/zotero/password` | Path to password secret file |

### SOPS Secrets

Add the following to your SOPS secrets file:

```yaml
services:
  zotero:
    username: <your-username>
    password: <your-password>
```

Deployed to:
- `/run/secrets/services/zotero/username`
- `/run/secrets/services/zotero/password`

## Zotero Client Setup

In Zotero preferences, set the WebDAV sync URL to:

```
https://zotero.local.solivan.dev/zotero
```

Use the same username and password configured in the secrets above.

## Routing

Accessible at `https://zotero.local.solivan.dev` (local network only, no external exposure).
