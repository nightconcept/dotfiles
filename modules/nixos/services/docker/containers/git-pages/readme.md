# git-pages (sites.solivan.dev)

Static sites for forge repos at `https://sites.solivan.dev/<user>/<repo>/`.
git-pages serves the `pages` branch of each repo. A Caddy router turns the
path `/<user>/<rest>` into host `<user>.pages.internal` and path `/<rest>`,
and puts the `/<user>` prefix back on redirects. See
`home/docs/plans/red-star-site-publishing.md` for the plan.

Authorization lives in `config.toml`: a push is accepted only for the `pages`
branch of `https://forge.solivan.dev/nightconcept/<repo>.git`. A new site needs
only a webhook on its repo; there is no DNS or tunnel change per site.

## Files

- `docker-compose.yml`: git-pages and the router, pinned by digest.
- `config.toml`, `Caddyfile`: the two services' configuration.
- `compose.local.yml`: publishes the router on `127.0.0.1:8088` for a preview.
- `compose.lan.yml`: Traefik labels for `sites.local.solivan.dev` with the
  CrowdSec bouncer. Not deployed yet; there is no NixOS module.

## Local preview

```bash
docker compose -f docker-compose.yml -f compose.local.yml up -d
```

Check authorization without moving content (the `Dry-Run` header runs only the
checks; the event header is what a Forgejo webhook sends):

```bash
curl -X POST http://127.0.0.1:8088/nightconcept/<repo>/ \
  -H 'Content-Type: application/json' -H 'X-Forgejo-Event: push' -H 'Dry-Run: yes' \
  --data '{"ref":"refs/heads/pages","repository":{"clone_url":"https://forge.solivan.dev/nightconcept/<repo>.git"}}'
```

A wrong branch, repo, user or host returns 401.

## Deploy secret

The router (Caddy) refuses `POST`, `PUT`, `DELETE` and `PATCH` unless the request
carries `Authorization: Bearer <token>`, so only your webhooks can deploy. Reads
need nothing. The token is `deploy_token` in
`modules/nixos/security/sops/git-pages.yaml`, set on the stack as `DEPLOY_TOKEN`
(a local preview needs `export DEPLOY_TOKEN=anything` first). The router removes
the header before git-pages sees it.

In the Forgejo webhook, put `Bearer <token>` in the **Authorization Header**
field. Read the token with
`sops -d --extract '["deploy_token"]' modules/nixos/security/sops/git-pages.yaml`.
To rotate it, replace the value, switch Rinoa, and update each webhook.

To load content without a forge, start git-pages with `PAGES_INSECURE=1`, `PUT`
a tar of the site to the site URL, then recreate it without the variable.
`PAGES_INSECURE` authorizes every request: never set it on a deployed host.

## Not done yet

- The Cloudflare tunnel hostname and WAF rule for `sites.solivan.dev`.
- Confirming CrowdSec sees the real client address for tunnel traffic
  (see the note in `docs/docker.md`).
