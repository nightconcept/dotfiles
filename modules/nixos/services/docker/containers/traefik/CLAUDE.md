# Traefik + CrowdSec

CrowdSec provides intrusion prevention for internet-facing services via behavior analysis and IP blocking.

## Architecture

- **CrowdSec Engine**: analyzes logs, detects malicious behavior
- **Traefik Bouncer**: middleware that blocks flagged IPs at the proxy level
- Bouncer middleware defined in `config/config.yml`

## Adding CrowdSec Protection to a Service

For any service exposed to the internet, add to its compose labels:

```yaml
- "traefik.http.routers.myservice-secure.middlewares=crowdsec-bouncer@docker"
```

Full label set example:
```yaml
- "traefik.enable=true"
- "traefik.http.routers.myservice.entrypoints=http"
- "traefik.http.routers.myservice.rule=Host(`myservice.local.solivan.dev`)"
- "traefik.http.middlewares.myservice-https-redirect.redirectscheme.scheme=https"
- "traefik.http.routers.myservice.middlewares=myservice-https-redirect"
- "traefik.http.routers.myservice-secure.entrypoints=https"
- "traefik.http.routers.myservice-secure.rule=Host(`myservice.local.solivan.dev`) || Host(`myservice.solivan.dev`)"
- "traefik.http.routers.myservice-secure.tls=true"
- "traefik.http.routers.myservice-secure.middlewares=crowdsec-bouncer@docker"
- "traefik.http.routers.myservice-secure.service=myservice"
- "traefik.http.services.myservice.loadbalancer.server.port=80"
- "traefik.docker.network=proxy"
```

Local domain: `myservice.local.solivan.dev` | External: `myservice.solivan.dev`

## Currently Protected Services

- **vaultwarden** — vaultwarden.solivan.dev
- **obsidian-sync** — obsidian-db.solivan.dev
- **opengist** — gist.solivan.dev
- **headscale** — hs.solivan.dev

## Monitoring

```bash
docker exec crowdsec cscli decisions list
docker exec crowdsec cscli metrics
docker exec crowdsec cscli alerts list
```
