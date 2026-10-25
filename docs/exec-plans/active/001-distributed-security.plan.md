# Execution Plan: Distributed security on existing VMs

**ID:** 001
**Created:** 2026-10-25
**Status:** in progress — package built and tested; production activation and capture feeds pending
**Research:** [Repository and live-state evidence](001-distributed-security.research.md)
**Issue/Ref:** User request for a simple Nix-enabled security package on Vincent and Rinoa.

## Goal and current state

Reuse Vincent for central EveBox/Wazuh analysis and a local Suricata sensor. Rinoa runs a remote sensor and retains independent CrowdSec protection for Traefik. Gotify stays separate on Vincent. Add mirrored feeds through one-time Proxmox settings, documented in `docs/network.md`; create no new VMs or hypervisor security applications.

**Built:** shared central/sensor Nix module, Suricata/EveBox/Wazuh services, authenticated remote forwarding, notification bridge, enrollment exports, and retention maintenance. Ten unit tests run in the Nix package build. Isolated distributed integration checks passed on Terra.
**Pending:** production activation, capture NICs, one-time Proxmox mirrors, and router/switch feeds.
**Live:** Vincent has six healthy security containers. Rinoa has the new system configuration and installed enrollment files; its sensor restart is pending. CrowdSec reads Traefik access logs and its bouncer is active. Both Proxmox hosts have no configured capture feeds.

## Worker context bootstrap

Read `AGENTS.md`, `docs/architecture.md`, `docs/bootstrap.md`, `docs/security.md`, `docs/network.md`, `docs/docker.md`, and the research above.
Read `hosts/CLAUDE.md`, `modules/CLAUDE.md`, `modules/nixos/services/docker/CLAUDE.md`, and the Traefik `CLAUDE.md` before changing their areas.
Inspect the existing Suricata prototype, Docker imports/health checker, both guest host files, and CrowdSec changes.
Preserve unrelated dirty changes in `modules/linux/programs/model_catalog.py` and `modules/linux/programs/strata/module.py`.

## Approach and final Nix configuration

Use the existing systemd/Compose/SOPS conventions. One managed stack per guest contains its selected services, with separate persistent volumes. Suricata is passive; Wazuh active response is disabled. Wazuh agents initially collect Suricata EVE only.

Implemented host declarations, initially monitoring `ens18`:

```nix
# hosts/nixos/vincent/default.nix
modules.nixos.docker.containers.security-stack = {
  enable = true;
  role = "central";
  sensors = [ "rinoa" ];
  interfaces = [ "ens18" ];
};
# hosts/nixos/rinoa/default.nix
modules.nixos.docker.containers.security-stack = {
  enable = true;
  role = "sensor";
  interfaces = [ "ens18" ];
  serverAddress = "192.168.1.185";
};
```

`role` accepts `central` or `sensor`; `interfaces` must be nonempty; `serverAddress` defaults to `192.168.1.185`. Extend interfaces only after capture NIC isolation is verified. These declarations are present in the repository and deployed guest configurations.

## Phase 1: Central package and local detection

**Depends on:** none. **Status:** package complete; Terra integration passed.

**Files:** introduce `modules/nixos/services/docker/containers/security-stack/{default.nix,compose.central.yml,evebox.yaml}` and pinned upstream Wazuh configuration under `security-stack/wazuh/`; move/reuse the bridge and its unittest; replace the prototype import in `modules/nixos/services/docker/default.nix`. Add central-role selection to Vincent's host file and required SOPS declarations. Retain the existing encrypted Gotify token where practical.

Implement the option contract, one systemd-managed Compose project, persistent component volumes, rule maintenance, rotation, and readiness. Central includes Suricata, EveBox, Wazuh manager/indexer/dashboard, and notification bridge. Reuse [official single-node Wazuh configuration](https://documentation.wazuh.com/current/deployment-options/docker/wazuh-container.html), pin compatible images, and bootstrap certificates once without replacing them at restart. Vincent's `vm.max_map_count` is already 1048576, above Wazuh's 262144 minimum; preserve the higher value.

Generate unique credentials; store runtime secrets/certificates outside the Nix store, with encrypted source secrets using the personal SOPS recipient. Remove sample users/passwords. Keep indexer and manager APIs private; restrict dashboard/ingestion exposure to the necessary trusted paths. Set explicit event/log retention within Vincent's approximately 58 GiB free disk, leaving space for current services. Do not enable new public routes.

Add proposed `security-stack/test_roles.py` for role selection, invalid interface lists, volume/port boundaries, and absence of active response. Add proposed opt-in `security-stack/test_integration.py`: use an isolated Terra Compose project with local test credentials, controlled ICMP packet replay and rule, then assert EVE detection, EveBox storage, Wazuh alert ingestion, and mock Gotify receipt. Fixtures belong under `security-stack/fixtures/`; never substitute production secrets into test fixtures.

**Verification** (new test files are created in this phase; integration command runs on Terra from the staged checkout):

```sh
python3 -m unittest discover -s modules/nixos/services/docker/containers/security-stack -p 'test_*.py'
nix eval --raw 'path:.#nixosConfigurations.vincent.config.system.build.toplevel.drvPath'
nix eval --raw 'path:.#nixosConfigurations.rinoa.config.system.build.toplevel.drvPath'
ssh terra 'cd /tmp/distributed-security-test && docker compose --env-file fixtures/central.env -f compose.central.yml config --quiet'
ssh terra 'cd /tmp/distributed-security-test && SECURITY_INTEGRATION=central python3 -m unittest test_integration'
```

Stage only package/test files to `/tmp/distributed-security-test` on Terra. The integration test owns and removes its test project and volumes. Confirm persistence by restarting that project before cleanup.
**Rollback:** revert the package/import/host declaration; remove only test-owned Terra resources. No production switch in this phase.

## Phase 2: Remote sensor and proxy separation

**Depends on:** Phase 1. **Status:** sensor package complete; Terra integration passed. Production CrowdSec attribution and access checks remain pending.

**Files:** add `security-stack/compose.sensor.yml`, EveBox agent and Wazuh agent configuration; extend `default.nix`, `test_roles.py`, `test_integration.py`, fixtures, and Rinoa's host selection. Update the existing CrowdSec/Traefik files only for already identified log-volume, bouncer registration, trusted-range, and client-attribution fixes.

Sensor includes Suricata, authenticated EveBox forwarding, a Wazuh agent reading local EVE, and the notification bridge. Assign unique stable sensor identities, credentials, registration state, and persisted cursors. Central collects its own EVE without duplicate forwarding. Verify outage/reconnect, restart, rotation, retries, and bounded buffering. Do not grant guest filesystem access or imply full guest monitoring.

Keep CrowdSec outside the security-stack lifecycle. Preserve LAN and Headscale IPv4/IPv6 access, and validate Cloudflare client attribution without unrestricted forwarded-header trust. Test bans only against an isolated synthetic IP and temporary project; never ban a real management/VPN address.

**Verification** (extend the Phase 1 integration harness for two roles and isolated CrowdSec checks):

```sh
python3 -m unittest discover -s modules/nixos/services/docker/containers/security-stack -p 'test_*.py'
nix eval --raw 'path:.#nixosConfigurations.vincent.config.system.build.toplevel.drvPath'
nix eval --raw 'path:.#nixosConfigurations.rinoa.config.system.build.toplevel.drvPath'
ssh terra 'cd /tmp/distributed-security-test && docker compose --env-file fixtures/sensor.env -f compose.sensor.yml config --quiet'
ssh terra 'cd /tmp/distributed-security-test && SECURITY_INTEGRATION=distributed python3 -m unittest test_integration'
```

The integration test must prove Rinoa-identity alerts reach both central stores after restart/disconnection and produce one expected notification. It must prove the isolated banned IP is blocked while LAN/VPN test identities remain allowed.
**Rollback:** remove sensor selection and sensor-owned test resources; preserve central data and current production CrowdSec.

## Phase 3: One-time Proxmox networking, documented

**Depends on:** Phases 1–2 test successfully. **Status:** not started.

**Files:** `docs/network.md` records exact applied VM NIC IDs/MACs, guest interface names, bridge/tap targets, source hooks, filter priorities/handles, persistence settings, backup locations, validation results, and owned rollback commands. Guest Nix files configure the added NICs without addresses/routes/DHCP; security-stack interface lists gain those NICs only after isolation tests pass.

Apply native settings once over existing root SSH. Do not create Proxmox Nix/pyinfra modules, a provisioning framework, or deployment entrypoints. Preserve existing bridge membership, management NICs/IPs/routes, and all three Locke physical ports. No PCI passthrough, new VMs, or security software on Proxmox.

Snapshot `qm config`, bridge/firewall topology, and all existing `tc` rules before edits. Allocate an unused additional capture NIC for Vincent VM 104 and Rinoa VM 101. Create capture links disconnected initially; activate them only after guest Nix configuration disables DHCP and routing on those interfaces. Use an isolated capture path with no guest egress into production, forwarding, DHCP, addresses, or default route. Select physical and guest source ports to include same-hypervisor traffic; account for Proxmox firewall bridge paths.

Use `tc mirred ... mirror`, never redirect. Cover both directions once, exclude capture destinations, avoid duplicate feeds/loops, and preserve unrelated qdiscs/filters. Native host persistence must reattach owned filters when VM taps are recreated and restore them after boot; record those one-time host settings and exact removal commands. Stop if source/destination ownership cannot be established safely.

**Verification** (replace placeholders in the documentation with actual chosen values before applying; baseline commands are runnable now):

```sh
ssh root@192.168.1.188 'qm config 104; ip -br link; bridge link; tc qdisc show'
ssh root@192.168.1.119 'qm config 101; ip -br link; bridge link; tc qdisc show'
ssh vincent 'ip -br address; ip route; ip -6 route'
ssh rinoa 'ip -br address; ip route; ip -6 route'
ssh root@192.168.1.188 'tc -s filter show dev enp5s0 ingress; tc -s filter show dev enp5s0 egress'
ssh root@192.168.1.119 'tc -s filter show dev enp1s0 ingress; tc -s filter show dev enp1s0 egress'
```

Record corresponding counters for Locke's `enp6s0f0`, `enp6s0f1`, and selected guest ports. Use bounded packet capture on the selected guest capture NICs to prove bidirectional physical/guest feeds and no duplicate sensor feed. Verify addresslessness and blocked capture egress explicitly.
Test tap recreation and mirror reattachment on isolated temporary interfaces first, and inspect persistent host settings. Do not stop production VMs or reboot working hypervisors merely for verification. Observe production stop/start and boot persistence during normal maintenance; record any unperformed guest-stop/reboot checks as **not proven**, without blocking the initial safe rollout.
**Rollback:** remove only owned filters/persistence settings/capture NICs using documented commands; restore guest interface selections. Do not flush shared networking or remove unrelated qdiscs.

## Phase 4: Named-host deployment and acceptance

**Depends on:** preceding checks; interactive sudo on both NixOS guests; capture verification for wider-coverage claims. **Status:** not started.

**Files:** Vincent/Rinoa health-check expectations and central UI routes; `docs/{security,docker,network}.md` status, coverage, rollback and operator commands. Extend tests only for newly uncovered failures.

Build and stage complete host configurations, deploy Vincent before Rinoa, then apply validated capture-interface selections. First activate guest configuration that leaves capture interfaces unnumbered and unmanaged by DHCP. Then enable the isolated Proxmox capture links and prove their feeds before adding them to the sensor selection. Existing sudo authentication is required; root SSH to Proxmox does not imply guest root access. Use the normal full named-host rebuild, not a one-off service deployment. Never activate the obsolete Rinoa staging snapshot.

**Verification** (from the reviewed repository checkout on each named guest):

```sh
sudo nixos-rebuild build --flake 'path:.#vincent'
sudo nixos-rebuild switch --flake 'path:.#vincent'
sudo systemctl status docker-container-security-stack.service --no-pager
docker compose -f /var/lib/docker-containers/security-stack/docker-compose.yml ps
```

Repeat build/switch/status on Rinoa using `path:.#rinoa`. The module must stage the selected Compose file at the runtime path above. Run named-host readiness checks and the following external regression probes:

```sh
curl --fail --silent --output /dev/null https://qbittorrent.local.solivan.dev/
curl --fail --silent --output /dev/null https://forge.local.solivan.dev/api/healthz
ssh barrett 'nordvpn status; ip route; ip rule'
ssh rinoa 'findmnt /mnt/titan'
ssh rinoa 'docker exec crowdsec cscli metrics show acquisition; docker exec crowdsec cscli bouncers list'
```

Generate a controlled local test-rule alert from each sensor and a mirrored guest path; verify the sensor identity in EveBox/Wazuh and one Gotify message. Stop/start sensor stacks and confirm LAN/Headscale SSH, qBittorrent UI, NordVPN internet egress, storage, and reverse-proxy access survive. Check from an actual Headscale client; a LAN-only probe does not prove VPN access. Confirm remote stores/cursors survive restart and retention remains bounded.
**Rollback:** previous NixOS generations plus Phase 3 owned mirror rollback; preserve event volumes, certificates, and credentials. Do not use `compose down -v` on production.

## Acceptance, limits, and progress

Initial rollout requires role/config tests, Terra rendered Compose and detection-to-analysis tests, both full guest builds/deployments, working distributed alerts, inspected persistent feed settings, isolated lifecycle tests, and access regression checks. Document every unobserved production lifecycle check as not proven.
Publish a coverage matrix for guest-local, same-hypervisor guest, inter-host, and mirrored physical-port traffic, with observed test evidence for each path.

Risks: Vincent's storage is shared and limited; capture can saturate resources; incorrect mirror direction/egress can disrupt networking; Cloudflare attribution remains unproven; guest activation requires sudo authentication.
Out of scope: new VMs, Proxmox security agents, Proxmox deployment modules, full guest endpoint monitoring, Wazuh automatic banning, TLS/VPN decryption, and changes to unrelated LLM modules.
Terra-to-internet and other paths bypassing these hypervisors remain blind spots. Whole-LAN coverage needs an additional router/switch feed; SSH to the gateway currently refuses connections.

- 2026-10-25: Research and plan recorded. Research recorded; one-time Proxmox settings follow the user's direction.

- 2026-10-25: Built the central/sensor runtime package. Reused one base Compose file plus pinned upstream Wazuh configuration, rather than separate duplicated role files. Added ten focused unit tests. Both full host configurations evaluate. Terra integration used isolated temporary projects rather than a permanent deployment harness: both sensor identities reached EveBox, Wazuh indexing, and the test notification receiver. Forwarder restart replay, fresh authentication, credential/certificate persistence, health, and maintenance passed. See [the enablement runbook](../../security.md). Production and mirror phases remain pending; Cloudflare attribution and live Headscale access are not proven.

- 2026-10-25: Verified Vincent's six security containers and maintenance timer are healthy/active. EveBox HTTPS and the CA-verified Wazuh dashboard return HTTP 200. Rinoa's initial sensor startup lacked enrollment files; installed them securely and requested an authenticated service restart. CrowdSec Traefik acquisition and bouncer activity are confirmed. Barrett NordVPN remains connected and qBittorrent returns HTTP 200.
