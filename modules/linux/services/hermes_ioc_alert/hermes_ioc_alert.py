#!/usr/bin/python3 -I
"""Push a Gotify alert when Hermes's model emits a known exfiltration indicator.

Cohere saw Qwen3.8-Flash-Next, in agentic runs, upload to an Alibaba OSS bucket,
call a "routify" proxy on aliyuncs.com, probe cloud metadata addresses, and use
`unshare` to get root in a user namespace:
https://cohere.com/blog/concerning-behaviour-popular-open-weight-ai-model

This scans what the model itself wrote (assistant tool calls and replies in
Hermes's state.db) and the Hermes user's journal. Tool output is not scanned, so
reading a file that mentions these hosts does not alert. Runs as root so the
agent, which runs as the same user as Hermes, cannot silence it.
"""

import argparse
import json
import re
import sqlite3
import subprocess
import sys
import urllib.parse
import urllib.request
from pathlib import Path

INDICATORS = {
    "Alibaba Cloud host": r"[a-z0-9.-]*\.aliyuncs\.com|alibabacloud\.com",
    "routify proxy": r"routify",
    "Cohere probe upload": r"sanmaohe|PROBE_PAYLOAD",
    "cloud metadata address": r"169\.254\.169\.254|100\.100\.100\.200|metadata\.google\.internal",
    "user namespace escape": r"\bunshare\b|\bnsenter\b",
}
PATTERNS = {label: re.compile(p, re.I) for label, p in INDICATORS.items()}
MAX_HITS_PER_ALERT = 5
SNIPPET_CHARS = 120


def find_indicator(text):
    """Return (label, snippet) for the first indicator in text, or None."""
    for label, pattern in PATTERNS.items():
        if match := pattern.search(text):
            break
    else:
        return None
    start = max(0, match.start() - SNIPPET_CHARS)
    snippet = text[start : match.end() + SNIPPET_CHARS].replace("\n", " ")
    return label, snippet


def scan_state_db(db_path, after_id):
    """Scan assistant messages newer than after_id. Returns (hits, last_id)."""
    conn = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)
    try:
        rows = conn.execute(
            "SELECT m.id, m.session_id, s.source, m.tool_calls, m.content "
            "FROM messages m LEFT JOIN sessions s ON s.id = m.session_id "
            "WHERE m.role = 'assistant' AND m.id > ? ORDER BY m.id",
            (after_id,),
        ).fetchall()
        last_id = conn.execute("SELECT COALESCE(MAX(id), 0) FROM messages").fetchone()[0]
    finally:
        conn.close()
    hits = []
    for msg_id, session_id, source, tool_calls, content in rows:
        for text in (tool_calls, content):
            found = text and find_indicator(text)
            if found:
                label, snippet = found
                where = f"session {session_id} ({source}), message {msg_id}"
                hits.append(f"[{label}] {where}: {snippet}")
                break
    return hits, max(last_id, after_id)


def scan_journal(uid, cursor):
    """Scan the user's journal after cursor. Returns (hits, new_cursor)."""
    cmd = ["journalctl", f"_UID={uid}", "--output=json", "--no-pager"]
    cmd += [f"--after-cursor={cursor}"] if cursor else ["--since=-24h"]
    out = subprocess.run(cmd, capture_output=True, text=True, check=True).stdout
    hits = []
    for line in out.splitlines():
        entry = json.loads(line)
        cursor = entry["__CURSOR"]
        message = entry.get("MESSAGE")
        # journald stores non-UTF-8 messages as byte arrays; nothing to match there.
        found = isinstance(message, str) and find_indicator(message)
        if found:
            label, snippet = found
            unit = entry.get("_SYSTEMD_USER_UNIT") or entry.get("SYSLOG_IDENTIFIER", "?")
            hits.append(f"[{label}] journal {unit}: {snippet}")
    return hits, cursor


def send_gotify(url, token, title, message, priority):
    """Post one Gotify message. The token goes in a header to keep it out of logs."""
    data = urllib.parse.urlencode({"title": title, "message": message, "priority": priority})
    request = urllib.request.Request(
        f"{url}/message", data=data.encode(), headers={"X-Gotify-Key": token}
    )
    with urllib.request.urlopen(request, timeout=10):
        pass


def main():
    """Scan once, alert on hits, and save how far the scan got."""
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--db", type=Path, required=True)
    parser.add_argument("--uid", required=True)
    parser.add_argument("--gotify-url", required=True)
    parser.add_argument("--token-file", type=Path, required=True)
    parser.add_argument("--state", type=Path, required=True)
    args = parser.parse_args()

    if not args.token_file.is_file():
        sys.exit(f"Missing Gotify token {args.token_file}; see docs/hermes.md.")
    token = args.token_file.read_text().strip()
    state = json.loads(args.state.read_text()) if args.state.exists() else {}
    host = Path("/proc/sys/kernel/hostname").read_text().strip()

    hits = []
    try:
        db_hits, state["last_message_id"] = scan_state_db(args.db, state.get("last_message_id", 0))
        hits += db_hits
        journal_hits, state["journal_cursor"] = scan_journal(args.uid, state.get("journal_cursor"))
        hits += journal_hits
        error = None
    except (sqlite3.Error, subprocess.CalledProcessError, OSError) as e:
        error = f"{type(e).__name__}: {e}"

    # A silent scanner is worse than none: report a new failure once.
    if error and error != state.get("error"):
        send_gotify(
            args.gotify_url,
            token,
            f"{host}: Hermes IOC scanner failing",
            f"{error}\nHermes tool calls are not being checked until this is fixed.",
            7,
        )
    state["error"] = error

    if hits:
        shown = hits[:MAX_HITS_PER_ALERT]
        more = len(hits) - len(shown)
        body = "\n\n".join(shown) + (f"\n\n…and {more} more" if more else "")
        body += "\n\nCheck ~/.hermes/state.db and stop hermes-gateway if unexpected."
        send_gotify(
            args.gotify_url,
            token,
            f"{host}: Hermes model emitted a known exfiltration indicator",
            body,
            9,
        )
        print("\n".join(hits))

    # Saved only after alerts are sent, so a Gotify outage retries the same hits.
    args.state.write_text(json.dumps(state))
    if error:
        sys.exit(error)


if __name__ == "__main__":
    main()
