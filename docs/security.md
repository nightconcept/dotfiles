# Distributed security stack

The shared Nix module manages Suricata, EveBox, Wazuh, and a Gotify notification bridge.
It reuses Vincent and Rinoa. Gotify and CrowdSec have separate lifecycles.
No security application runs on a Proxmox host.

## Current state

The package is implemented and tested on Terra. Both host declarations enable it on future rebuilds.
Vincent is active with six healthy containers. Rinoa has the new configuration and enrollment files; its service restart is pending.
Proxmox traffic mirrors are pending.
The superseded Rinoa prototype snapshot must not be activated.

| Host | Role | Services |
|---|---|---|
| Vincent, `192.168.1.185`, Locke VM 104 | Central | Suricata, EveBox, Wazuh manager/indexer/dashboard, notification bridge |
| Rinoa, `192.168.1.110`, Valefor VM 101 | Sensor | Suricata, EveBox forwarder, Wazuh agent, notification bridge |

Each sensor initially monitors its own `ens18` interface.
Wazuh collects Suricata EVE records. Full guest filesystem and system-log monitoring requires additional agent configuration.
CrowdSec protects selected Traefik routes on Rinoa. It remains outside this package.
Suricata is passive. Wazuh active response is disabled. Neither changes VPN routing or blocks traffic.

## Nix configuration

The Docker module imports `containers/security-stack/default.nix`.
Vincent already selects this configuration:

```nix
modules.nixos.docker.containers.security-stack = {
  enable = true;
  role = "central";
  interfaces = [ "ens18" ];
  sensors = [ "rinoa" ];
};
```

Rinoa already selects this configuration:

```nix
modules.nixos.docker.containers.security-stack = {
  enable = true;
  role = "sensor";
  interfaces = [ "ens18" ];
  serverAddress = "192.168.1.185";
};
```

The default retention is three days. The module generates credentials and certificates at first startup.
These files stay outside the Nix store. The Gotify token comes from encrypted `modules/nixos/security/sops/suricata.yaml`.
Both guests need their existing SOPS age identity available at activation.

## Enable Vincent first

Use the updated repository checkout on Vincent. Guest activation requires interactive sudo authentication.
A package build does not replace the full host rebuild.

```sh
sudo nixos-rebuild build --flake 'path:.#vincent'
sudo nixos-rebuild switch --flake 'path:.#vincent'
sudo systemctl status docker-container-security-stack.service --no-pager
sudo docker compose --project-directory /var/lib/docker-containers/security-stack ps
```

The first startup downloads container images and can take several minutes.
The runtime directory is `/var/lib/docker-containers/security-stack`, owned by root with mode `0700`.
Vincent exports Rinoa's enrollment files under `enrollment/rinoa/`.

## Copy Rinoa's enrollment files once

Run these commands from your normal SSH account on Vincent.
The temporary archive contains credentials. Keep its permissions private.

```sh
umask 077
enrollment_archive=$(mktemp /tmp/rinoa-security.XXXXXX)
sudo tar -C /var/lib/docker-containers/security-stack/enrollment/rinoa -czf "$enrollment_archive" .
sudo chown "$(id -u):$(id -g)" "$enrollment_archive"
scp "$enrollment_archive" rinoa:/home/danny/rinoa-security-enrollment.tar.gz
rm "$enrollment_archive"
ssh -t rinoa
```

Then run these commands on Rinoa:

```sh
sudo install -d -m 0700 /var/lib/docker-containers/security-stack/enrollment
sudo tar -xzf /home/danny/rinoa-security-enrollment.tar.gz -C /var/lib/docker-containers/security-stack/enrollment
sudo chown -R root:root /var/lib/docker-containers/security-stack/enrollment
sudo chmod 0600 /var/lib/docker-containers/security-stack/enrollment/evebox.key /var/lib/docker-containers/security-stack/enrollment/wazuh.password
rm /home/danny/rinoa-security-enrollment.tar.gz
```

The module makes the public CA certificate readable by the Wazuh agent.
It preserves the EveBox key, enrollment password, and agent state across restarts.

## Enable the proxy route and Rinoa

Add a Pi-hole DNS record: `evebox.local.solivan.dev` → `192.168.1.110`.
The Rinoa configuration includes an authenticated EveBox route through Traefik's existing HTTPS and trusted-client middleware.
The sensor uses that HTTPS route to send events to Vincent.

From the updated repository checkout on Rinoa:

```sh
sudo nixos-rebuild build --flake 'path:.#rinoa'
sudo nixos-rebuild switch --flake 'path:.#rinoa'
sudo systemctl status docker-container-security-stack.service --no-pager
sudo docker compose --project-directory /var/lib/docker-containers/security-stack ps
sudo docker exec crowdsec cscli metrics show acquisition
```

This full rebuild applies the CrowdSec log-volume and trusted-network fixes.
Live checks on Rinoa show Traefik log acquisition and an active bouncer.
It preserves separate CrowdSec operation for Traefik. Cloudflare client attribution still needs a production check.
See [CrowdSec configuration](docker.md#crowdsec-on-rinoa).

| Interface | Address | Login |
|---|---|---|
| EveBox | `https://evebox.local.solivan.dev` | `admin`, `EVEBOX_PASSWORD` |
| Wazuh dashboard | `https://192.168.1.185:5601` | `admin`, `INDEXER_PASSWORD` |

Read the passwords privately with `sudoedit /var/lib/docker-containers/security-stack/credentials.json` on Vincent.
Do not copy credentials into tickets, command arguments, or logs.
The Wazuh dashboard uses the package's private CA. Import `enrollment/root-ca.pem` into the appropriate client trust store.
Wazuh agent transport and enrollment use ports 1514 and 1515 on Vincent's LAN address.
The indexer and manager API remain inside the Docker network.
EveBox's backend port 5636 listens on Vincent's trusted LAN address behind Traefik.

## Add network coverage later

No capture NIC or traffic mirror has been configured on Locke or Valefor.
The initial sensors cover their own VMs. They do not cover the whole network.

Proxmox configuration consists of one-time native networking settings, recorded in [the network runbook](network.md#one-time-proxmox-capture-setup).
No Proxmox Nix module, pyinfra service, new VM, or hypervisor security application is needed.
Each existing sensor VM receives an additional isolated virtual NIC for packet copies.
Preserve its management NIC, address, and default route.

After a capture NIC and its isolation are verified, extend that guest's declaration:

```nix
interfaces = [ "ens18" "ens19" ];
captureInterfaces = [ "ens19" ];
```

Use the actual guest interface name. The module disables DHCP, IPv6, and forwarding on declared capture interfaces.
It refuses to isolate an interface that carries a default route.
Proxmox must also prevent capture-NIC egress into production.

Locke needs feeds from `enp5s0`, `enp6s0f0`, `enp6s0f1`, and relevant guest paths.
Valefor needs feeds from `enp1s0` and relevant guest paths.
Physical-port capture alone misses guest traffic that stays inside a virtual bridge.
Promiscuous mode alone does not deliver other clients' packets to a VM.
NIC passthrough would remove an existing port from its bridge; all current wired ports are in use.

Traffic that bypasses both hypervisors needs a router or switch mirror feed.
That includes ordinary client internet traffic and some LAN or Wi-Fi traffic.
Encrypted HTTPS and VPN payloads remain encrypted.

## Operations and storage

Each host manages its selected services through `docker-container-security-stack.service`.
Stopping the unit preserves named volumes. Never use `docker compose down -v` on production.

An hourly timer rotates Suricata logs and expires old Wazuh events. It updates Suricata rules at most once daily.
EveBox targets three days and 4 GB of events by default.
Wazuh removes dated alert/archive indices after three days, or earlier above a 10 GiB budget.
The current day's index is preserved, so this budget is not a hard disk limit.
Suricata logs rotate daily or above 128 MB, with eight rotated files; the timer checks them hourly.
Vincent shares its disk with existing services and runners. Check free space during initial operation.

Back up the private runtime directory and persistent Docker volumes together.
Preserve `credentials.json`, CA private key, certificates, sensor enrollment files, and both agent cursors.
Restoring only the configuration without databases can lose enrolled identities.
Leaf certificates last 825 days. Renewal requires operator maintenance before expiry; startup preserves existing certificates.
The EveBox bootstrap follows its pinned 0.31.0 SQLite schema and needs review before an EveBox upgrade.

The notification bridge retries failed Gotify requests and keeps its cursor on disk.
Agent forwarding positions also persist. Retention can remove old events during an extended outage.
Do not run `docker compose config` in shared logs: it expands runtime credentials.
Use `docker compose config --quiet` for configuration checks.

To roll back activation, select the previous NixOS generation on that guest.
Keep the runtime directory and Docker volumes for recovery.

## Verification evidence

Terra ran isolated central and sensor projects using the package's pinned images.
A controlled ICMP alert reached EveBox, Wazuh's searchable index, and the test Gotify receiver from both sensor identities.
Events written while forwarders were stopped reached both central stores after restart.
A central restart preserved credentials, CA identity, sensor keys, and stored events.
Fresh EveBox initialization accepted the generated password and rejected an incorrect password.
Rule updates, log rotation, enrollment with CA verification, container health, and retention maintenance were exercised.

The Nix runtime package runs ten unit tests during its build.
The full Vincent and Rinoa configurations evaluate successfully.
Production checks on 2026-10-25 found Vincent healthy, EveBox HTTPS responding, and the Wazuh dashboard responding with CA verification.
Rinoa initially failed because enrollment files were missing. The files were securely installed; its service restart is pending.
CrowdSec reads Traefik access logs. Barrett retains its NordVPN connection and LAN route, and the qBittorrent proxy returns HTTP 200.
Actual Headscale access, Cloudflare client attribution, and wider capture feeds remain unverified.
