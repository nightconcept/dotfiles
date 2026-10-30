"""Exercise pinned Hermes deployment against real temporary Git checkouts."""

import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

INSTALL = Path(__file__).resolve().parents[1] / "modules/linux/ai/hermes-install.sh"

# A tiny Hermes CLI implements the upstream commands used by the deployment helper.
CLI = """import os, pathlib, sys
home = pathlib.Path(os.environ["HERMES_HOME"])
if sys.argv[1] == "backup":
    target = pathlib.Path(sys.argv[sys.argv.index("--output") + 1])
    target.write_text((home / "state.db").read_text())
elif sys.argv[1] == "gateway":
    unit = pathlib.Path.home() / ".config/systemd/user/hermes-gateway.service"
    unit.parent.mkdir(parents=True, exist_ok=True)
    unit.write_text("fixture unit")
"""

PM_STAGE = """#!/usr/bin/env python3
import os, pathlib, subprocess, sys
repo = pathlib.Path.cwd()
stage = sys.argv[sys.argv.index("--stage") + 1]
with open(os.environ["ACTIONS"], "a") as log:
    log.write(stage + "\\n")
if stage == "python-deps":
    if os.environ.get("FAIL_SYNC"):
        sys.exit(7)
    location = repo / ".hermes"
    location.mkdir(exist_ok=True)
    head = subprocess.check_output(["git", "rev-parse", "HEAD"], text=True).strip()
    (location / "installed").write_text(head)
elif stage == "products":
    binaries = repo / ".hermes/bin"
    binaries.mkdir(parents=True, exist_ok=True)
    launcher = binaries / "hermes"
    launcher.write_text("#!/bin/sh\\nexec " + sys.executable + " -m hermes_cli.main \\"$@\\"\\n")
    launcher.chmod(0o755)
"""

PM_PROBE = """import pathlib, subprocess
def venv_is_current():
    root = pathlib.Path(__file__).resolve().parents[1]
    marker = root / ".hermes/installed"
    head = subprocess.check_output(["git", "-C", str(root), "rev-parse", "HEAD"], text=True).strip()
    return marker.exists() and marker.read_text() == head
"""

SYSTEMCTL = """#!/usr/bin/env python3
import os, pathlib, sys
if "cat" in sys.argv:
    unit = pathlib.Path.home() / ".config/systemd/user/hermes-gateway.service"
    sys.exit(0 if unit.exists() else 1)
with open(os.environ["ACTIONS"], "a") as log:
    log.write("stop\\n")
"""


class HermesInstallTest(unittest.TestCase):
    """Check adoption, repeated deploys, failed upgrades, and state protection."""

    def setUp(self):
        """Create isolated source, state, and command adapters."""
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        root = Path(self.temporary.name)
        self.home = root / "home"
        self.state = self.home / ".hermes"
        self.state.mkdir(parents=True)
        (self.state / "state.db").write_text("existing conversations")
        self.source = root / "upstream"
        self.source.mkdir()
        self.git(self.source, "init", "--quiet")
        self.git(self.source, "config", "user.email", "fixture@example.invalid")
        self.git(self.source, "config", "user.name", "Fixture")
        package = self.source / "hermes_cli"
        package.mkdir()
        (package / "main.py").write_text(CLI)
        (self.source / ".gitignore").write_text("venv/\n.hermes/\n__pycache__/\n")
        scripts = self.source / "scripts"
        scripts.mkdir()
        (scripts / "install.sh").write_text('#!/bin/sh\nexec hermes-pm-stage "$@"\n')
        pm = self.source / "pm"
        pm.mkdir()
        (pm / "__init__.py").write_text(PM_PROBE)
        self.first = self.commit("initial runtime")
        (self.source / "release").write_text("second release")
        self.second = self.commit("next runtime")
        self.repo = self.state / "hermes-agent"
        self.actions = root / "actions"
        binaries = root / "bin"
        binaries.mkdir()
        for name, content in (("hermes-pm-stage", PM_STAGE), ("systemctl", SYSTEMCTL)):
            path = binaries / name
            path.write_text(content.replace("#!/usr/bin/env python3", f"#!{sys.executable}"))
            path.chmod(0o755)
        self.env = {
            **os.environ,
            "HOME": str(self.home),
            "HERMES_HOME": str(self.state),
            "XDG_CONFIG_HOME": str(self.home / ".config"),
            "ACTIONS": str(self.actions),
            "PATH": f"{binaries}:{os.environ['PATH']}",
        }

    def git(self, cwd: Path, *args: str) -> str:
        """Run Git against an isolated checkout."""
        return subprocess.check_output(["git", "-C", str(cwd), *args], text=True).strip()

    def commit(self, message: str) -> str:
        """Commit the fixture source and return its revision."""
        self.git(self.source, "add", ".")
        self.git(self.source, "commit", "--quiet", "-m", message)
        return self.git(self.source, "rev-parse", "HEAD")

    def deploy(self, commit: str, **environment: str) -> subprocess.CompletedProcess[str]:
        """Run the production helper without touching host packages or daemons."""
        return subprocess.run(
            ["bash", str(INSTALL), str(self.repo), str(self.source), commit],
            env={**self.env, **environment},
            text=True,
            capture_output=True,
            check=False,
        )

    def test_fresh_install_then_repeat_does_not_reinstall_or_stop(self):
        """An older exact pin installs from a newer upstream and repeats without changes."""
        first = self.deploy(self.first)
        self.assertEqual(first.returncode, 0, first.stderr)
        self.assertEqual(self.git(self.repo, "rev-parse", "HEAD"), self.first)
        before = self.actions.read_text()
        repeated = self.deploy(self.first)
        self.assertEqual(repeated.returncode, 0, repeated.stderr)
        self.assertEqual(self.actions.read_text(), before)
        self.assertEqual((self.state / "state.db").read_text(), "existing conversations")

    def test_upgrade_backs_up_state_and_changes_only_to_selected_commit(self):
        """A pin bump preserves state and saves its pre-upgrade source revision."""
        self.assertEqual(self.deploy(self.first).returncode, 0)
        result = self.deploy(self.second)
        self.assertEqual(result.returncode, 0, result.stderr)
        backups = list((self.state / "backups/dotfiles").glob("*/state.zip"))
        self.assertEqual(len(backups), 1)
        self.assertEqual(backups[0].read_text(), "existing conversations")
        self.assertEqual(backups[0].with_name("commit").read_text().strip(), self.first)
        self.assertEqual(self.git(self.repo, "rev-parse", "HEAD"), self.second)

    def test_adopts_existing_runtime_once_without_changing_its_revision(self):
        """A pre-existing install gets a backup and marker, then skips repeated setup."""
        self.assertEqual(self.deploy(self.first).returncode, 0)
        (self.state / ".dotfiles-runtime").unlink()
        result = self.deploy(self.first)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.git(self.repo, "rev-parse", "HEAD"), self.first)
        self.assertEqual(len(list((self.state / "backups/dotfiles").glob("*/state.zip"))), 1)
        before = self.actions.read_text()
        self.assertEqual(self.deploy(self.first).returncode, 0)
        self.assertEqual(self.actions.read_text(), before)

    def test_dirty_checkout_is_rejected_even_when_pin_matches(self):
        """Repeated deploys never adopt edited source as the pinned runtime."""
        self.assertEqual(self.deploy(self.first).returncode, 0)
        (self.repo / "hermes_cli/main.py").write_text("local changes")
        before = self.actions.read_text()
        result = self.deploy(self.first)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("local changes", result.stderr)
        self.assertEqual(self.actions.read_text(), before)

    def test_failed_sync_keeps_backup_and_retry_finishes(self):
        """A failed lock sync does not publish readiness or prevent a later retry."""
        self.assertEqual(self.deploy(self.first).returncode, 0)
        marker = self.state / ".dotfiles-runtime"
        previous_marker = marker.read_text()
        failed = self.deploy(self.second, FAIL_SYNC="1")
        self.assertNotEqual(failed.returncode, 0)
        self.assertIn("gateway stays stopped", failed.stderr)
        self.assertEqual(marker.read_text(), previous_marker)
        self.assertTrue((self.state / ".dotfiles-upgrade-backup").exists())
        retried = self.deploy(self.second)
        self.assertEqual(retried.returncode, 0, retried.stderr)
        self.assertNotEqual(marker.read_text(), previous_marker)
        self.assertFalse((self.state / ".dotfiles-upgrade-backup").exists())
        self.assertEqual(len(list((self.state / "backups/dotfiles").glob("*/state.zip"))), 1)

    def test_downgrade_is_rejected_before_stopping_gateway(self):
        """An older pin cannot silently start against newer persistent state."""
        self.assertEqual(self.deploy(self.second).returncode, 0)
        before = self.actions.read_text()
        result = self.deploy(self.first)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Refusing Hermes downgrade", result.stderr)
        self.assertEqual(self.actions.read_text(), before)
        self.assertEqual(self.git(self.repo, "rev-parse", "HEAD"), self.second)


if __name__ == "__main__":
    unittest.main()
