# Docker Configuration

Docker services are managed as Nix modules in `/modules/nixos/services/docker/containers/`. Each container has its own module that defines:
- Docker compose configuration
- Environment variables
- Volume mounts
- Network configuration
- Traefik labels for reverse proxy

Available container modules include:
- **Media**: jellyfin, plex
- ***arr Stack**: sonarr, sonarr-anime, radarr, recyclarr, prowlarr, readarr, flaresolverr
- **Books**: audiobookshelf, calibre, calibre-web, readarr-books
- **Home Automation**: homepage, uptime-kuma, gotify
- **Infrastructure**: traefik, portainer, watchtower (Nicholas Fedor fork), cloudflare-tunnel
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

## Gotify Notifications (Vincent)

Gotify on Vincent pushes alerts for work that needs a person. It listens on
`http://192.168.1.185:8070`, and Rinoa's Traefik routes
`https://gotify.local.solivan.dev` to it (LAN and VPN clients only).

- **Uptime Kuma** sends monitor down/up and certificate expiry alerts through
  a default `Gotify` notification attached to every monitor.
- **Watchtower** on Vincent sends a report after it updates containers or
  fails to update them.
- **Disk space**: `gotify-disk-alert.timer` checks `/` every hour. It sends
  an alert when usage is at or above 85%, repeats it every 24 hours while the
  disk stays full, and sends one message when usage goes below 85%.

On the first start, the module generates the admin password in
`/var/lib/docker-containers/gotify/admin-password`. `gotify-provision.service`
creates the `uptime-kuma`, `watchtower` and `hermes-alerts` applications. Gotify 3 shows an
application token only once, so the service stores each token in
`/var/lib/docker-containers/gotify/tokens/`. If a token file is missing, the
service rotates that application's token. The `host-alerts` application is
added when `diskAlert.enable` is set.

To receive alerts, log in to the web UI as `admin`, then add a client in the
Gotify Android app (or another Gotify client) with the server URL.

## Security stack and reverse-proxy protection

The shared security package has central and sensor roles.
Vincent runs central EveBox/Wazuh services and a local sensor. Rinoa runs a local sensor that reports to Vincent.
Gotify remains on Vincent. CrowdSec remains on reverse-proxy hosts such as Rinoa.
See [the distributed security architecture](security.md) for package boundaries, capture interfaces, placement findings, and implementation status.

The module is `modules/nixos/services/docker/containers/security-stack/default.nix`.
Both host declarations enable their selected role on the next rebuild.
Vincent and Rinoa are active with healthy central and sensor containers.
The encrypted bridge token remains in `modules/nixos/security/sops/suricata.yaml`.
The package passed isolated central and remote-sensor tests on Terra.
See [enablement and test evidence](security.md#enable-vincent-first).

Run the package checks with the repository's Python environment:

```sh
uv run python -m unittest discover -s modules/nixos/services/docker/containers/security-stack -p 'test_*.py'
```

### CrowdSec on Rinoa

The configured CrowdSec service reads Traefik's existing `traefik_traefik-logs` volume.
Its bouncer key is registered through `BOUNCER_KEY_traefik` and shared with the existing Traefik bouncer.
Only routers with `crowdsec-bouncer@docker` enforce CrowdSec decisions. There is no host firewall bouncer or outbound filtering.
The acquisition whitelist covers the LAN and Tailscale IPv4/IPv6 ranges to preserve trusted client access.
Traefik's LAN access rules also permit the Tailscale IPv4/IPv6 ranges.
This whitelist prevents detection from creating bans. It does not remove existing manual decisions.
Barrett's NordVPN traffic and direct LAN services do not pass through this middleware.

Recent Traefik logs included Docker gateway addresses instead of public client addresses.
Cloudflare Tunnel client attribution needs validation before relying on CrowdSec for those requests.
Do not enable unrestricted trust of forwarded headers to resolve this.

Deploy the full Rinoa host from its repository checkout:

```sh
sudo nixos-rebuild switch --flake 'path:.#rinoa'
```

Check CrowdSec acquisition and bouncer registration:

```sh
docker exec crowdsec cscli metrics show acquisition
docker exec crowdsec cscli bouncers list
```

Terra checks parsed four synthetic Traefik records.
The test bouncer blocked a banned address and allowed LAN and Tailscale clients.
These checks do not validate every VPN application.

## Forgejo Runner Image Cache

The `forgejo-dind` container keeps its image cache in the named volume
`forgejo-runners_forgejo-dind-data`. Before this volume existed, each
recreation of the container left behind an anonymous `/var/lib/docker` volume
of 2-10 GB. `forgejo-dind-prune.timer` runs weekly and removes images that
have not been used for 7 days.

## Finance services on Rinoa

The `finance` module manages Actual Budget and Paisa on Rinoa.
Both containers use the `proxy` network. Neither container publishes a host port.
Traefik permits LAN and Tailscale clients through `secured@file`.

- `https://budget.local.solivan.dev` routes to Actual Budget, container port 5006.
- `https://ledger.local.solivan.dev` routes to Paisa, container port 7500.

The image digests preserve the versions from Terra during migration.
Update these digests separately after a backup.

Persistent paths on Rinoa:

- `/home/danny/docker/actual/data` contains the Actual server and user files.
- `/home/danny/docker/paisa/data` contains the Paisa configuration and database.
- `/home/danny/git/ledger` contains the Ledger checkout.

The module refuses to start without these migrated paths.
The daily Ledger sync and monthly house valuation timers also move to Rinoa.
The sync uses the existing SOPS password and SSH identity.
A full Terra deployment no longer starts either finance stack.

Migration status and commands: [finance migration](finance-migration.md).

## Private Compose credentials

The Docker module creates each runtime `.env` file with mode `0600` before the service writes credentials.
It also repairs existing file permissions when the service starts.
This rule covers enabled container modules on both Rinoa and Vincent.

To repair existing files without a service restart, run:

```sh
ssh -t rinoa 'sudo find /var/lib/docker-containers -xdev -type f -name .env -exec chmod 0600 {} +' && ssh -t vincent 'sudo find /var/lib/docker-containers -xdev -type f -name .env -exec chmod 0600 {} +'
```

This command changes file permissions. It does not rotate credentials.

## Adding a New Service Checklist

After deploying a new container with Traefik labels, you must also add DNS records manually:

**Local domain** (`*.local.solivan.dev`): Add a custom DNS record in Pi-hole.
- Pi-hole admin → **Local DNS → DNS Records**
- Domain: `<subdomain>.local.solivan.dev` → IP: `192.168.1.110` (rinoa)

**Public domain** (`*.solivan.dev`): Add a DNS record in Cloudflare pointing to rinoa's WAN IP or Cloudflare Tunnel.

## Linkwarden on Rinoa

The `linkwarden` module runs Linkwarden, PostgreSQL 16, and Meilisearch.
Traefik serves `https://linkwarden.local.solivan.dev` to LAN and Tailscale clients.
No container publishes a host port. Add this Pi-hole DNS record before deployment:
`linkwarden.local.solivan.dev` → `192.168.1.110`.

Deploy from Rinoa's checkout with `sudo nixos-rebuild switch --flake 'path:.#rinoa'`.
Open the URL and register your account. Registration is enabled for trusted clients.

State lives under `/var/lib/docker-containers/linkwarden/`:
`data/` contains archives, `pgdata/` contains PostgreSQL data, and `meili_data/`
contains the search index. The root-only `.env` contains generated credentials.
Credentials persist across rebuilds. Back up the credentials and data together;
stop `docker-container-linkwarden.service` before a filesystem backup.
Do not delete `.env` while retaining the database.

The application follows upstream's `latest` image tag; it is not opted into Watchtower.
SSO, email, and AI tagging are not configured.

## httpSMS on Rinoa

The `httpsms` module runs a self-hosted httpSMS gateway: API, web UI,
PostgreSQL 17, and Redis. The `events` app uses it to send invite and link texts.
Both images build on Rinoa from the pinned `httpsms` flake input. The first
start builds the web UI and takes several minutes.

- `https://httpsms.local.solivan.dev` routes to the web UI (port 3000).
- `https://httpsms-api.local.solivan.dev` routes to the API (port 8000).
  The gateway phone app uses this URL as its server URL.
- Both routes use `secured@file` (LAN and Tailscale clients only).
- Other containers call the API at `http://httpsms-api:8000` on `proxy`.
  The events app uses the private `events-sms` network instead.
- PostgreSQL data: `/var/lib/docker-containers/httpsms/data/postgres`.
- Secrets: `modules/nixos/security/sops/httpsms.yaml`. The module generated
  `db_password` and `system_api_key`. The Firebase values are `CHANGEME`.

The service refuses to start while a secret is `CHANGEME`. After the API
starts, the service adds the events-queue system user to the database.
There is no SMTP, so httpSMS sends no "phone offline" emails.

### Setup

1. Create a Firebase project. Enable **Authentication → Email/Password**.
   Disable **email enumeration protection** (a firebaseui bug).
2. Add `httpsms.local.solivan.dev` to **Authentication → Settings →
   Authorized domains**.
3. Register a **Web app**. Copy its config into `firebase_web/*` in
   `httpsms.yaml` (`sops modules/nixos/security/sops/httpsms.yaml`).
4. Generate a **service account** private key. Paste the JSON into
   `firebase_credentials` as a YAML block scalar (`firebase_credentials: |`).
5. Register an **Android app** with package `com.httpsms`. Download its
   `google-services.json`.
6. Build the Android app from the same httpSMS commit as the flake input.
   Replace `android/app/google-services.json` with your file first. The stock
   APK uses the hosted Firebase project, so it cannot receive your pushes.
7. Add Pi-hole DNS records for `httpsms` and `httpsms-api` to `192.168.1.110`.
8. Set `httpsms.enable = true` in `hosts/nixos/rinoa/default.nix`. Deploy Rinoa.
9. Sign up in the web UI. Install the app on the gateway phone. On the login
   screen, set the server URL to `https://httpsms-api.local.solivan.dev`. Scan
   the phone API key QR code from the web UI.
10. In the httpSMS app settings, set the message expiration to 600 seconds.

The phone must stay on the home Wi-Fi (or Tailscale) to reach the API.

## events on Rinoa

The `events` module runs the events app (`forge.solivan.dev/nightconcept/events`).
The image builds on Rinoa from the pinned `events` flake input.

- The Cloudflare Tunnel routes `events.solivan.dev` to `http://events:8080`.
  There are no Traefik labels and no host port. The app trusts
  `CF-Connecting-IP` because of that.
- The app is not on `proxy`. Only cloudflared reaches it, on `events-edge`.
  Only `httpsms-api` shares `events-sms` with it (API calls and the webhook).
  The events module adds both networks to those two stacks.
- The container runs as `1000:100` with a read-only root filesystem.
- Data: `/var/lib/docker-containers/events/data` (SQLite and photos).
- Backups: `/mnt/titan/backups/events`, nightly at 03:00, 14 days kept.
- Secrets: `modules/nixos/security/sops/events.yaml`. The module generated
  `admin_password` and `httpsms_webhook_key`. The other values are `CHANGEME`.

### Setup

1. Push the events repository to the forge. Run `nix flake update events`.
2. Create a Cloudflare Turnstile widget for `events.solivan.dev`. Put its keys
   in `turnstile_sitekey` and `turnstile_secret`.
3. In the httpSMS web UI, copy the account API key into `httpsms_api_key`.
   Put the gateway phone number (E.164) in `httpsms_from`.
4. In the httpSMS web UI, add a webhook: URL `http://events:8080/hooks/httpsms`,
   signing key = `httpsms_webhook_key`, events `message.phone.delivered`,
   `message.send.failed`, `message.send.expired`.
5. In the Cloudflare Zero Trust dashboard, add the tunnel public hostname
   `events.solivan.dev` with service `http://events:8080`.
   In the `solivan.dev` zone, add the bot protection:
   - Security → Bots: turn on Bot Fight Mode and Block AI bots.
   - WAF custom rule: hostname `events.solivan.dev` and country not `US` →
     Managed Challenge.
   - WAF rate-limiting rule: hostname `events.solivan.dev` and path starts
     with `/login` or `/i/`, 20 requests per 10 seconds per IP → Block.
6. Set `events.enable = true` in `hosts/nixos/rinoa/default.nix`. Deploy Rinoa.
7. Log in at `https://events.solivan.dev/admin/login` with `admin_password`
   (`sops -d modules/nixos/security/sops/events.yaml`).

### LAN preview (before the phone and Cloudflare)

`events.lanPreview = true` serves `https://events.local.solivan.dev` through
Traefik to LAN and Tailscale clients only. Texts and their personal links go to
`docker logs events` instead of a phone, and bot checks are off. Only
`admin_password` is needed. The tunnel and httpSMS are not involved.

Add the Pi-hole record `events.local.solivan.dev` → `192.168.1.110`. Phone and
name login needs no text, so test contacts can use any numbers. Personal links
are under **Contacts**. All LAN clients share one login rate-limit bucket
(5 phone and name logins per 10 minutes), because Traefik is the client IP the app sees.

To go live, set `lanPreview = false` after steps 1–5 and deploy. Delete test
data first if you want a clean start: stop the stack and remove
`/var/lib/docker-containers/events/data/*`.

To update the app, push to the forge, run `nix flake update events`, and
deploy Rinoa. The image tag is the commit, so a new commit builds a new image.
