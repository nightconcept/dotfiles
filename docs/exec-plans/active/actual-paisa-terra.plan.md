# Execution Plan: Actual Budget and Paisa on Terra

Status: active
Last reviewed: 2026-08-20
Owner: danny

**Research:** `docs/exec-plans/active/actual-paisa-terra.research.md`
**Issue/Ref:** Actual Budget and Paisa evaluation on Terra

## Goal

Deploy Actual Budget and Paisa as a Docker Compose stack on Terra. Rinoa's existing Traefik instance will terminate TLS and route `budget.local.solivan.dev` to Actual and `ledger.local.solivan.dev` to Paisa on Terra. The services have separate persisted data. A later conversion layer will reconcile Actual transactions with the Ledger journal used by Paisa.

## Worker Context Bootstrap

1. Read `AGENTS.md`.
2. Read `modules/linux/module.py` and `hosts/linux/terra/main.py`.
3. Read `modules/nixos/services/docker/containers/traefik/config/config.yml`.
4. Read `docs/exec-plans/active/actual-paisa-terra.research.md`.

## Approach

Terra remains the application host and exposes only the two application ports on its LAN address. Rinoa remains the sole HTTPS entry point. Add static Traefik file-provider routers and services on Rinoa that proxy to Terra at ports 5006 and 7500, use the existing `secured` middleware chain, and preserve the original host header.

The Terra stack retains Actual data at `/opt/budget/actual-data`, the Paisa database/configuration at `/opt/budget/paisa-data`, and the Ledger journal at `/opt/budget/ledger`. Paisa mounts the journal read-only. The initial journal is a valid non-personal sample; the WIP Forgejo checkout replaces it only when it is ready.

The later synchronization work is an explicit data-integration project, not an implicit side effect of container deployment. It will first define a canonical transaction interchange record, identity keys, duplicate detection, direction of authority per field, and a reconciliation report. It must not silently implement unrestricted bidirectional writes.

## Public Seams Under Test

1. `just terra` deploys the stack idempotently and both application containers become healthy.
2. Rinoa returns successful HTTPS responses from `budget.local.solivan.dev` and `ledger.local.solivan.dev`.
3. Recreating containers preserves Actual data, Paisa configuration/database, and the journal.
4. Paisa can read its journal but cannot write to the mounted journal directory.

## Phases

### Phase 1: Define the Terra Budget Stack

**Objective:** Create an idempotent pyinfra module for Actual and Paisa.
**Depends on:** none
**Files to change:**

- `modules/linux/programs/budget/module.py` — add `BudgetModule` with persistent-directory setup, Compose deployment, and a non-destructive remove operation.
- `modules/linux/programs/budget/docker-compose.yml` — run Actual on 5006 and Paisa on 7500, each with upstream-compatible health checks and restart policies.
- `modules/linux/programs/budget/paisa.yaml` — configure a read-only Ledger journal path and a separate writable database path.
- `modules/linux/programs/budget/sample.ledger` — provide a minimal valid non-personal journal only for initial evaluation.

**Implementation notes:**

- Use `actualbudget/actual-server:latest` with `/opt/budget/actual-data:/data`.
- Use `ananthakumaran/paisa:latest`; mount `/opt/budget/paisa-data` writable and `/opt/budget/ledger` read-only.
- Bind ports 5006 and 7500 on Terra's LAN address, not ports 80/443. Restrict direct LAN access to Rinoa where the host firewall policy supports it; Traefik is the supported client entry point.
- Seed the sample journal only if the destination is absent. Never overwrite an existing journal, Paisa database, or Actual data.
- Do not commit passwords, user financial data, deploy keys, or Forgejo credentials.

**Verification:**

```bash
uv run ruff check modules/linux/programs/budget
uv run ty check modules/linux/programs/budget
docker compose -f modules/linux/programs/budget/docker-compose.yml config
```

**Status:** [ ] not started

---

### Phase 2: Register the Stack with Terra

**Objective:** Include the new stack in the normal Terra deployment.
**Depends on:** Phase 1
**Files to change:**

- `hosts/linux/terra/main.py` — import, instantiate, and deploy `BudgetModule` after Docker is available.
- `hosts/linux/terra/budget.py` — add a narrow pyinfra entry point for deploying this stack without invoking unrelated Terra modules.

**Implementation notes:**

- Preserve the existing deployment order other than the new call.
- Use `uv run --with pyinfra --with requests pyinfra -y @local hosts/linux/terra/budget.py` for the initial stack rollout. It avoids the unrelated full-host deployment.
- The module's cleanup/removal path may stop containers but must preserve all three persistent directories.

**Verification:**

```bash
uv run ruff check hosts/linux/terra/main.py modules/linux/programs/budget
uv run ty check hosts/linux/terra/main.py modules/linux/programs/budget
uv run --with pyinfra --with requests pyinfra -y @local hosts/linux/terra/budget.py
sudo docker compose -f /opt/budget/docker-compose.yml ps
curl --fail http://192.168.1.111:5006
curl --fail http://192.168.1.111:7500
```

**Status:** [ ] in progress — code is complete; deployment requires interactive sudo.

---

### Phase 3: Add Rinoa Traefik Routes and Health Coverage

**Objective:** Publish the requested local hostnames through Rinoa's existing TLS proxy.
**Depends on:** Phase 2
**Files to change:**

- `modules/nixos/services/docker/containers/traefik/config/config.yml` — add HTTPS routers for the two hostnames and services targeting `http://192.168.1.111:5006` and `http://192.168.1.111:7500`.
- `hosts/nixos/rinoa/default.nix` — add routed health checks for both URLs to the Rinoa container health gate.
- `docs/docker.md` — document access URLs, Rinoa-to-Terra backends, persistent paths, backups, and the future ledger/sync handoff.

**Implementation notes:**

- Use the existing `secured` middleware chain (LAN allowlist plus headers), TLS, and `passHostHeader: true`.
- Do not add DNS records that point the two names at Terra. The existing local domain routing must continue resolving them to Rinoa; verify the local DNS wildcard/records before rollout.
- Treat Rinoa's existing Cloudflare DNS-challenge wildcard certificate as the trusted TLS certificate for both hostnames.
- Do not add CrowdSec unless the routes become internet-facing.

**Verification:**

```bash
sudo nixos-rebuild build --flake .#rinoa
curl --fail https://budget.local.solivan.dev/
curl --fail https://ledger.local.solivan.dev/
```

**Status:** [ ] in progress — route configuration is complete; deploy after Terra is healthy.

---

### Phase 4: Adopt the Forgejo Ledger Repository

**Objective:** Replace the sample journal with a read-only checkout of `nightconcept/ledger` when the repository becomes usable.
**Depends on:** Phase 3 and an approved read-only Forgejo credential
**Files to change:**

- `modules/linux/programs/budget/module.py` — add an explicit opt-in checkout/update flow with the repository layout supplied as configuration.
- `modules/linux/programs/budget/paisa.yaml` — point `journal_path` at the repository journal entry point.
- `docs/docker.md` — document authentication, updating, rollback, and backups.

**Implementation notes:**

- Keep Paisa's writable state outside the checkout.
- Validate the Ledger journal before switching Paisa to it.
- Use a deploy key or token provisioned outside the repository; no secret may be rendered into source-controlled files.

**Verification:**

```bash
sudo -u danny git -C /opt/budget/ledger status --short
sudo docker compose -f /opt/budget/docker-compose.yml exec paisa paisa status
sudo docker compose -f /opt/budget/docker-compose.yml exec paisa sh -c 'test ! -w /root/Documents/paisa/journal'
```

**Status:** [ ] not started

---

### Phase 5: Define and Build Transaction Reconciliation

**Objective:** Make Actual and the Ledger journal match through reviewed, auditable conversion scripts.
**Depends on:** Phase 4 and an agreed transaction contract
**Files to change:**

- `modules/linux/programs/budget/sync/` — new conversion and reconciliation scripts plus fixtures.
- `modules/linux/programs/budget/sync/README.md` — document the canonical mapping, dry-run workflow, conflict policy, and recovery process.
- `modules/linux/programs/budget/docker-compose.yml` — add no scheduled writer until dry-run reconciliation has been accepted.

**Implementation notes:**

- Begin read-only: export data from both sides and produce a discrepancy report before introducing any writes.
- Define stable identity keys, account/category mappings, splits, transfers, scheduled transactions, deleted records, currency/precision rules, and time-zone handling.
- Make every write idempotent and preserve source IDs in metadata. Require dry-run output and backup before writes.
- Choose field-level authority and conflict policy explicitly; if both sides changed since the last synchronization, report the conflict rather than overwrite either record.
- Add one-direction-at-a-time importers and parity tests before considering bidirectional operation.

**Verification:**

```bash
uv run pytest modules/linux/programs/budget/sync
uv run python -m modules.linux.programs.budget.sync.reconcile --dry-run
```

**Status:** [ ] not started

## Testing Strategy

Use static Python checks and Compose rendering before deployment. Validate the public seams through Docker health checks, direct Terra checks, and routed HTTPS checks through Rinoa. The synchronization phase adds fixture-based tests for mapping, idempotence, conflicts, and dry-run reconciliation; it must never require real financial data in tests.

## Rollout / Integration Notes

Deploy Terra first, then apply Rinoa. Local DNS must resolve both names to Rinoa, whose existing certificate covers `*.local.solivan.dev`. Back up all three `/opt/budget` directories before upgrades. Keep Watchtower disabled for these containers until restore and reconciliation procedures are proven.

## Known Risks

- The recorded Terra address, `192.168.1.111`, must be confirmed before Rinoa routes are applied.
- Directly published Docker ports can bypass host firewall conventions; validate that only Rinoa can reach them if stronger LAN isolation is required.
- Actual and Paisa have different data models. Duplicate and conflict behavior must be designed and tested before any converter writes data.
- The ledger repository is WIP and may not have a stable layout or credential path.

## Out of Scope

- Public `budget.solivan.dev` or `ledger.solivan.dev` exposure.
- Caddy, a new proxy, or TLS termination on Terra.
- Immediate data migration or bidirectional synchronization.
- Committing financial data, passwords, deployment credentials, or application databases.

## Progress Log

- 2026-08-20: Revised for Rinoa-to-Terra Traefik routing and a future explicit reconciliation layer.
- 2026-08-20: Phases 1–3 implementation completed. Ruff, ty, Compose rendering,
  and Traefik YAML parsing pass. The targeted Terra deployment is awaiting an
  interactive sudo credential; Pi-hole records and Rinoa deployment are still
  required before endpoint acceptance checks can run.
