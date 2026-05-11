#!/usr/bin/env python3
"""Validate the barrett pyinfra modules without sudo or pyinfra execution.

Prints every config file / systemd unit / script that would be deployed,
and runs a live check of the ipfilter VPN-guard logic.

Usage:  python3 scripts/barrett-validate.py
"""

import subprocess
import sys
import textwrap

RESET = "\033[0m"
BOLD = "\033[1m"
GREEN = "\033[32m"
YELLOW = "\033[33m"
RED = "\033[31m"
CYAN = "\033[36m"


def header(title: str) -> None:
    print(f"\n{BOLD}{CYAN}{'=' * 60}{RESET}")
    print(f"{BOLD}{CYAN}  {title}{RESET}")
    print(f"{BOLD}{CYAN}{'=' * 60}{RESET}")


def ok(msg: str) -> None:
    print(f"{GREEN}  ✓{RESET}  {msg}")


def warn(msg: str) -> None:
    print(f"{YELLOW}  ⚠{RESET}  {msg}")


def fail(msg: str) -> None:
    print(f"{RED}  ✗{RESET}  {msg}")


def show_file(label: str, content: str) -> None:
    print(f"\n{BOLD}--- {label} ---{RESET}")
    for line in content.splitlines():
        print(f"    {line}")


# ---------------------------------------------------------------------------
# 1. Syntax check all barrett-related Python files
# ---------------------------------------------------------------------------
header("1. Python syntax check")

import ast
import pathlib

roots = [
    pathlib.Path("modules/linux/services"),
    pathlib.Path("hosts/linux/barrett"),
]
errors = 0
for root in roots:
    for py in sorted(root.glob("*.py")):
        try:
            ast.parse(py.read_text())
            ok(str(py))
        except SyntaxError as e:
            fail(f"{py}: {e}")
            errors += 1

if errors:
    sys.exit(1)

# ---------------------------------------------------------------------------
# 2. Render and print every config / unit / script that would be deployed
# ---------------------------------------------------------------------------
sys.path.insert(0, ".")

# We can't import pyinfra operations at module level without side effects, so
# we extract the template strings directly from the service modules.

header("2. Rendered configs")

# -- ipfilter update script --
from modules.linux.services.ipfilter import _UPDATE_SCRIPT, _SERVICE_UNIT as _IF_SVC, _TIMER_UNIT as _IF_TIMER  # noqa: E402

show_file("/usr/local/bin/update-qbittorrent-ipfilter", _UPDATE_SCRIPT)
show_file("qbittorrent-ipfilter-update.service", _IF_SVC)
show_file("qbittorrent-ipfilter-update.timer", _IF_TIMER)

# -- qbittorrent service unit --
from modules.linux.services.qbittorrent import _SERVICE_UNIT as _QB_SVC  # noqa: E402

rendered_qb_svc = _QB_SVC.format(
    user="danny",
    config_dir="/var/lib/torrent/qbittorrent",
    download_dir="/mnt/titan/downloads",
    webui_port=8112,
)
show_file("qbittorrent.service", rendered_qb_svc)

# -- autoremove service + timer --
from modules.linux.services.autoremove_torrents import (  # noqa: E402
    _SERVICE_UNIT as _AR_SVC,
    _TIMER_UNIT as _AR_TIMER,
)

show_file("autoremove-torrents.service", _AR_SVC)
show_file("autoremove-torrents.timer", _AR_TIMER.format(interval_minutes=5))

# -- titan mount units --
from modules.linux.services.titan_mount import _MOUNT_UNIT, _AUTOMOUNT_UNIT  # noqa: E402

show_file("mnt-titan.mount", _MOUNT_UNIT)
show_file("mnt-titan.automount", _AUTOMOUNT_UNIT)

# ---------------------------------------------------------------------------
# 3. Key correctness checks on rendered content
# ---------------------------------------------------------------------------
header("3. Correctness checks")

checks = [
    # ipfilter VPN guard
    ("ipfilter script checks nordvpn status before downloading",
     'nordvpn status' in _UPDATE_SCRIPT and 'Status: Connected' in _UPDATE_SCRIPT),
    # ipfilter exits cleanly (not with error) when VPN is down
    ("ipfilter exits 0 when VPN disconnected (no false failure)",
     'exit 0' in _UPDATE_SCRIPT),
    # ipfilter service retries on failure
    ("ipfilter service has Restart=on-failure",
     'Restart=on-failure' in _IF_SVC),
    ("ipfilter service has RestartSec (retry delay)",
     'RestartSec' in _IF_SVC),
    # qBittorrent bound to nordlynx (set in the config template, not the service unit)
    ("qBittorrent bound to nordlynx interface",
     'Interface=nordlynx' in open("modules/linux/services/qbittorrent.py").read()),
    # qBittorrent privacy settings in generated config script
    ("qBittorrent AnonymousMode enabled in update() shell script",
     'AnonymousMode=true' in open("modules/linux/services/qbittorrent.py").read()),
    ("qBittorrent DHT disabled",
     'DHTEnabled=false' in open("modules/linux/services/qbittorrent.py").read()),
    ("qBittorrent PEX disabled",
     'PeXEnabled=false' in open("modules/linux/services/qbittorrent.py").read()),
    ("qBittorrent RequireEncryption=true",
     'RequireEncryption=true' in open("modules/linux/services/qbittorrent.py").read()),
    # autoremove timer fires every 5 minutes
    ("autoremove timer interval is 5 minutes",
     '5min' in _AR_TIMER.format(interval_minutes=5)),
    # qbittorrent service waits for nordvpnd
    ("qbittorrent.service After= includes nordvpnd",
     'nordvpnd.service' in rendered_qb_svc),
]

all_passed = True
for label, result in checks:
    if result:
        ok(label)
    else:
        fail(label)
        all_passed = False

# ---------------------------------------------------------------------------
# 4. Live: test ipfilter VPN-guard logic against running nordvpn
# ---------------------------------------------------------------------------
header("4. Live: ipfilter VPN guard (read-only)")

try:
    result = subprocess.run(
        ["nordvpn", "status"],
        capture_output=True, text=True, timeout=5,
    )
    status_output = result.stdout
    connected = "Status: Connected" in status_output

    if connected:
        ok(f"NordVPN is connected — ipfilter update would proceed")
        # Grab the server line to confirm
        for line in status_output.splitlines():
            if any(k in line for k in ("Status", "Server", "IP")):
                print(f"       {line.strip()}")
    else:
        warn("NordVPN is NOT connected — ipfilter update would skip (exit 0)")
        print(f"       {status_output.strip()[:120]}")
except FileNotFoundError:
    warn("nordvpn CLI not found on PATH")
except subprocess.TimeoutExpired:
    warn("nordvpn status timed out")

# ---------------------------------------------------------------------------
# Result
# ---------------------------------------------------------------------------
header("Result")
if all_passed:
    ok("All checks passed")
    sys.exit(0)
else:
    fail("One or more checks failed")
    sys.exit(1)
