# Cloud Windows CI runner

Cloud is the Debian 13 PC, managed through `hosts/linux/cloud/main.py`.
Deploy the complete host from the repository root:

```bash
just cloud
```

The command prompts for sudo, manages Docker Engine from Docker's Debian
repository, builds Forgejo Runner 13.2.0 for Windows from a pinned upstream
commit, and starts a Windows Server 2025 VM using Docker Compose and KVM.
Windows installation continues asynchronously; watch it at
<http://127.0.0.1:8006>. RDP is available on localhost port 3389.
The first automatic login runs provisioning, which then disables automatic login
and removes the image's Windows Update pause settings.
Windows needs an appropriate license for ongoing use.

## Resources and storage

- Four virtual CPUs, 8 GiB RAM, two concurrent jobs.
- A growable 90 GiB qcow2 disk under `/var/lib/cloud-windows-runner`.
- Keep at least 20–30 GiB free on Cloud for Debian, Docker, and image builds.
- Persistent provisioning and credentials live under `/opt/cloud-windows-runner`,
  owned by root with restricted permissions. The administrator password is
  generated once in its `.env`; deployment never prints it.
- The VM container image is pinned by digest. Changing `VERSION` on an existing
  disk does not upgrade or reinstall Windows. Maintain Windows through Windows Update.
- Container recreation and `docker compose down` preserve the guest disk.

## Registration

Open <https://forge.solivan.dev/user/settings/actions/runners> for a runner scoped
to your own repositories. Choose **Create new runner**, name it `cloud-windows`,
and copy its UUID and token. For organization or instance scope, use the respective
organization settings or administrator Actions runner page instead.

After the first deployment creates the provisioning directory, edit:

```bash
sudoedit /opt/cloud-windows-runner/provision/connection.yml
```

Enter the following, substituting the UUID and token displayed by Forgejo:

```yaml
server:
  connections:
    forgejo:
      url: https://forge.solivan.dev
      uuid: YOUR-RUNNER-UUID
      token: YOUR-RUNNER-TOKEN
```

Do not paste tokens into shell commands or commit them. Keep this protected file
for subsequent boots and deployments. Windows' startup task retries every minute
on failure, including while this file is empty. It combines this connection block
with the managed runner configuration inside the VM. Confirm `cloud-windows`
appears online in Forgejo. If upgrading from the old registration-token setup,
rerun `just cloud` and restart the `ForgejoRunner` scheduled task in Windows.

The `ForgejoRunner` scheduled task runs at boot as SYSTEM. Jobs execute inside
the Windows VM with those privileges: use this runner for trusted repositories.
The host provisioning share is read-only to the guest; Docker's socket is not
mounted into Windows. Web console and RDP ports bind only to localhost.

## Workflows and updates

The runner advertises `windows-latest`, `windows-2025`, `self-hosted`, `windows`,
and `x64`, all using the host executor. Git, PowerShell 7, and Node.js LTS are
installed through Chocolatey. Visual Studio, Windows SDKs, .NET SDKs, and other
project-specific tools must be added when required by a workflow. This is not
the complete GitHub-hosted Windows tool image.

Forgejo officially supports and tests its runner on Linux; this Windows build
needs validation against real workflows. Matching GitHub labels does not promise
full GitHub Actions compatibility, including checkout, cache, and artifacts.
The cache server is initially disabled. Existing Linux runners on Vincent are
unaffected.

`just cloud` updates the shared provisioning files and uses Docker's build cache.
Restart the `ForgejoRunner` scheduled task inside Windows, when no job is running,
to load a rebuilt executable or updated configuration. It does not reinstall the OS.

Validation after installation: confirm the runner appears online, run a workflow
with `runs-on: windows-latest` that checks out its repository and executes `pwsh`,
then test an artifact upload/download and a real project build. Reboot Cloud and
confirm the runner returns online. Rerun `just cloud` to verify disk and runner
identity are retained.

Runner daemon logs are written inside Windows to
`C:\ForgejoRunner\runner.err.log` and `C:\ForgejoRunner\runner.out.log`.
Normal informational messages go to stderr. The launcher uses `Start-Process`
with separate log files so Windows PowerShell does not treat those messages as
terminating errors when task output is redirected.

## References

- [Windows VM container and installation hooks](https://github.com/dockur/windows)
- [Forgejo runner source and platform support](https://code.forgejo.org/forgejo/runner)
- [Forgejo runner labels](https://forgejo.org/docs/latest/admin/actions/configuration/)
- [GitHub runner images](https://github.com/actions/runner-images)
