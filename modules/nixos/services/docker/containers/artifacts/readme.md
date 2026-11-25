# artifacts

[Artifact Share](https://forge.solivan.dev/nightconcept/artifact-share) (our fork of
AlexDobrushskiy/artifact-share) at `https://artifacts.local.solivan.dev/<id>`. Client skill:
`home/skills/publish-artifact`. Plan and decisions: `home/docs/plans/artifacts-hosting.md`.

One Go binary over SQLite. The image builds on Rinoa from the pinned `artifact-share` flake
input. Pages are private until made public: the owner signs in, everyone else gets 404.

| File | What it does |
|---|---|
| `default.nix` | Options, data folder, the systemd unit that builds and runs the compose project. |
| `docker-compose.yml` | The container (read-only, no capabilities) and its Traefik labels with the CrowdSec bouncer. |

Data: `<dataPath>/artifacts.sqlite3` holds every revision, comment and key digest. It does
not expire, and it is **not backed up yet**.

## Operate

```sh
# Sign in as the owner: prints a one-time URL valid for 10 minutes.
ssh rinoa docker exec artifacts artifact-share owner link
# Publisher key for an agent machine (the secret prints once).
ssh rinoa docker exec artifacts artifact-share key create --label terra --scopes create,read,update
ssh rinoa docker exec artifacts artifact-share key list
ssh rinoa docker exec artifacts artifact-share backup /data/backup.sqlite3
```

Keys go in `~/.config/artifact-share/config.json` on each machine; see the home skill.

## Upgrade

Push to `nightconcept/artifact-share`, then bump the `artifact-share` rev in `flake.nix`,
`nix flake lock --update-input artifact-share`, and switch Rinoa. Merge upstream with
`git fetch upstream && git merge upstream/main` in the fork.

## Not done yet

- The Cloudflare tunnel hostname `artifacts.solivan.dev`, a rate-limit rule, and CrowdSec
  seeing real client addresses. Then `public = true` in `hosts/nixos/rinoa/default.nix`.
- Back up the data folder.
