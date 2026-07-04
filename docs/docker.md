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
- **Authentication**: authelia, vaultwarden
- **Development**: forgejo, forgejo-runner
- **Gaming**: minecraft, enshrouded, palworld
- **Utilities**: freshrss, nextcloud, open-webui, searxng, wg-easy, ddclient, knot

Docker networks:
- `proxy` - Shared network for services behind Traefik reverse proxy

## Adding a New Service Checklist

After deploying a new container with Traefik labels, you must also add DNS records manually:

**Local domain** (`*.local.solivan.dev`): Add a custom DNS record in Pi-hole.
- Pi-hole admin → **Local DNS → DNS Records**
- Domain: `<subdomain>.local.solivan.dev` → IP: `192.168.1.110` (rinoa)

**Public domain** (`*.solivan.dev`): Add a DNS record in Cloudflare pointing to rinoa's WAN IP or Cloudflare Tunnel.
