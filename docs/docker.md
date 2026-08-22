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
- **Infrastructure**: traefik, portainer, watchtower, cloudflare-tunnel, headscale
- **Media requests**: seerr (the supported successor to Overseerr and Jellyseerr)
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

- `/home/danny/docker/actual/data` — Actual server and user files
- `/home/danny/docker/paisa/data` — Paisa configuration and SQLite database
- `/home/danny/git/ledger` — Ledger Git checkout, mounted read-only by Paisa

Paisa uses `ledger/main.journal` from the `nightconcept/ledger` checkout and
the hledger image. Back up all three directories before upgrades. Actual and
Ledger transaction conversion is a separate future project; no synchronization
occurs in this stack.

Before deploying the Rinoa routes, create these Pi-hole local DNS records that
resolve to Rinoa, not Terra:

- `budget.local.solivan.dev` -> `rinoa`
- `ledger.local.solivan.dev` -> `rinoa`

Verify both names resolve to Rinoa before using the HTTPS URLs. Traefik resolves
the Terra backend through the local hostname `terra`.

## Adding a New Service Checklist

After deploying a new container with Traefik labels, you must also add DNS records manually:

**Local domain** (`*.local.solivan.dev`): Add a custom DNS record in Pi-hole.
- Pi-hole admin → **Local DNS → DNS Records**
- Domain: `<subdomain>.local.solivan.dev` → IP: `192.168.1.110` (rinoa)

**Public domain** (`*.solivan.dev`): Add a DNS record in Cloudflare pointing to rinoa's WAN IP or Cloudflare Tunnel.
