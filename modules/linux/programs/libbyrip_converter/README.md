# LibbyRip Converter

Pyinfra-managed Docker stack for the LibbyRip web converter on `terra`.

Source repo:
- Local checkout: `/home/danny/git/LibbyRip`
- Upstream: `git@github.com:nightconcept/LibbyRip.git`

Production deployment:
- Run `just terra` from the `dotfiles` repo.
- The app listens on `http://terra:8086` on the local network.
- Point your separate Traefik server at `http://terra:8086` and route `converter.local.solivan.dev` there.

Storage layout:
- Upload queue: `/mnt/titan/transfer/upload_audiobooks`
- Converted output: `/mnt/titan/Audiobooks`
- App state: `/opt/libbyrip-converter/data`

Local development:
- Run `just dev` from the `dotfiles` repo.
- Open `http://localhost:8080`.
