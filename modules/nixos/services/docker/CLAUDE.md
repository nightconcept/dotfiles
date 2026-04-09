# Docker Services

Docker containers are Nix modules in `containers/`. Each defines compose config, env vars, volumes, networks, and Traefik labels.

## Network

- `proxy` — shared network for all services behind the Traefik reverse proxy

## Available Container Modules

| Category | Containers |
|----------|-----------|
| Media | jellyfin, plex |
| *arr Stack | sonarr, radarr, prowlarr, readarr, flaresolverr |
| Books | audiobookshelf, calibre, calibre-web, readarr-books |
| Home Automation | homepage, uptime-kuma |
| Infrastructure | traefik, portainer, watchtower, cloudflare-tunnel |
| Authentication | authelia, vaultwarden |
| Development | forgejo, forgejo-runner |
| Gaming | minecraft, enshrouded, palworld |
| Utilities | freshrss, nextcloud, open-webui, searxng, wg-easy, ddclient, knot |

See `containers/traefik/CLAUDE.md` for reverse proxy and CrowdSec configuration.
