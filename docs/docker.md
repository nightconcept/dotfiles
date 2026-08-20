# Docker Configuration

Docker services are managed as Nix modules in `/modules/nixos/services/docker/containers/`. Each container has its own module that defines:
- Docker compose configuration
- Environment variables
- Volume mounts
- Network configuration
- Traefik labels for reverse proxy

Available container modules include:
- **Media**: jellyfin, plex
- ***arr Stack**: sonarr, radarr, prowlarr, readarr, flaresolverr
- **Books**: audiobookshelf, calibre, calibre-web, readarr-books
- **Home Automation**: homepage, uptime-kuma
- **Infrastructure**: traefik, portainer, watchtower, cloudflare-tunnel
- **Authentication**: vaultwarden
- **Development**: forgejo, forgejo-runner, paseo
- **Gaming**: minecraft, enshrouded, palworld
- **Utilities**: freshrss, nextcloud, open-webui, searxng, wg-easy, ddclient, knot

Docker networks:
- `proxy` - Shared network for services behind Traefik reverse proxy

## Terra Budget Stack

Actual Budget and Paisa run on Terra through the pyinfra-managed Docker Compose
stack at `/opt/budget`. Rinoa's Traefik instance is the TLS endpoint and
proxies the following local URLs to Terra:

- `https://budget.local.solivan.dev` -> Actual Budget on Terra port 5006
- `https://ledger.local.solivan.dev` -> Paisa on Terra port 7500

Persistent data stays on Terra:

- `/opt/budget/actual-data` — Actual server and user files
- `/opt/budget/paisa-data` — Paisa configuration and SQLite database
- `/opt/budget/ledger` — Ledger journal, mounted read-only by Paisa

The first deployment seeds a non-personal Ledger journal. Replace it with the
`nightconcept/ledger` Forgejo checkout only when that repository is ready and
an out-of-band read-only credential is available. Back up all three directories
before upgrades. Actual and Ledger transaction conversion is a separate future
project; no synchronization occurs in this stack.

Before deploying the Rinoa routes, create these Pi-hole local DNS records that
resolve to Rinoa (`192.168.1.110`), not Terra:

- `budget.local.solivan.dev` -> `192.168.1.110`
- `ledger.local.solivan.dev` -> `192.168.1.110`

Verify both names resolve to Rinoa before using the HTTPS URLs. The Terra
backend address (`192.168.1.111`) is intentionally recorded in the
Traefik file-provider configuration and the Terra deployment module; update
both host-specific configurations together if it changes.

## Adding a New Service Checklist

After deploying a new container with Traefik labels, you must also add DNS records manually:

**Local domain** (`*.local.solivan.dev`): Add a custom DNS record in Pi-hole.
- Pi-hole admin → **Local DNS → DNS Records**
- Domain: `<subdomain>.local.solivan.dev` → IP: `192.168.1.110` (rinoa)

**Public domain** (`*.solivan.dev`): Add a DNS record in Cloudflare pointing to rinoa's WAN IP or Cloudflare Tunnel.
