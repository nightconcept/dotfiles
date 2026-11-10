"""Keep the latest downloaded season of explicitly listed Sonarr series."""

import argparse
import datetime
import json
import sys
import urllib.error
import urllib.request
import xml.etree.ElementTree as ET
from pathlib import Path

URL = "http://127.0.0.1:8989/api/v3"
CONFIG = "/home/danny/docker/sonarr/config/config.xml"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("manifest")
    parser.add_argument("--apply", action="store_true", help="unmonitor and delete old seasons")
    args = parser.parse_args()
    manifest = json.loads(Path(args.manifest).read_text())
    key = ET.parse(CONFIG).getroot().findtext("ApiKey")
    if not key:
        raise ValueError("Sonarr API key missing")

    def request(path, method="GET", data=None):
        body = json.dumps(data).encode() if data is not None else None
        req = urllib.request.Request(
            URL + path, data=body, method=method,
            headers={"X-Api-Key": key, "Content-Type": "application/json"},
        )
        with urllib.request.urlopen(req, timeout=60) as response:
            result = response.read()
        return json.loads(result) if result else None

    series_by_tvdb = {str(s["tvdbId"]): s for s in request("/series")}
    now = datetime.datetime.now(datetime.timezone.utc)
    total = 0
    for tvdb_id, title in manifest.items():
        series = series_by_tvdb.get(tvdb_id)
        if not series:
            print(f"SKIP {title}: series not found", flush=True)
            continue
        episodes = request(f"/episode?seriesId={series['id']}")
        files = request(f"/episodefile?seriesId={series['id']}")
        episodes_by_file = {}
        for episode in episodes:
            if episode.get("episodeFileId"):
                episodes_by_file.setdefault(episode["episodeFileId"], []).append(episode)
        aired = set()
        for episode in episodes:
            date = episode.get("airDateUtc")
            if episode.get("hasFile") and episode.get("seasonNumber", 0) > 0 and date:
                if datetime.datetime.fromisoformat(date.replace("Z", "+00:00")) <= now:
                    aired.add(episode["seasonNumber"])
        if not aired:
            print(f"SKIP {title}: no downloaded, aired season", flush=True)
            continue
        keep = max(aired)
        old_seasons = {s["seasonNumber"] for s in series["seasons"] if 0 < s["seasonNumber"] < keep}
        candidates = []
        for file in files:
            linked = episodes_by_file.get(file["id"], [])
            if linked and all(e.get("seasonNumber") in old_seasons for e in linked):
                candidates.append(file)
        size = sum(f["size"] for f in candidates)
        total += size
        print(f"{title}: keep season {keep}; old seasons {sorted(old_seasons)}; "
              f"{len(candidates)} files, {size / 1e9:.2f} GB", flush=True)
        for file in candidates:
            print(f"  {file.get('relativePath', file['id'])} ({file['size'] / 1e9:.2f} GB)", flush=True)
        old_episodes = [e["id"] for e in episodes if e.get("seasonNumber") in old_seasons and e.get("monitored")]
        if args.apply and old_seasons:
            for season in series["seasons"]:
                if season["seasonNumber"] in old_seasons:
                    season["monitored"] = False
            request(f"/series/{series['id']}", "PUT", series)
            if old_episodes:
                request("/episode/monitor", "PUT", {"episodeIds": old_episodes, "monitored": False})
            for file in candidates:
                request(f"/episodefile/{file['id']}", "DELETE")
    print(f"{'Deleted' if args.apply else 'Would delete'}: {total / 1e9:.2f} GB", flush=True)


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, KeyError, urllib.error.HTTPError) as error:
        print(f"Cleanup stopped: {error}", file=sys.stderr)
        sys.exit(1)
