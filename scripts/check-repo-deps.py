#!/usr/bin/env python3
"""Report repos whose toolchain versions fall behind shared/dev-builds.toml.

Scans each repo's mise.toml / .mise.toml / .tool-versions, devenv.nix, .python-version,
global.json, go.mod, rust-toolchain(.toml), and torch pins in uv.lock / requirements*.txt.

Usage:
    check-repo-deps.py [PATH ...] [--all] [--json] [--manifest FILE]

Each PATH is a repo or a directory of repos. The default is ~/git. Standard library only.
"""

from __future__ import annotations

import argparse
import dataclasses
import json
import re
import sys
import tomllib
from pathlib import Path

DEFAULT_MANIFEST = Path(__file__).resolve().parent.parent / "shared" / "dev-builds.toml"

# mise / asdf tool names that map onto a manifest tool.
TOOL_ALIASES = {
    "python": "python",
    "node": "node",
    "nodejs": "node",
    "go": "go",
    "golang": "go",
    "rust": "rust",
    "dotnet": "dotnet",
    "core:dotnet": "dotnet",
    "java": "java",
    "zig": "zig",
    "uv": "uv",
    "aqua:astral-sh/uv": "uv",
    "just": "just",
    "pnpm": "pnpm",
}

# devenv / nixpkgs package attribute -> (tool, version).
NIX_PACKAGE_PATTERNS = [
    (re.compile(r"\bpython3(\d{2})\b"), "python", lambda m: f"3.{m.group(1)}"),
    (re.compile(r"\bnodejs_(\d+)\b"), "node", lambda m: m.group(1)),
    (re.compile(r"\bgo_1_(\d+)\b"), "go", lambda m: f"1.{m.group(1)}"),
    (re.compile(r"\bdotnet-sdk_(\d+)\b"), "dotnet", lambda m: f"{m.group(1)}.0"),
    (re.compile(r"\b(?:jdk|temurin-bin-)(\d+)\b"), "java", lambda m: m.group(1)),
    (re.compile(r"\bzig_0_(\d+)\b"), "zig", lambda m: f"0.{m.group(1)}"),
]

FLOATING = {"latest", "lts", "stable", "system", "ref:main"}


@dataclasses.dataclass
class Finding:
    """One tool version declared by one repo file."""

    tool: str
    declared: str
    source: str
    status: str = ""  # behind | current | ahead | floating | unpinned
    preferred: str = ""


def numeric(version: str) -> tuple[int, ...] | None:
    """Return the leading dotted number of a version spec, or None if it has none.

    Args:
        version: A spec such as "3.14.6", "temurin-17", "v1.2", or "24".

    Returns:
        The numeric parts as a tuple, for example (3, 14, 6).
    """
    m = re.search(r"(\d+(?:\.\d+)*)", version)
    return tuple(int(p) for p in m.group(1).split(".")) if m else None


def compare(declared: str, preferred: str) -> str:
    """Classify a declared version against the preferred one.

    The comparison uses the shorter of the two precisions, so "3.14" matches any 3.14.x and a
    loose spec such as "24" matches "24.22".

    Args:
        declared: The version the repo asks for.
        preferred: The version from the manifest.

    Returns:
        One of "behind", "current", "ahead", "floating", or "unpinned".
    """
    spec = declared.strip().lower()
    if spec in FLOATING or spec.startswith("prefix:"):
        return "floating"
    if spec.startswith(("nightly", "beta", "canary")):
        return "unpinned"
    have, want = numeric(spec), numeric(preferred)
    if have is None or want is None:
        return "unpinned"
    n = min(len(have), len(want))
    if have[:n] < want[:n]:
        return "behind"
    if have[:n] > want[:n]:
        return "ahead"
    return "current"


def _mise_findings(repo: Path) -> list[Finding]:
    found = []
    for name in ("mise.toml", ".mise.toml"):
        path = repo / name
        if not path.exists():
            continue
        try:
            tools = tomllib.loads(path.read_text()).get("tools", {})
        except tomllib.TOMLDecodeError as err:
            found.append(Finding("mise", f"parse error: {err}", name, "unpinned"))
            continue
        for key, value in tools.items():
            if isinstance(value, dict):
                value = value.get("version", "")
            if isinstance(value, list):
                value = value[0] if value else ""
            found.append(Finding(key, str(value), name))
    path = repo / ".tool-versions"
    if path.exists():
        for line in path.read_text().splitlines():
            parts = line.split()
            if len(parts) >= 2 and not parts[0].startswith("#"):
                found.append(Finding(parts[0], parts[1], ".tool-versions"))
    return found


def _devenv_findings(repo: Path) -> list[Finding]:
    path = repo / "devenv.nix"
    if not path.exists():
        return []
    text = re.sub(r"#.*", "", path.read_text())
    found = []
    for pattern, tool, version in NIX_PACKAGE_PATTERNS:
        for m in pattern.finditer(text):
            found.append(Finding(tool, version(m), "devenv.nix"))
    for m in re.finditer(r"languages\.(\w+)\.version\s*=\s*\"([^\"]+)\"", text):
        found.append(Finding(m.group(1), m.group(2), "devenv.nix"))
    for m in re.finditer(r"languages\.rust\.(?:channel|version)\s*=\s*\"([^\"]+)\"", text):
        found.append(Finding("rust", m.group(1), "devenv.nix"))
    # A language enabled with no version follows the nixpkgs pin in devenv.lock.
    seen = {f.tool for f in found}
    for m in re.finditer(r"languages\.(\w+)\.enable\s*=\s*true", text):
        lang = {"javascript": "node", "golang": "go"}.get(m.group(1), m.group(1))
        if lang not in seen:
            found.append(Finding(lang, "nixpkgs default", "devenv.nix", "unpinned"))
            seen.add(lang)
    return found


def _language_file_findings(repo: Path) -> list[Finding]:
    found = []
    if (repo / ".python-version").exists():
        found.append(
            Finding("python", (repo / ".python-version").read_text().strip(), ".python-version")
        )
    if (repo / "global.json").exists():
        try:
            sdk = json.loads((repo / "global.json").read_text())["sdk"]["version"]
            found.append(Finding("dotnet", sdk, "global.json"))
        except (KeyError, json.JSONDecodeError):
            pass
    if (repo / "go.mod").exists():
        m = re.search(r"^go\s+(\S+)", (repo / "go.mod").read_text(), re.M)
        if m:
            found.append(Finding("go", m.group(1), "go.mod"))
    for name in ("rust-toolchain.toml", "rust-toolchain"):
        path = repo / name
        if path.exists():
            text = path.read_text()
            m = re.search(r'channel\s*=\s*"([^"]+)"', text)
            found.append(Finding("rust", m.group(1) if m else text.strip(), name))
    return found


def _torch_findings(repo: Path) -> list[Finding]:
    found = []
    lock = repo / "uv.lock"
    if lock.exists():
        try:
            packages = tomllib.loads(lock.read_text()).get("package", [])
        except tomllib.TOMLDecodeError:
            packages = []
        versions = sorted({p["version"] for p in packages if p.get("name") == "torch"})
        found += [Finding("torch", v, "uv.lock") for v in versions]
    for req in sorted(repo.glob("requirements*.txt")):
        for m in re.finditer(r"^torch\s*==\s*([^\s;#]+)", req.read_text(), re.M):
            found.append(Finding("torch", m.group(1), req.name))
    return found


def scan_repo(repo: Path, manifest: dict) -> list[Finding]:
    """Collect and classify every tool version a repo declares.

    Args:
        repo: The repo root.
        manifest: The parsed dev-builds manifest.

    Returns:
        Findings for tools that the manifest covers.
    """
    preferred = dict(manifest.get("tools", {}))
    torch = manifest.get("python", {}).get("torch", {})
    if "version" in torch:
        preferred["torch"] = torch["version"]
    findings = (
        _mise_findings(repo)
        + _devenv_findings(repo)
        + _language_file_findings(repo)
        + _torch_findings(repo)
    )
    kept = []
    for f in findings:
        f.tool = TOOL_ALIASES.get(f.tool, f.tool)
        if f.tool not in preferred:
            continue
        f.preferred = preferred[f.tool]
        f.status = f.status or compare(f.declared, f.preferred)
        kept.append(f)
    return kept


def fix_hint(f: Finding) -> str:
    """Return a one-line suggestion that moves a finding to the preferred version."""
    if f.source in ("mise.toml", ".mise.toml", ".tool-versions"):
        return f"mise use {f.tool}@{f.preferred}"
    hints = {
        ".python-version": f"echo {f.preferred} > .python-version",
        "go.mod": f"go mod edit -go={f.preferred}.0",
        "global.json": f'set sdk.version to the latest {f.preferred}.x ("mise latest dotnet")',
        "rust-toolchain.toml": f'set channel = "{f.preferred}"',
        "rust-toolchain": f"echo {f.preferred} > rust-toolchain",
        "uv.lock": f'uv add "torch=={f.preferred}"',
        "devenv.nix": f"bump the {f.tool} package/version in devenv.nix to {f.preferred}",
    }
    return hints.get(f.source, f"pin torch=={f.preferred}")


def find_repos(paths: list[Path]) -> list[Path]:
    """Expand each path to the git repos it holds, without duplicates or symlinked copies."""
    repos: dict[Path, Path] = {}
    for path in paths:
        path = path.expanduser()
        candidates = [path] if (path / ".git").exists() else sorted(path.iterdir())
        for c in candidates:
            if c.is_dir() and (c / ".git").exists():
                # A symlink to another repo is an alias; report the real directory name.
                key = c.resolve()
                if key not in repos or repos[key].is_symlink():
                    repos[key] = c
    return sorted(repos.values(), key=lambda p: p.name.lower())


def main(argv: list[str] | None = None) -> int:
    """Run the check and print a report."""
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument("paths", nargs="*", type=Path, default=[Path("~/git")])
    parser.add_argument("--manifest", type=Path, default=DEFAULT_MANIFEST)
    parser.add_argument("--all", action="store_true", help="also list current/floating pins")
    parser.add_argument("--json", action="store_true", help="machine-readable output")
    parser.add_argument("--strict", action="store_true", help="exit 1 when any repo is behind")
    args = parser.parse_args(argv)

    manifest = tomllib.loads(args.manifest.read_text())
    repos = find_repos(args.paths)
    report = {repo.name: scan_repo(repo, manifest) for repo in repos}
    behind = {n: [f for f in fs if f.status == "behind"] for n, fs in report.items()}
    behind = {n: fs for n, fs in behind.items() if fs}

    if args.json:
        print(
            json.dumps(
                {n: [dataclasses.asdict(f) for f in fs] for n, fs in report.items()}, indent=2
            )
        )
        return 1 if args.strict and behind else 0

    roots = ", ".join(str(p) for p in args.paths)
    print(f"check-repo-deps: {len(repos)} repos under {roots}")
    print(f"preferred builds: {args.manifest.name} (updated {manifest.get('updated', '?')})")
    prefs = dict(manifest.get("tools", {}))
    torch = manifest.get("python", {}).get("torch", {})
    if torch:
        prefs["torch"] = f"{torch['version']} (+{torch.get('rocm-backend', '')})"
    print("  " + "  ".join(f"{k}={v}" for k, v in prefs.items()))

    print(f"\nBEHIND: {len(behind)} repos")
    for name, findings in behind.items():
        print(f"  {name}")
        for f in findings:
            print(
                f"    {f.tool:<7} {f.declared:<14} -> {f.preferred:<6} {f.source:<20}"
                f" fix: {fix_hint(f)}"
            )

    if args.all:
        print("\nOTHER PINS (current / ahead / floating / unpinned)")
        for name, findings in report.items():
            rest = [f for f in findings if f.status != "behind"]
            if rest:
                pins = ", ".join(f"{f.tool} {f.declared} [{f.status}]" for f in rest)
                print(f"  {name}: {pins}")

    clean = [n for n, fs in report.items() if fs and n not in behind]
    none = [n for n, fs in report.items() if not fs]
    print(f"\nNOT BEHIND: {len(clean)} repos: {', '.join(clean) or '-'}")
    print(f"NO PINNED TOOLCHAIN: {len(none)} repos: {', '.join(none) or '-'}")
    return 1 if args.strict and behind else 0


if __name__ == "__main__":
    sys.exit(main())
