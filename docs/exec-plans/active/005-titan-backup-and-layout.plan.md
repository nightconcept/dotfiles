# Execution Plan: Titan backup on Jeanne, free Lancelot, tidy Titan's root

**ID:** 005
**Created:** 2026-11-21
**Status:** in progress. Phase 1 done 2026-11-21 except step 6: Lancelot holds 972 KB (root junk files and `lost+found`), 6.9 TB free.
Deleted 23,345 files (6.617 TB) whose content matched Titan or Jeanne. "Matched" means the same name, size, and SHA-256 of the first and last 1 MiB; Titan's side was hashed on mog.
Then, by the user's decision, deleted the rest of TVShows2, Movies2, and Games (439 GB): copies Titan had replaced, seasons and shows Titan no longer has, Mulholland Drive, and all games.
**Issue/Ref:** User request to free Lancelot, back up Titan's essential data to Terra, and give Titan's root a clearer layout.

## Goal

1. Free Lancelot (`/mnt/lancelot`, Terra md1 RAID5, 7.3 TB, 95 % full). It is an old copy of Titan from 2022 to 2024.
2. Make Jeanne (`/mnt/jeanne`, Terra md0 RAID5, 15 TB) the only backup of Titan on Terra. Back up essential data only. Do not back up TV shows, movies, anime, or games.
3. On Jeanne and Lancelot, keep TV shows and movies that match Titan. Delete the copies that no longer exist on Titan.
4. Group Titan's 26 root folders into a clearer layout. Keep every path that a service uses.

## How it was measured

Titan's size and file list come from mog over SSH (`ssh mog 'cd /export/titan && ...'`), where Titan is local disk.
Do not scan `/mnt/titan` over SMB; it is too slow for this.
Jeanne and Lancelot were listed on Terra's local disks.
A file "matches" when another tree has a file with the same name and byte size. No checksums were run.
Inventories (2026-11-21): Titan 362,613 files, Jeanne 2,498,735, Lancelot 29,370.
Refresh them before execution. The inventory script is in the 2026-11-21 session; rebuild it from the commands above.

## Measured state (2026-11-21)

### Lancelot (7.1 TB of files)

| Folder | Size | Matches Titan | Only on Jeanne | Unique |
|---|---|---|---|---|
| TVShows2 | 4,825 GB | 4,629 GB | 0 | 196 GB in 27 shows |
| Movies2 | 1,656 GB | 1,520 GB | 0 | 136 GB in 324 titles |
| Games | 580 GB | 427 GB | 15 GB | 138 GB in 19 titles |
| Wedding | 13.4 GB | all | 0 | 0 |
| Photography2 | 10.7 GB | all | 0 | 0 |
| Music2 | 2.9 GB | all | 0 | 0 |

Unique TV: Titan still has 15 of the 27 shows (138 GB; Titan's files differ, usually upgrades). 12 shows are gone from Titan (58 GB), for example The Traitors (US), The Transformers, Yellowjackets.
Unique movies: Titan has a different file for almost every title (135 GB). Only Mulholland Drive (1 GB) and stray `.eng` subtitle files are gone from Titan.
Unique games: 90 GB are titles Titan still has in another form, for example Forza Horizon 5. 48 GB in 11 titles are gone from Titan: Euro Truck Simulator 2 (17.5 GB), Tales of Vesperia, Cities: Skylines, Street Fighter 30th A.C., System Shock Remake, Dead Cells, the Final Fantasy Pixel Remasters, Chrono Trigger, Castlevania Chronicles II.

### Jeanne (4.7 TB of files)

Data that matches Titan: TV Shows 1,456 GB, Movies 757 GB, downloads 326 GB, Games 100 GB, Photography 24 GB, Music 21.5 GB, Airman Show, Programs, config, Archive.

Data that is **not on Titan**. Jeanne holds the only copy:

| Folder | Not on Titan |
|---|---|
| vesper-data | 875 GB |
| Games | 186 GB |
| Movies | 164 GB |
| Comics | 162 GB |
| transfer | 161 GB |
| calibre-library | 112 GB |
| TV Shows | 88 GB |
| downloads | 69 GB |
| starways | 43 GB |
| OS | 36 GB |
| AI Models | 23.5 GB |
| Books | 19.5 GB |
| titan | 6.8 GB |
| Audiobooks | 4.6 GB |
| scratch-fix-build-oom | 3.8 GB |

Titan data with **no copy on Jeanne**: Backups (76 GB), Wedding (13 GB), data (11 GB), docker (6 GB), Books (3.5 GB), Music (2.9 GB), most of Comics, Audiobooks, and config.

### Titan (29 TB, 44 TB pool)

TVShows 12.4 TB, Movies 3.5 TB, Anime 1.9 TB, Games-Unorganized 1.5 TB, Emulation 319 GB, Comics 203 GB, downloads 196 GB, Audiobooks 138 GB, Games 96 GB, Backups 76 GB, transfer 65 GB, Photography 55 GB, config 37 GB, OS 24 GB, Music-Unorganized 21.5 GB, vesper 20 GB, Programs 18 GB, Airman Show 14 GB, Wedding 13 GB, data 11 GB, Games-Staging 10 GB, Archive 9 GB, docker 6 GB, Books 3.5 GB, Music 2.9 GB.

## Phase 1: Free Lancelot

1. Refresh the Lancelot and Titan inventories.
2. Delete every Lancelot file that matches Titan (6.6 TB) or Jeanne (15 GB).
3. Delete unique TV and movie files. Titan has replaced or removed them, which follows the rule in goal 3.
4. Decide on the 48 GB of games that are gone from Titan (Open decision 1). Copy any that are kept to Titan `Games-Unorganized` through mog, then delete them from Lancelot.
5. Delete the root junk: `.DS_Store`, `._*`, `.Trash-1000`, and `sync.ffs_db` (an old FreeFileSync database).
6. Check that Lancelot is empty. Then the user unmounts it and stops md1 with sudo. Reusing the three disks is a separate decision.

## Phase 2: Back up Titan's essentials to Jeanne

Target: `/mnt/jeanne/titan-backup/`, with the same tree as `/export/titan`.

Include (about 0.7 TB): Backups, Photos, Photography, Wedding, Archive, config, data, docker, vesper, Books, Books-Unorganized, Music, Music-Unorganized, Audiobooks, Comics, Programs, OS, Airman Show.
Exclude: TVShows, Movies, Anime, Games, Games-Unorganized, Games-Staging, Emulation, downloads, transfer (Open decision 2).

Method:

- Terra pulls with rsync over SSH from mog's local disk, never over SMB:
  `rsync -aHAX --numeric-ids --delete --backup --backup-dir=/mnt/jeanne/titan-backup/.deleted/<date> mog:/export/titan/<folder>/ /mnt/jeanne/titan-backup/<folder>/`
- `--backup-dir` keeps files that Titan deleted or changed. Prune `.deleted/` after 90 days, so a mistake or ransomware on Titan does not wipe the backup.
- Run it as a weekly systemd user timer on Terra, managed in dotfiles (Terra's pyinfra modules). It sends a Gotify alert on failure.
- Terra is on Wi-Fi (see network.md). The first copy of 0.7 TB takes hours; run it overnight.
- Check it: rerun with `--dry-run --itemize-changes` (expect no changes), then compare file counts and a sample of checksums on both sides.

After the check passes, Jeanne's old loose copies of these folders (Photography, Music, Airman Show, Programs, config, Archive) duplicate `titan-backup/`. Delete them.

### Phase 2 progress (2026-11-22)

- `modules/linux/programs/titan_backup/` adds `titan-backup.sh`, a weekly `titan-backup.timer` (Sunday 05:00, `Persistent=true`), and `titan-backup-alert.service` (`OnFailure`). The alert posts to Gotify only when `/etc/titan-backup/gotify.token` exists; put a `host-alerts` app token there.
- Terra enables it in `hosts/linux/terra/main.py`. It is not deployed yet: run `just terra` at a quiet time (the full deploy restarts the AI stack and Hermes).
- The first sync was started by hand on 2026-11-22 with the same script (`systemd-run --user --unit=titan-backup-first`, log `~/.local/state/lancelot-moves/titan-backup-first.log`).
- After it finishes: rerun with `--dry-run --itemize-changes` (expect no changes), compare file counts, then delete Jeanne's old loose copies (`Photography`, `Music`, `Airman Show`, `Programs`, `config`, `Archive`, `Audiobooks`).
- Jeanne's matching TV and movies moved to `/mnt/jeanne/titan-media/` (2,644 files). The backup job does not touch it.

## Phase 3: Prune Jeanne's TV and movies

**Done 2026-11-21.** Deleted 555 files (292 GB): every TV and movie file with no name-and-size match on Titan (TV 87.9 GB, movies 138.5 GB) and, by the user's decision, all of `Movies/Movie Education` (65.6 GB, a rating-sorted copy of movies Titan already has). Kept 2.17 TB that matches Titan. Jeanne went from 4.2 TB to 4.0 TB used.

Keep Jeanne `TV Shows` and `Movies` files that match Titan (2.2 TB).
Delete the files that do not match Titan (88 GB of TV, 164 GB of movies), after a fresh inventory and a per-title list that the user reviews.

## Phase 4: Jeanne-only data

2026-11-21: deleted `OS` (52 GB of 2024 installer ISOs) and `AI Models` (23.5 GB: 2023 Stable Diffusion checkpoints and the finished ThinkingCap quant work folder) by the user's decision.
2026-11-21: deleted `calibre-library` (105 GB, the old January 2024 library) by the user's decision. The live Calibre on Terra uses `/mnt/calibre-library` and was not touched.

Jeanne is the only copy of about 1.9 TB (table above). For each folder, the user picks one:

- **Move to Titan:** it becomes primary there, and Phase 2 backs it up if it is in the include list.
- **Keep on Jeanne only:** Terra-local working data. Record that it has no backup.
- **Delete.**

Likely candidates: calibre-library and Comics move to Titan. vesper-data (875 GB) is deleted, because Vesper is finished. transfer and downloads are sorted or deleted. starways and AI Models stay Terra-local.

## Phase 5: Titan root layout

Services use these paths, so keep them where they are: `TVShows`, `Movies`, `Anime`, `Audiobooks`, `Books`, `downloads`, `transfer` (scripts in this repo), `Backups`, `docker`, `Games` (dgm registry paths like `Games/windows/...`), `Games-Unorganized` (Edea's dgm packaging input), and `Emulation/DGM`. The arr apps on Aerith also store root folders in their own databases.

Proposed root (26 folders become 17):

```
TVShows  Movies  Anime            media for Plex, Jellyfin, and the arr apps (unchanged)
Music  Audiobooks  Books  Comics  library media (unchanged; Music-Unorganized merges into Music/_inbox)
Games  Games-Unorganized  Emulation   dgm (unchanged; Games-Staging moves under Games/_staging)
Photos                            was Photography (renamed 2026-11-22)
Photography                       new folder for photos the user edits or develops
Personal/                         Wedding, Archive
Backups/                          existing Backups, plus config/ (service config backups) and docker-pre-locality-2026-11-01/
Music/                            also takes Airman Show
Software/                         OS, Programs
Projects/                         data (autotrader, ddd, madness, ...), vesper
downloads  transfer               inboxes (unchanged paths; transfer/upload_audiobooks is LibbyRip's upload path)
```

Before each move, search this repo, the service configs on Aerith, Rinoa, and Barrett, and the dgm registry for the old path. Move a folder only on mog (`mv` on local disk is instant). Update the references in the same change. `Books-Unorganized` is empty; delete it. Phase 2 must use the new paths after Phase 5.

### Phase 5 progress

**2026-11-21, done on mog with `mv` on local disk.** Each move was checked by file count and apparent size before and after; all matched:

- `Wedding` → `Personal/Wedding` (1,117 files); `Archive` → `Personal/Archive` (28)
- `OS` → `Software/OS` (4); `Programs` → `Software/Programs` (414)
- `config` → `Backups/config` (144,535)
- `docker` → `Backups/docker-pre-locality-2026-11-01` (40,222), after deleting the empty `docker/forgejo.new-empty.bak`
- `Music-Unorganized` → `Music/_inbox` (1,620), with a `.plexignore` of `*` so Plex's Music library (`/mnt/titan/Music`) skips it
- `Airman Show` → `Music/Airman Show` (568). Plex's Music library will scan it.
- Deleted `sync.ffs_db` (FreeFileSync state from 2024-03-24)
- The Forgejo and obsidian-livesync module defaults now point at `/var/lib/docker-containers/<name>/data`. Rinoa's system derivation is unchanged, so no deploy is needed.

Checked before moving: mog has no rsync or user cron jobs on these paths (only SnapRAID diff and sync, which handle renames). Plex libraries are Movies, TV Shows, and Music only.

**2026-11-22, `transfer/` sorted on mog.** Each move was checked by file count and size. Large directories were recounted against the 2026-11-21 Titan inventory, because `find` read a just-renamed tree incompletely on mergerfs. All matched.

- Backups are per person: `Backups/danny/windows-2025-06` (3,162 files, 2025 Windows reformat), `Backups/danny/game-saves/pc-2025-03` (6,028, "Saved Games"), `Backups/danny/game-saves/palworld-server/` (palworldbackup, two `saved-20240129_*.tar.gz` Palworld server saves, one `.sav`), `Backups/danny/config-misc/` (`debian_4_12`, `hardware-configuration.nix`, `colemak-dh.json`, `winutil-config.json`), `Backups/kim/pc-2025-01` (2,341, KimBackup).
- `Personal/Secrets/`: `luks.key`, `secret-key`, `dataset_storage0_keys.json`, `vw-recovery`. Normal permissions, by the user's choice. They are still readable on every Titan client; move them to a password manager or SOPS later.
- `Personal/Documents/`: `Identification.zip`, the eTranscript PDF, the VA residency video.
- `Photography/Phone/`: `11_4/` and 14 loose photos and videos.
- `Audiobooks/<Author>/<Title>/`: 10 MP3s. `Books/`: the NCLEX review PDF (renamed).
- Deleted: `facebook-nightconcept.zip` and `misc/` (byte-identical and name-and-size-identical copies are in `Photography/`), the three forex zips, `agatha/checkpoints`, `desktop.ini`.
- Left for the user to review: the two Falling in Love specials and their subtitles. `upload_audiobooks/` stays (LibbyRip).
- The existing `Backups/` entries (`config`, `garnet`, `dietpi`, `events`, `storage-locality-2026-11-01`, `docker-pre-locality-2026-11-01`) were not moved; docs refer to their paths.

**Held, because live users still point at the old paths:**

- `vesper` and `data` → `Projects/`: rotom (running) and foreman archive leases to `host:/mnt/titan/vesper/{lease}` (`~/.config/rotom/config.toml`, `shadow.toml`, `~/.config/foreman/config.toml`). madness defaults its archive to `/mnt/titan/data/madness` (`src/march/cli.py`), and ddd backs up to `/mnt/titan/data/ddd` (`scripts/backup_data.py`). Update those, restart rotom while it holds no lease, then move.
- `Games-Staging` → `Games/_staging`: Edea's `dgl-add-game` skill stages into `/mnt/titan/Games-Staging/{s}/{g}` (`references/bulk-add-batching.md`). Update the skill and dgm first.
- `Books-Unorganized` (empty): Terra's Calibre container mounts it (`modules/linux/programs/books/docker-compose.yml`). Remove the mount and redeploy the books stack, then delete it.

### Phase 5 decisions (2026-11-21)

- The user approved the grouping above.
- `Airman Show` moves into `Music/`.
- `OS` and `vesper` stay on Titan (not deleted). They move to `Software/` and `Projects/`.
- `transfer` stays at the root as the inbox. `transfer/upload_audiobooks` is the LibbyRip converter's upload path. Sort its loose files (59 items from 2018 to 2026: photos, an MP3, a PDF) later.
- `docker/` was checked on 2026-11-21. Nothing uses it:
  - Rinoa's `forgejo`, `forgejo-db`, and `obsidian-livesync` containers mount only `/var/lib/docker-containers/...` on Rinoa (`hosts/nixos/rinoa/default.nix` sets `remoteDataPath` and `dataPath`). No Rinoa systemd unit names `titan/docker`.
  - `docker/forgejo` (5.5 GB, newest file 2026-11-01) and `docker/obsidian-livesync` (82 MB, newest 2026-09-25) are the inactive originals from the plan 003 cutover. Plan 003 copied them with checksums to Rinoa. `Backups/storage-locality-2026-11-01/` also holds a Forgejo tar, a manifest, and a `pg_dump`.
  - `docker/forgejo.new-empty.bak` (9.7 KB, 2025-09-24) is an empty leftover.
  - Rinoa's local Forgejo and CouchDB data have no recurring backup yet (plan 003). Until they do, keep these originals as a fallback: move `docker/` to `Backups/docker-pre-locality-2026-11-01/` and delete `forgejo.new-empty.bak`.
  - The Forgejo and obsidian-livesync modules still default to `/mnt/titan/docker/...`. Rinoa overrides both. Change the defaults when `docker/` moves.

## Open decisions

1. The 48 GB of Lancelot games that are gone from Titan: keep (copy to `Games-Unorganized`) or delete?
2. Back up Emulation (319 GB: ROMs and emulator setups) and transfer (65 GB)? They are close to games and an inbox, so they are excluded by default.
3. Jeanne-only data (Phase 4): move, keep, or delete each folder.
4. Where does Airman Show belong: media or Personal?
5. Approve the Phase 5 layout before any move.
