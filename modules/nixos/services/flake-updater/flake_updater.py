"""Nightly flake.lock updater: build every gated output, then push the lock to main.

Policy (see docs/yuffie.md):
- Run only when nixos-unstable has a revision newer than the one in flake.lock.
- After a push, wait a cooldown period (7 days) before the next update.
- A failed run is retried the next night. When the same nixpkgs revision fails
  max_attempts times, wait for a newer nixos-unstable revision.
- Send a Gotify alert once alert_after consecutive runs have failed.
- Keep build roots for the current and the previous pushed lock only.

--no-push runs the update and gate immediately and changes nothing else; use it to
validate a new or reprovisioned yuffie.
"""

import argparse
import dataclasses
import json
import os
import shutil
import subprocess
import sys
import time
import urllib.parse
import urllib.request
from pathlib import Path

NIXPKGS_URL = "https://github.com/NixOS/nixpkgs"
UNSTABLE_REF = "refs/heads/nixos-unstable"
DAY = 24 * 60 * 60


class GateError(Exception):
    """A build or check step failed."""


@dataclasses.dataclass
class State:
    """Updater state kept between runs.

    Attributes:
        last_push: Epoch seconds of the last successful push, or None.
        attempts: Failed attempts per nixpkgs revision.
        consecutive_failures: Failed runs since the last success.
    """

    last_push: float | None = None
    attempts: dict[str, int] = dataclasses.field(default_factory=dict)
    consecutive_failures: int = 0

    @classmethod
    def load(cls, path: Path) -> "State":
        """Reads the state file, or returns an empty state if there is none."""
        if not path.exists():
            return cls()
        return cls(**json.loads(path.read_text()))

    def save(self, path: Path) -> None:
        """Writes the state file atomically."""
        tmp = path.with_suffix(".tmp")
        tmp.write_text(json.dumps(dataclasses.asdict(self), indent=2) + "\n")
        tmp.replace(path)


def decide(
    state: State,
    now: float,
    latest_rev: str,
    locked_rev: str,
    cooldown_days: int,
    max_attempts: int,
) -> str | None:
    """Returns why this run should skip the update, or None to run it."""
    if state.last_push is not None:
        ready = state.last_push + cooldown_days * DAY
        if now < ready:
            return f"cooldown: next update after {time.ctime(ready)}"
    if latest_rev == locked_rev:
        return f"flake.lock already has the newest nixos-unstable ({latest_rev[:12]})"
    if state.attempts.get(latest_rev, 0) >= max_attempts:
        return (
            f"nixos-unstable {latest_rev[:12]} failed {max_attempts} times;"
            " waiting for a newer revision"
        )
    return None


def locked_nixpkgs_rev(lock: dict) -> str:
    """Returns the nixpkgs revision pinned in a parsed flake.lock."""
    root = lock["nodes"][lock["root"]]
    node = root["inputs"]["nixpkgs"]
    return lock["nodes"][node]["locked"]["rev"]


def run(cmd: list[str], cwd: Path | None = None, env: dict | None = None) -> str:
    """Runs a command, streams stderr to the journal and returns stdout."""
    print(f"$ {' '.join(cmd)}", flush=True)
    result = subprocess.run(
        cmd, cwd=cwd, env=env, stdout=subprocess.PIPE, stderr=sys.stderr, text=True
    )
    if result.returncode != 0:
        raise GateError(f"{' '.join(cmd[:4])} exited with {result.returncode}")
    return result.stdout


class Updater:
    """Runs one nightly update."""

    def __init__(self, args: argparse.Namespace) -> None:
        """Stores settings and derives paths from the state directory."""
        self.args = args
        self.state_dir = Path(args.state_dir)
        self.repo = self.state_dir / "repo"
        self.roots = self.state_dir / "gcroots"
        self.state_file = self.state_dir / "state.json"

    def notify(self, title: str, message: str, priority: int) -> None:
        """Sends a Gotify message. Without a token file, only logs it."""
        print(f"[notify p{priority}] {title}: {message}", flush=True)
        token_file = Path(self.args.gotify_token_file)
        if not token_file.exists():
            print(f"no Gotify token at {token_file}; alert not sent", flush=True)
            return
        data = urllib.parse.urlencode(
            {"title": title, "message": message, "priority": priority}
        ).encode()
        request = urllib.request.Request(
            f"{self.args.gotify_url}/message",
            data=data,
            headers={"X-Gotify-Key": token_file.read_text().strip()},
        )
        try:
            urllib.request.urlopen(request, timeout=30).close()
        except OSError as error:
            print(f"Gotify send failed: {error}", flush=True)

    def git(self, *args: str) -> str:
        """Runs git in the working clone."""
        return run(["git", *args], cwd=self.repo)

    def sync_repo(self) -> None:
        """Makes the working clone an exact copy of origin's branch."""
        if not (self.repo / ".git").exists():
            run(["git", "clone", self.args.repo_url, str(self.repo)])
        self.git("fetch", "origin", self.args.branch)
        self.git("checkout", "-B", self.args.branch, f"origin/{self.args.branch}")
        self.git("reset", "--hard", f"origin/{self.args.branch}")
        self.git("clean", "-fdx")

    def locked_rev(self) -> str:
        """Returns the nixpkgs revision in the working clone's flake.lock."""
        return locked_nixpkgs_rev(json.loads((self.repo / "flake.lock").read_text()))

    def check_attrs(self) -> list[str]:
        """Returns the flake's x86_64-linux check names."""
        out = run(
            ["nix", "eval", "--json", ".#checks.x86_64-linux", "--apply", "builtins.attrNames"],
            cwd=self.repo,
        )
        return json.loads(out)

    def gate(self) -> list[str]:
        """Runs every gate step and returns the installables that were built.

        Steps run one at a time, each in its own nix process, so evaluation memory
        (about 1.5 GB per host, 5 GB for the flake check) is freed before the next build.
        Yuffie has 6 GB of RAM; the tidus-boot VM alone takes 3 GB.
        """
        run(["nix", "flake", "check", "--all-systems", "--no-build"], cwd=self.repo)
        run(["nix", "fmt", "--", "--check", "."], cwd=self.repo)
        for host in self.args.darwin_hosts:
            run(
                [
                    "nix",
                    "eval",
                    "--raw",
                    f".#darwinConfigurations.{host}.config.system.build.toplevel.drvPath",
                ],
                cwd=self.repo,
            )

        # VM tests last: by then the host closures they boot are already built.
        names = sorted(self.check_attrs(), key=lambda name: name.endswith("-boot"))
        checks = [f".#checks.x86_64-linux.{name}" for name in names]
        for check in checks:
            run(["nix", "build", "--no-link", "-L", check], cwd=self.repo)

        # Standalone home configs read USER and HOME, so they need an impure build.
        env = os.environ | {"USER": "danny", "HOME": "/home/danny"}
        for profile in self.args.home_profiles:
            run(
                [
                    "nix",
                    "build",
                    "--impure",
                    "--no-link",
                    "-L",
                    f".#homeConfigurations.{profile}.activationPackage",
                ],
                cwd=self.repo,
                env=env,
            )
        return checks

    def rotate_roots(self, checks: list[str]) -> None:
        """Roots the new build as current and keeps one previous build."""
        current, previous = self.roots / "current", self.roots / "previous"
        shutil.rmtree(previous, ignore_errors=True)
        if current.exists():
            current.rename(previous)
        current.mkdir(parents=True)
        for installable in checks:
            name = installable.rsplit(".", 1)[-1]
            run(["nix", "build", "--out-link", str(current / name), installable], cwd=self.repo)

    def push(self, rev: str, changes: str) -> None:
        """Commits flake.lock and pushes it; rebases and rechecks once if main moved."""
        self.git("add", "flake.lock")
        self.git(
            "-c",
            f"user.name={self.args.git_name}",
            "-c",
            f"user.email={self.args.git_email}",
            "commit",
            "-m",
            f"chore(flake): update inputs to nixos-unstable {rev[:12]}",
            "-m",
            f"Built and checked on yuffie.\n\n{changes}".strip(),
        )
        try:
            self.git("push", "origin", f"HEAD:{self.args.branch}")
            return
        except GateError:
            print("push rejected; rebasing onto the new main", flush=True)
        self.git("fetch", "origin", self.args.branch)
        try:
            self.git("rebase", f"origin/{self.args.branch}")
        except GateError:
            self.git("rebase", "--abort")
            raise GateError("main changed flake.lock during the run") from None
        self.gate()
        self.git("push", "origin", f"HEAD:{self.args.branch}")

    def update(self, state: State) -> None:
        """Runs the update, gate and push. Raises GateError on failure."""
        self.sync_repo()
        latest = run(["git", "ls-remote", NIXPKGS_URL, UNSTABLE_REF]).split()[0]
        skip = decide(
            state,
            time.time(),
            latest,
            self.locked_rev(),
            self.args.cooldown_days,
            self.args.max_attempts,
        )
        if skip and not self.args.no_push:
            print(f"skip: {skip}", flush=True)
            return

        state.attempts[latest] = state.attempts.get(latest, 0) + 1
        result = subprocess.run(
            ["nix", "flake", "update"], cwd=self.repo, capture_output=True, text=True
        )
        print(result.stderr, file=sys.stderr, flush=True)
        if result.returncode != 0:
            raise GateError("nix flake update failed")
        changes = "\n".join(
            line.strip() for line in result.stderr.splitlines() if "Updated input" in line
        )
        rev = self.locked_rev()

        checks = self.gate()
        if self.args.no_push:
            print(f"--no-push: gate passed for nixos-unstable {rev[:12]}\n{changes}", flush=True)
            return
        self.push(rev, changes)
        self.rotate_roots(checks)

        state.last_push = time.time()
        state.attempts = {}
        state.consecutive_failures = 0
        self.notify("Flake update pushed", f"nixos-unstable {rev[:12]}\n\n{changes}", 2)

    def main(self) -> int:
        """Runs one night's update and records the outcome."""
        state = State.load(self.state_file)
        if self.args.no_push:
            # A dry run ignores the policy and leaves state, roots and main untouched.
            try:
                self.update(State())
            except GateError as error:
                print(f"FAILED: {error}", flush=True)
                return 1
            return 0
        try:
            self.update(state)
        except GateError as error:
            state.consecutive_failures += 1
            print(f"FAILED: {error}", flush=True)
            if state.consecutive_failures >= self.args.alert_after:
                self.notify(
                    "Flake update failing",
                    f"{state.consecutive_failures} nights in a row. Last error: {error}."
                    " See: journalctl -u flake-updater on yuffie",
                    8,
                )
            return 1
        finally:
            state.save(self.state_file)
        return 0


def parse_args(argv: list[str]) -> argparse.Namespace:
    """Parses command-line options."""
    parser = argparse.ArgumentParser(description="Nightly flake.lock updater for yuffie.")
    parser.add_argument("--state-dir", required=True)
    parser.add_argument("--repo-url", required=True)
    parser.add_argument("--branch", default="main")
    parser.add_argument("--cooldown-days", type=int, default=7)
    parser.add_argument("--max-attempts", type=int, default=2)
    parser.add_argument("--alert-after", type=int, default=3)
    parser.add_argument("--darwin-hosts", nargs="*", default=[])
    parser.add_argument("--home-profiles", nargs="*", default=[])
    parser.add_argument("--gotify-url", required=True)
    parser.add_argument("--gotify-token-file", required=True)
    parser.add_argument("--git-name", default="yuffie")
    parser.add_argument("--git-email", default="yuffie@solivan.dev")
    parser.add_argument(
        "--no-push",
        action="store_true",
        help="Update and run the gate now, ignoring the policy; push nothing, keep no state.",
    )
    return parser.parse_args(argv)


if __name__ == "__main__":
    sys.exit(Updater(parse_args(sys.argv[1:])).main())
