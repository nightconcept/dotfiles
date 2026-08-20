# Actual Budget and Paisa on Terra — Research

Date: 2026-08-20

## Scope

This note records first-party deployment requirements for Actual Budget and
Paisa, plus the repository conventions relevant to deploying them on Terra.
It does not assume an Actual-to-Paisa integration: they use separate data
models.

## Actual Budget

- The official server images are `actualbudget/actual-server` (Docker Hub) and
  `ghcr.io/actualbudget/actual` (GHCR). Upstream recommends the `latest` tag
  for most users. [Actual Docker installation](https://actualbudget.org/docs/install/docker/)
- The server listens on port `5006`. Upstream's Compose file mounts persistent
  host data at `/data`, supplies a container health check, and uses
  `restart: unless-stopped`. The server creates `server-files` and `user-files`
  underneath the mounted data directory. [Upstream Compose file](https://github.com/actualbudget/actual/blob/master/packages/sync-server/docker-compose.yml), [Actual Docker installation](https://actualbudget.org/docs/install/docker/)
- Actual includes the browser client; the server provides cross-device sync and
  bank syncing. Its default login method is password authentication. The
  server can terminate TLS itself, but the upstream HTTPS documentation also
  describes a reverse-proxy deployment. Use the reverse proxy already needed
  for the requested hostname rather than adding per-container TLS.
  [Installation overview](https://actualbudget.org/docs/install/), [server configuration](https://actualbudget.org/docs/config/), [HTTPS configuration](https://actualbudget.org/docs/config/https/)
- If budget-file imports fail through a proxy, review the proxy's request-body
  limit; Actual explicitly calls this out for reverse-proxy deployments.
  [Actual FAQ](https://actualbudget.org/docs/faq/)

## Paisa

- Paisa is a personal-finance manager built on the Ledger CLI double-entry
  accounting tool. It is not an Actual client and it does not consume Actual
  budget data. [Paisa repository](https://github.com/ananthakumaran/paisa)
- Upstream publishes `ananthakumaran/paisa:latest`. The default image includes
  Ledger and listens on `7500`; upstream's Docker example maps the persistent
  host directory to `/root/Documents/paisa/`. `-hledger`, `-beancount`, and
  `-all` image variants are available when a different journal engine is
  needed. [Paisa Docker installation](https://paisa.fyi/getting-started/installation/), [upstream Dockerfile](https://github.com/ananthakumaran/paisa/blob/master/Dockerfile)
- Paisa discovers configuration in this order: `PAISA_CONFIG`, `--config`,
  current directory, then `paisa/paisa.yaml` under the user's Documents
  directory. The required `paisa.yaml` values include `journal_path` and
  `db_path`; Paisa creates the database when it does not exist.
  [Paisa configuration reference](https://paisa.fyi/reference/config/)
- Paisa can configure UI users in `paisa.yaml`. That does not protect the
  ledger and database files from anyone with filesystem access; if exposed
  outside the trusted LAN, upstream requires HTTPS and a strong password.
  [Paisa user authentication](https://paisa.fyi/reference/user-authentication/)

## Repository findings

- Terra is a non-NixOS Ubuntu host deployed through pyinfra. Its entry point
  is [`hosts/linux/terra/main.py`](../../../hosts/linux/terra/main.py), which
  deploys Docker before its service modules. The correct implementation seam
  is therefore a new `modules/linux/programs/<service>/` `HostModule`, then an
  import/instance/deploy call in that Terra entry point—not a NixOS container
  module. [Architecture](../../architecture.md)
- Terra Docker modules put Compose files in a persistent `/opt/<stack>`
  directory, create required state directories, copy the Compose file through
  pyinfra, and start it with `docker compose ... up -d`. See
  [`modules/linux/programs/koreader_sync/module.py`](../../../modules/linux/programs/koreader_sync/module.py)
  and [`modules/linux/programs/paseo/module.py`](../../../modules/linux/programs/paseo/module.py).
- The existing Terra services publish host ports directly and use
  `restart: unless-stopped`; Watchtower updates only containers labeled
  `com.centurylinklabs.watchtower.enable=true`. See
  [`modules/linux/programs/watchtower/docker-compose.yml`](../../../modules/linux/programs/watchtower/docker-compose.yml).
- The repository's Traefik `proxy` network and `*.local.solivan.dev` routing
  conventions belong to the NixOS Docker stack on Rinoa, not Terra. The
  documented local DNS procedure currently maps names to Rinoa
  (`192.168.1.110`). [Docker documentation](../../docker.md)

## Design implications for the plan

1. Add one Terra-managed budget stack (or two focused modules) with persistent
   directories under `/opt`, deploying Actual at `/data` and Paisa at
   `/root/Documents/paisa`. Add health checks for both HTTP services and use
   restart policies consistent with existing Terra Compose stacks.
2. Treat `budget.local.solivan.dev` and `ledger.local.solivan.dev` as a
   separate routing prerequisite. Terra currently has neither a reverse proxy
   nor documented local-DNS records for those names. The implementation must
   add a Terra-facing reverse proxy and DNS records targeting Terra, or the
   requested names cannot route to the containers. Do not point these records
   at Rinoa unless Rinoa is intentionally configured to proxy traffic to
   Terra.
3. Keep the initial Paisa deployment independent from
   `forge.solivan.dev/nightconcept/ledger`: create a persisted configuration
   and data location that can run with a safe test journal. A later, separate
   change should authenticate and clone or otherwise mount the Forgejo ledger
   repository read-only at the configured `journal_path`, while retaining the
   Paisa database outside that checkout. This avoids treating the WIP ledger
   repository as ready and avoids writing generated database state into Git.
4. Do not add or store journal data, Paisa credentials, or Actual server
   passwords in the repository. Configure secret values out of band; retain
   access to the persisted directories for backup and recovery.

## Verification targets

- `just terra` (or `flake-rebuild terra`) completes and Docker reports both
  containers running and healthy.
- Direct host checks reach Actual on port 5006 and Paisa on port 7500.
- After the routing prerequisite is implemented, HTTPS requests to
  `https://budget.local.solivan.dev` and `https://ledger.local.solivan.dev`
  reach the corresponding application.
- Restarting or recreating the containers preserves Actual server/user files
  and Paisa configuration, journal, and database state. A later ledger-repo
  integration must also demonstrate that Paisa can read the configured
  journal without modifying the checkout.
