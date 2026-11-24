# artifacts

Single-file HTML pages written by agents, served at `https://artifacts.solivan.dev/<id>`
(LAN: `artifacts.local.solivan.dev`). Plan: `home/docs/plans/artifacts-hosting.md`.
Client: `home/skills/publish-artifact`.

| File | What it does |
|---|---|
| `nginx.conf` | Serves `/<id>`; `PUT`/`DELETE /_api/<id>.html\|.json` and `GET /_api/index.json` need the token. Sends the content policy. |
| `sweep.py` | Expires artifacts and builds `index.json`. A systemd timer runs it every 5 minutes. |
| `test_sweep.py` | `python3 -m unittest test_sweep` in this folder. |
| `compose.traefik.yml` | Traefik labels with the CrowdSec bouncer. |
| `compose.local.yml` | Publishes `127.0.0.1:8089` for a local preview. |

Data: `<dataPath>/a/<id>.html`, `<id>.json`, and `<dataPath>/index.json`. The `.html`
mtime is the creation time. The data is not backed up.

## Token

`write_token` in `modules/nixos/security/sops/artifacts.yaml`. The module writes it
into `auth.conf` (mode 400, uid 101) for nginx. Read it with
`sops -d --extract '["write_token"]' modules/nixos/security/sops/artifacts.yaml`.
To rotate: replace the value and switch Rinoa.

## Local preview

Make a data folder and an `auth.conf` with the map from `default.nix`, mount them over
`./data` and `./auth.conf` in a compose override, then
`docker compose -f docker-compose.yml -f compose.local.yml -f override.yml up -d`.

## Not done yet

- The Cloudflare tunnel hostname `artifacts.solivan.dev`, a rate-limit rule for
  `PUT`/`DELETE`, and a check that CrowdSec sees real client addresses. Then
  `public = true` for `artifacts` in `hosts/nixos/rinoa/default.nix`.
