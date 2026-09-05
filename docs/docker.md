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
- **Infrastructure**: traefik, portainer, watchtower (Nicholas Fedor fork), cloudflare-tunnel, headscale
- **Media requests**: seerr (the supported successor to Overseerr and Jellyseerr)
- **Authentication**: vaultwarden
- **Development**: forgejo, forgejo-runner, paseo
- **Gaming**: minecraft, enshrouded, palworld
- **Utilities**: freshrss, nextcloud, open-webui, searxng, wg-easy, ddclient, knot

Docker networks:
- `proxy` - Shared network for services behind Traefik reverse proxy

Rinoa runs the maintained `ghcr.io/nicholas-fedor/watchtower` fork daily at
04:00. Updates are opt-in: only running containers with the
`com.centurylinklabs.watchtower.enable=true` label are updated, and superseded
images are removed afterward. Watchtower follows the configured image tag; it
does not promote a pinned tag such as `3.5.2` to a newer release line.

## Terra Docker Compose Stacks

Actual Budget and Paisa run on Terra as separate pyinfra-managed Docker Compose
stacks at `/opt/budget` and `/opt/ledger`.
Actual Budget opts into Terra's Watchtower instance for automatic image updates.

BookOrbit runs as a Nix-managed Docker service on Rinoa. It stores its
application and PostgreSQL data in `/home/danny/docker/bookorbit/data` on
Rinoa and mounts `/mnt/titan` as `/books`, exposing `/books/Books` and
`/books/Audiobooks`. On its first start, BookOrbit creates a private `.env`
file and generates its database password, JWT secret, and setup token.

BookOrbit is available at `https://books.local.solivan.dev` and
`https://books.solivan.dev`.

Actual Budget and Paisa use the following local URLs. Rinoa's Traefik instance
is the TLS endpoint and proxies them to Terra:

- `https://budget.local.solivan.dev` -> Actual Budget on Terra port 5006
- `https://ledger.local.solivan.dev` -> Paisa on Terra port 7500

Persistent data stays on Terra:

- `/home/danny/docker/actual/data` — Actual server and user files
- `/home/danny/docker/paisa/data` — Paisa configuration and SQLite database
- `/home/danny/git/ledger` — Ledger Git checkout, mounted read-write by Paisa

Paisa uses `clean/main.journal` from the `nightconcept/ledger` checkout and
the hledger image. Back up all three directories before upgrades. Actual and
Ledger transaction conversion is a separate future project; no synchronization
occurs between these stacks.

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
