"""Rotate local logs, reload daily rule updates, and expire dated Wazuh alerts."""

import datetime
import json
import os
import re
import sys
import time
from pathlib import Path

from prepare import run


def expired_indices(indices, days, today):
    """Expire only dated Wazuh event indices; preserve current-day data."""
    dated = []
    for index in indices:
        match = re.fullmatch(
            r"wazuh-(?:alerts|archives)-4\.x-(\d{4}\.\d{2}\.\d{2})", index["index"]
        )
        if match:
            date = datetime.datetime.strptime(match[1], "%Y.%m.%d").date()
            dated.append((date, index["index"], int(index.get("store.size") or 0)))
    dated.sort()
    total = sum(size for _, _, size in dated)
    expired = []
    for date, name, size in dated:
        if date < today and ((today - date).days >= days or total > 10 * 1024**3):
            expired.append(name)
            total -= size
    return expired


def main():
    """Operate only this project's containers and event indices."""
    settings = json.loads(Path(sys.argv[1]).read_text())
    root = Path(sys.argv[2])
    os.chdir(root)
    docker = ["docker", "compose", "--project-directory", str(root)]
    updated = root / ".rules-updated"
    if not updated.exists() or time.time() - updated.stat().st_mtime >= 86400:
        run(
            docker
            + ["exec", "-T", "--user", "suricata", "suricata", "suricata-update", "--no-reload"]
        )
        run(docker + ["kill", "--signal", "USR2", "suricata"])
        updated.touch()
    run(docker + ["exec", "-T", "suricata", "logrotate", "/etc/logrotate.d/suricata"])
    if settings["role"] == "central":
        curl = docker + ["exec", "-T", "wazuh.indexer", "bash", "-c"]
        auth = 'printf \'user = "admin:%s"\\n\' "$INDEXER_PASSWORD" | '
        auth += "curl --fail --silent --show-error --config - --cacert config/certs/root-ca.pem "
        indices = json.loads(
            run(
                curl
                + [
                    auth
                    + "'https://wazuh.indexer:9200/_cat/indices/wazuh-alerts-*,wazuh-archives-*?format=json&bytes=b'"
                ]
            )
        )
        today = datetime.datetime.now(datetime.timezone.utc).date()
        for name in expired_indices(indices, settings["retentionDays"], today):
            run(curl + [auth + "-X DELETE 'https://wazuh.indexer:9200/" + name + "'"])
        run(
            docker
            + [
                "exec",
                "-T",
                "wazuh.manager",
                "find",
                "/var/ossec/logs/alerts",
                "/var/ossec/logs/archives",
                "-mindepth",
                "2",
                "-type",
                "f",
                "-mtime",
                "+" + str(settings["retentionDays"]),
                "-delete",
            ]
        )


if __name__ == "__main__":
    main()
