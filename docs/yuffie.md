# Yuffie: nightly flake update builder

Yuffie is a NixOS VM (VM 100 on Valefor). Each night it updates `flake.lock` to the newest
`nixos-unstable`, builds every gated output and pushes the lock to `main` if all of them pass.
It also serves its Nix store as a binary cache (harmonia), so hosts can download the exact
closures that passed.

- Host config: `hosts/nixos/yuffie/`
- Updater module and script: `modules/nixos/services/flake-updater/`
- Policy tests: `tests/test_flake_updater.py`
- Tidus VM boot test: `tests/nixos/tidus-boot.nix`

## Update policy

| Rule | Value |
|---|---|
| Start time | 00:00 each night. A missed run does not run later in the day. |
| Trigger | `nixos-unstable` has a revision newer than the one in `flake.lock`. |
| Inputs | All inputs (`nix flake update`). |
| Cooldown | 7 days after each push. |
| Retry | A failed run is tried again the next night. |
| Real failure | The same nixpkgs revision fails 2 times: wait for a newer revision. |
| Alert | Gotify (priority 8) for each failed run, from the 3rd failure in a row. |
| Success | Gotify (priority 2). Commit `chore(flake): update inputs to nixos-unstable <rev>`. |
| Kept builds | Build roots for the current and the previous pushed lock. Two boot entries. |

### The gate

All steps must pass before the push:

1. `nix flake check --all-systems --no-build` (evaluates everything, including Darwin checks).
2. `nix fmt -- --check .` (a new formatter version can change the formatting).
3. Evaluate `darwinConfigurations.{waver,merlin}`. Linux cannot build Darwin systems.
4. Build all `checks.x86_64-linux`: the toplevels of tidus, aerith, rinoa, vincent and yuffie,
   and `tidus-boot`.
5. Build `homeConfigurations.{desktop,laptop,server}`.

Each step runs alone, in its own `nix` process, and Nix builds one derivation at a time.
Measured evaluation peaks: about 5 GB for step 1, 1.1–1.5 GB for each host. The
`tidus-boot` VM takes 3 GB and runs last, with nothing else in memory. A run is slow,
but it fits in 6 GB.

`tidus-boot` boots tidus's full module list in a QEMU VM. It checks that `multi-user.target`,
home-manager, Docker and SDDM start and that no unexpected unit fails. The VM has no age key,
so `sops-install-secrets.service` is allowed to fail. Tests cannot check the laptop hardware
(GPU, suspend, firmware, bootloader install).

If `main` changes during a run, the updater rebases, runs the gate again (mostly cached) and
pushes. If `main` changed `flake.lock`, the run fails and the next night starts again.

Forgejo CI and `just check` only evaluate the checks (`--no-build`).

## Operations

```sh
ssh danny@yuffie.local
systemctl list-timers flake-updater           # next run
journalctl -u flake-updater -n 100            # last run
sudo cat /var/lib/flake-updater/state.json    # cooldown and attempt counters
sudo systemctl start flake-updater-dry-run    # update + gate now; no push, no state change
sudo systemctl disable --now flake-updater.timer   # stop nightly updates
```

To force an update before the cooldown ends, delete `state.json`. To revert a bad update,
`git revert` the lock commit on `main`. The next run waits for a newer revision only after
2 failures, so pause the timer if you need time to fix the problem.

## VM settings (Valefor)

Valefor has an Intel N100 (4 cores) and 16 GB RAM. Rinoa runs Traefik, Forgejo and
Vaultwarden on the same node. Yuffie gets a lower CPU share and builds at night only.

| Setting | Yuffie (VM 100) | Rinoa (VM 101) |
|---|---|---|
| Memory | 6144 MB (zram swap) | 8192 MB (uses about 3 GB) |
| CPU | 4 cores, `cpu: host` (nested KVM), `cpuunits: 50` | 4 cores, `cpuunits` default (100) |
| Disk | `local-lvm`, 120 GB, `discard=on,ssd=1,iothread=1` | 200 GB, `discard=on,ssd=1,iothread=1` |
| Nix | `max-jobs = 1`, `cores = 2`, daemon `batch`/`idle` priority | — |

The thin pool `local-lvm` is 349 GB. Without `discard=on`, guest trims do not return space to
the pool. Yuffie's `min-free`/`max-free` start garbage collection during a build when its disk
is low, so the Nix store cannot fill the pool.

## Secrets

`hosts/nixos/yuffie/secrets/secrets.yaml` (recipients: `danny_personal`, `tidus_host`):

| Key | Use | Public part |
|---|---|---|
| `harmonia_sign_key` | Signs the binary cache | `yuffie-1:BJqmV1TUm+Lai5QDAnvRA7wbICPt3nLxzcJARuI8mPM=` |
| `forgejo_deploy_key` | Clones and pushes `nightconcept/dotfiles` | Forgejo deploy key `yuffie-flake-updater`, write access |

The Gotify token is not in SOPS. Vincent creates the `flake-updater` application, and
the token is copied to `/var/lib/flake-updater/gotify.token` (see step 5.4). Without the token
file, the updater logs alerts but does not send them.

A reprovisioned yuffie decrypts the same keys, so the cache public key and the deploy key
stay the same. Yuffie keeps no other state that cannot be rebuilt: when `state.json` is lost,
the cooldown restarts from zero.

## Reprovisioning runbook

Use this runbook for the first install and for any rebuild. **[Claude]** marks steps that
Claude runs over SSH. **[Danny]** marks steps that need the Proxmox console, a web UI or
the personal age key. Claude asks before each destructive step (marked ⚠).

### 1. Preparation

1. **[Claude]** Download and verify the installer ISO on Valefor:
   `local:iso/nixos-minimal-unstable.iso`. Check it against the `.sha256` file next to it.
2. **[Claude]** Confirm `nix eval .#nixosConfigurations.yuffie.config.system.build.toplevel`
   and `nix flake check --all-systems --no-build` pass on the commit to install.
3. **[Danny]** In Forgejo, open `nightconcept/dotfiles` → Settings → Deploy keys. Add the
   `yuffie-flake-updater` public key with **write access**. If `main` is protected, allow
   this deploy key to push.

### 2. Valefor maintenance window

Rinoa is stopped for about one minute. Pick a quiet time.

1. **[Danny]** Confirm that nothing on the old yuffie disk is needed.
2. **[Claude]** ⚠ Resize rinoa and enable discard. A full stop and start applies the change:

   ```sh
   qm set 101 --memory 8192 --scsi0 local-lvm:vm-101-disk-0,iothread=1,size=200G,discard=on,ssd=1
   qm shutdown 101 && qm start 101
   ```

3. **[Claude]** In rinoa, run `sudo fstrim -av`. Check
   `curl -s http://192.168.1.110:3002/health` and the routed services. On Valefor, check
   that `lvs` shows less usage on `pve/data`.
4. **[Claude]** ⚠ Replace yuffie's disk and apply the VM settings:

   ```sh
   qm set 100 --delete scsi0                        # the old disk becomes unused0
   qm disk unlink 100 --idlist unused0 --force      # deletes local-lvm:vm-100-disk-0
   qm set 100 --scsi0 local-lvm:120,discard=on,ssd=1,iothread=1
   qm set 100 --cpu host --cores 4 --cpuunits 50 --memory 6144 --onboot 1
   qm set 100 --ide2 local:iso/nixos-minimal-unstable.iso,media=cdrom --boot 'order=scsi0;ide2'
   ```

   Keep the MAC address (`08:00:27:1F:06:11`), so a DHCP reservation still applies.

### 3. Install

1. **[Claude]** `qm start 100`. The empty disk fails to boot, so the VM boots the ISO.
2. **[Danny]** In the Proxmox console (VM 100 → Console), run `passwd` to set a temporary
   password for the `nixos` user. Run `ip -4 a` and give Claude the address.
3. **[Claude]** Over SSH (`nixos@<ip>`), partition and mount the disk:

   ```sh
   sudo parted -s /dev/sda -- mklabel msdos mkpart primary ext4 1MiB 100%
   sudo mkfs.ext4 -L nixos /dev/sda1
   sudo mount /dev/disk/by-label/nixos /mnt
   ```

4. **[Danny]** Install the personal age key, so that SOPS works at first boot:

   ```sh
   sudo install -d -m 700 /mnt/var/lib/sops-nix
   sudo install -m 600 /dev/stdin /mnt/var/lib/sops-nix/key.txt   # paste key, then Ctrl-D
   ```

5. **[Claude]** Copy the repo to `/mnt/tmp/dotfiles` with rsync, then install:

   ```sh
   sudo nixos-install --flake /mnt/tmp/dotfiles#yuffie --no-root-passwd
   ```

6. **[Claude]** Remove the ISO and reboot:
   `qm set 100 --ide2 none,media=cdrom --boot order=scsi0`, then `qm reboot 100`.

### 4. Verify

**[Claude]** Over SSH (`danny@yuffie.local`):

1. Check that `/run/secrets/yuffie/forgejo_deploy_key` and `/run/secrets/yuffie/harmonia_sign_key`
   exist and that `systemctl --failed` shows no units.
2. Check that `/dev/kvm` exists (nested KVM for `tidus-boot`).
3. Check `curl -s http://localhost:5000/nix-cache-info`.
4. Check the deploy key:
   `sudo -u flake-updater GIT_SSH_COMMAND="ssh -i /run/secrets/yuffie/forgejo_deploy_key -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=/var/lib/flake-updater/known_hosts" git ls-remote ssh://git@192.168.1.110:2222/nightconcept/dotfiles.git HEAD`.
5. Check `systemctl list-timers flake-updater` shows the next run at 00:00.

### 5. First run

1. **[Claude]** In the evening, start `flake-updater-dry-run`. The first run fills an empty
   store, so it can take several hours on the N100.
2. **[Claude]** If `tidus-boot` fails because of a unit that fails only in a VM, add the unit
   to `ALLOWED_FAILURES` in `tests/nixos/tidus-boot.nix` with a reason, and commit.
3. **[Claude]** When the dry run passes, leave the timer on. The next night starts the policy.
4. **[Claude]** After vincent is deployed (it creates the `flake-updater` Gotify application),
   copy the token:

   ```sh
   ssh vincent sudo cat /var/lib/docker-containers/gotify/tokens/flake-updater.token \
     | ssh yuffie.local sudo install -m 600 -o flake-updater -g flake-updater \
       /dev/stdin /var/lib/flake-updater/gotify.token
   ```

### 6. Later: hosts use the cache

Not done yet. Steps:

1. **[Danny]** Add a DHCP reservation for MAC `08:00:27:1F:06:11` on the router and decide on a
   DNS name.
2. **[Claude]** Add `http://<yuffie>:5000` to `nix.settings.substituters` and the public key
   above to `trusted-public-keys` in `modules/nixos/core/nix`. Hosts away from the LAN wait
   `connect-timeout` (5 s) and then use cache.nixos.org.
