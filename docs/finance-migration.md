# Finance migration from Terra to Rinoa

Status: complete. Finance applications and scheduled jobs reside on Rinoa.

The migration preserves the existing application versions, data, and HTTPS names.
The Rinoa containers publish no host ports.
The model API and agent account remain unchanged.

The final stopped-container copy passed file-content and symlink checks on 2026-10-30.
The Ledger checkout also matches, including uncommitted and untracked files.
Runtime caches are excluded from the checkout copy.
Private final backups exist on both hosts under `.local/state/dotfiles-finance-migration/final-20261030T191819Z`.
The Terra timers are disabled. The old finance containers are stopped.

Rinoa has the pinned hledger 1.52.1 installation under `.local/share/mise/installs/github-simonmichael-hledger/1.52.1`.
The Nix services provide mise, Python, SOPS, and ssh-to-age.
The pinned just and lefthook installations also exist on Rinoa for the copied Git hooks.
The Ledger Python dependencies import successfully on Rinoa.
The existing category-alias error still requires a separate financial mapping decision.

Both finance containers report healthy. Both HTTPS routes respond successfully.
Actual accepts the existing password and lists the original budget file.
Paisa's database matches the stopped Terra snapshot and can read the migrated journal.
Neither host accepts connections on ports 5006 or 7500.
Both timers are active on Rinoa and disabled on Terra.
The final scheduled-job definitions use mise for the pinned Git-hook tools.
Rinoa's readiness checks pass with no failed units or unhealthy containers.

## Before activation

1. Build the full Rinoa configuration from the updated checkout.
2. Copy the Ledger checkout to Rinoa, including its private data and Git metadata.
3. Stop both Ledger timers on Terra.
4. Stop Actual Budget and Paisa on Terra.
5. Copy both stopped containers' data to private backup archives.
6. Copy the data to the matching paths on Rinoa.
7. Compare the source and destination file hashes.

Do not initialize an empty Actual server on Rinoa.
Do not run both copies after the proxy changes.

## Activate Rinoa

From the updated checkout on Rinoa, run:

```sh
sudo nixos-rebuild switch --flake 'path:.#rinoa'
```

This command deploys the full host.
The migration does not add a separate deployment entrypoint.

## Checks after activation

- Both finance containers report healthy.
- Both HTTPS URLs respond with valid TLS.
- Actual accepts the existing password and lists the existing budget files.
- Paisa opens the existing journal.
- Neither host accepts connections on ports 5006 or 7500.
- Rinoa enables both Ledger timers. Terra disables both timers.
- Existing containers retain their previous health status.

Keep the stopped finance containers, source data, and private backup archives on Terra for recovery.
Do not restart the old containers while Rinoa serves the finance applications.

## Recovery

If activation fails before new writes, stop the finance service on Rinoa.
Restore the previous Rinoa generation and its proxy routes.
Start the original containers and timers on Terra.

If Rinoa received new writes, preserve its data before recovery.
An old Terra database will not contain those writes.
