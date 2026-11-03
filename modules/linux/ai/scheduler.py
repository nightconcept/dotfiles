"""Scheduler integration for Terra's AI stack (Rotom GPU lease window detection)."""

from __future__ import annotations

import os
import shlex

from pyinfra import host
from pyinfra.facts.server import Command


def gpu_window_open() -> bool:
    """Tells whether the lease daemon (rotom) reports an open GPU lease window right now.

    While it is open, llama-swap is meant to be down. Deploy steps that would restart or
    probe llama-swap use this to leave it alone. It is False when the scheduler is missing, not
    running, or in a window without GPU leases.

    Returns:
        True when status reports `gpu_leases: true`.
    """
    home = os.path.expanduser("~")
    check_expr = (
        "import json,sys; d=json.load(sys.stdin); "
        "val = d.get('gpu_leases'); val = (d.get('terra') or {}).get('gpu_leases') "
        "if val is None else val; print(val is True)"
    )
    cmd = (
        f"({shlex.quote(home + '/.local/bin/rotom')} status --json 2>/dev/null || "
        "rotom status --json 2>/dev/null) | "
        f"python3 -c {shlex.quote(check_expr)} 2>/dev/null || echo False"
    )
    output = host.get_fact(Command, command=cmd)
    return (output or "").strip().endswith("True")
