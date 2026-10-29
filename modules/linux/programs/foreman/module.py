"""foreman: the GPU/CPU/RAM lease daemon on terra.

foreman hands out leases of VRAM, cores and RAM, and stops llama-swap (and so Strata) during
the overnight training window. This module installs the pinned build, seeds its config once,
runs it as a user service, and installs the two root-owned pieces it needs: cpuset delegation
for the user manager and a polkit rule that lets danny start and stop llama-swap only.
"""

import io
import os

from pyinfra import host
from pyinfra.facts.server import Command
from pyinfra.operations import files, server, systemd

from modules.linux.module import HostModule

# TODO: the foreman repo has no remote yet. Push it to forge first. FOREMAN_COMMIT is the local
# HEAD when this was written; confirm it is the pushed commit before running `just terra`.
FOREMAN_REPO = "https://forge.solivan.dev/danny/foreman"
FOREMAN_COMMIT = "4be41c9c65e41add757d85c3dc3728e3ffbf27f4"  # PIN

_SEED_CONFIG = os.path.join(os.path.dirname(__file__), "config.toml")

_USER_UNIT = """\
[Unit]
Description=foreman GPU/CPU/RAM lease daemon

[Service]
Type=simple
ExecStart=%h/.local/bin/foreman serve
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
"""

# Takes effect only after user@1000.service restarts, which kills every user unit. Reboot
# terra once after the first deploy; until then foreman logs that cpuset is missing.
_DELEGATE_DROPIN = """\
[Service]
Delegate=cpu cpuset io memory pids
"""

_POLKIT_RULE = """\
// Managed by dotfiles (foreman module).
// Lets {user} start and stop llama-swap.service only. Other units and verbs stay denied.
polkit.addRule(function(action, subject) {{
    if (action.id == "org.freedesktop.systemd1.manage-units" &&
        subject.user == "{user}" &&
        action.lookup("unit") == "llama-swap.service" &&
        (action.lookup("verb") == "start" || action.lookup("verb") == "stop")) {{
        return polkit.Result.YES;
    }}
}});
"""


def gpu_window_open() -> bool:
    """Tells whether foreman reports an open GPU lease window right now.

    While it is open, llama-swap is meant to be down. Deploy steps that would restart or
    probe llama-swap use this to leave it alone. It is False when foreman is missing, not
    running, or in a window without GPU leases.

    Returns:
        True when `foreman status --json` reports `gpu_leases: true`.
    """
    home = os.path.expanduser("~")
    output = host.get_fact(
        Command,
        command=(
            f"{home}/.local/bin/foreman status --json 2>/dev/null | "
            "python3 -c \"import json,sys; print(json.load(sys.stdin).get('gpu_leases') is True)\" "
            "2>/dev/null || echo False"
        ),
    )
    return (output or "").strip().endswith("True")


class ForemanModule(HostModule):
    """Installs the pinned foreman build and runs it as a user service."""

    def __init__(self):
        """Initialize foreman paths."""
        self.user = os.environ.get("USER", "danny")
        self.home = f"/home/{self.user}"
        self.repo_dir = f"{self.home}/git/foreman"
        self.bin_path = f"{self.home}/.local/bin/foreman"
        self.config_path = f"{self.home}/.config/foreman/config.toml"
        self.seed_path = f"{self.home}/.local/share/foreman/config.seed.toml"
        self.unit_path = f"{self.home}/.config/systemd/user/foreman.service"
        self.delegate_path = "/etc/systemd/system/user@.service.d/foreman-delegate.conf"
        self.polkit_path = "/etc/polkit-1/rules.d/50-foreman-llama-swap.rules"

    def install(self):
        """Put the foreman checkout at the pinned commit.

        A missing checkout is cloned. A clean one is moved to the pin. One with local changes
        stops the deploy, so work in progress is never overwritten.
        """
        server.shell(
            name=f"Fetch foreman {FOREMAN_COMMIT[:8]}",
            commands=[
                f"""
                set -eu
                if [ ! -d "{self.repo_dir}/.git" ]; then
                    mkdir -p "$(dirname "{self.repo_dir}")"
                    git clone --quiet "{FOREMAN_REPO}" "{self.repo_dir}"
                fi
                cd "{self.repo_dir}"
                if [ "$(git rev-parse HEAD)" != "{FOREMAN_COMMIT}" ]; then
                    if ! git diff --quiet || ! git diff --cached --quiet; then
                        echo "foreman has local changes; not moving it to {FOREMAN_COMMIT}." >&2
                        exit 1
                    fi
                    git fetch --quiet origin
                    git checkout --quiet "{FOREMAN_COMMIT}"
                fi
                """
            ],
        )

    def update(self):
        """Build foreman with mise and just, then install the binary."""
        server.shell(
            name="Build foreman and install it to ~/.local/bin",
            commands=[
                f"""
                set -eu
                cd "{self.repo_dir}"
                mise trust --quiet
                mise install
                mise exec -- just build
                mkdir -p "$(dirname "{self.bin_path}")"
                install -m 0755 bin/foreman "{self.bin_path}.new"
                mv -f "{self.bin_path}.new" "{self.bin_path}"
                """
            ],
        )

    def service(self):
        """Seed the config, deploy the root-owned pieces and run the user service."""
        # The seed copy is always refreshed. The live config is created only when missing,
        # because the foreman CLI owns it after that.
        files.put(
            name="Deploy foreman seed config",
            src=_SEED_CONFIG,
            dest=self.seed_path,
            mode="644",
        )
        server.shell(
            name="Seed foreman config if it is missing",
            commands=[
                f'test -f "{self.config_path}" || '
                f'install -D -m 644 "{self.seed_path}" "{self.config_path}"'
            ],
        )

        files.put(
            name="Deploy cpuset delegation drop-in for user@.service",
            src=io.StringIO(_DELEGATE_DROPIN),
            dest=self.delegate_path,
            mode="644",
            _sudo=True,
        )
        files.put(
            name="Deploy polkit rule for foreman to start and stop llama-swap",
            src=io.StringIO(_POLKIT_RULE.format(user=self.user)),
            dest=self.polkit_path,
            mode="644",
            _sudo=True,
        )
        # Reload only. Restarting user@.service would kill every user unit.
        systemd.daemon_reload(name="Reload systemd for the delegation drop-in", _sudo=True)

        files.put(
            name="Deploy foreman user unit",
            src=io.StringIO(_USER_UNIT),
            dest=self.unit_path,
            mode="644",
        )
        systemd.service(
            name="Enable and restart foreman",
            service="foreman",
            running=True,
            restarted=True,
            enabled=True,
            daemon_reload=True,
            user_mode=True,
        )

    def remove(self):
        """Stop foreman and remove what this module installed.

        The checkout, the config and the lease state stay, because the CLI owns them.
        """
        systemd.service(
            name="Stop and disable foreman",
            service="foreman",
            running=False,
            enabled=False,
            user_mode=True,
        )
        for path in (self.unit_path, self.bin_path):
            files.file(name=f"Remove {path}", path=path, present=False)
        for path in (self.delegate_path, self.polkit_path):
            files.file(name=f"Remove {path}", path=path, present=False, _sudo=True)
