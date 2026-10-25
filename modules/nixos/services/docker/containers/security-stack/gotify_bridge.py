"""Forward the Suricata alerts shown in EveBox to Gotify."""

import json
import os
import time
from pathlib import Path
from urllib import request


def notify(event, url, token):
    """Send one alert without including packet payloads or HTTP credentials."""
    alert = event["alert"]
    message = (
        f"Sensor: {event.get('host', os.environ.get('SENSOR_NAME', 'unknown'))}\n"
        f"{alert['signature']}\n"
        f"{event.get('src_ip', '?')}:{event.get('src_port', '?')} -> "
        f"{event.get('dest_ip', '?')}:{event.get('dest_port', '?')}\n"
        f"{event.get('timestamp', '')}\nhttps://evebox.local.solivan.dev"
    )
    body = json.dumps({"title": "Suricata alert", "message": message, "priority": 7}).encode()
    req = request.Request(
        url.rstrip("/") + "/message",
        body,
        {"Content-Type": "application/json", "X-Gotify-Key": token},
    )
    with request.urlopen(req, timeout=15) as response:
        response.read()


def forward(log, state_file, send):
    """Resume after delivered records and leave incomplete records for the next poll."""
    state = json.loads(state_file.read_text()) if state_file.exists() else {}
    # Drain a renamed file before switching to the new eve.json after rotation.
    for candidate in log.parent.glob("eve.json*"):
        stat = candidate.stat()
        if stat.st_ino == state.get("inode") and stat.st_size > state.get("offset", 0):
            log = candidate
            break
    with log.open("rb") as source:
        stat = os.fstat(source.fileno())
        offset = state.get("offset", 0) if state.get("inode") == stat.st_ino else 0
        source.seek(offset if offset <= stat.st_size else 0)
        while line := source.readline():
            if not line.endswith(b"\n"):
                break
            try:
                event = json.loads(line)
            except (ValueError, UnicodeDecodeError):
                print("Skipping malformed EVE record", flush=True)
            else:
                if isinstance(event, dict) and event.get("event_type") == "alert":
                    send(event)
                    save_position(state_file, stat.st_ino, source.tell())
            state = {"inode": stat.st_ino, "offset": source.tell()}
        if state:
            save_position(state_file, state["inode"], state["offset"])


def save_position(path, inode, offset):
    """Atomically checkpoint delivered events."""
    temporary = path.with_suffix(".tmp")
    temporary.write_text(json.dumps({"inode": inode, "offset": offset}))
    temporary.replace(path)


def main():
    """Retry failed deliveries without advancing the saved position."""
    token = Path("/run/secrets/gotify-token").read_text().strip()
    if not token:
        raise ValueError("Gotify token file is empty")
    while True:
        try:
            forward(
                Path("/var/log/suricata/eve.json"),
                Path("/var/lib/bridge/position.json"),
                lambda event: notify(event, os.environ["GOTIFY_URL"], token),
            )
        except (OSError, ValueError):
            # Exception details can contain credentials or response bodies.
            print("Alert delivery failed or EVE file unavailable; retrying", flush=True)
        time.sleep(5)


if __name__ == "__main__":
    main()
