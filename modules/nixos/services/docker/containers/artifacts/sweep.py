#!/usr/bin/env python3
"""Expire artifacts and rebuild the index.

Layout under the data directory:
  a/<id>.html   the artifact (its mtime is the creation time)
  a/<id>.json   metadata written by the publisher: title, expires, pinned, publisher
  index.json    written here; the live artifacts and recent removals

Rules (the server does not trust the publisher's metadata):
  - no expiry, or a bad one: created + 14 days
  - an expiry later than created + 90 days is cut back to 90 days
  - `pinned` never expires, but only the 20 newest pins count; older ones fall
    back to the normal rules
  - over the quota (bytes or count), the soonest-expiring unpinned artifacts go first
  - a metadata file with no artifact is removed
"""
import argparse
import json
import os
import re
import sys
import tempfile
from dataclasses import dataclass, field
from datetime import datetime, timedelta, timezone
from pathlib import Path

ID = re.compile(r"^[0-9a-f]{16}$")
DEFAULT_TTL = timedelta(days=14)
MAX_TTL = timedelta(days=90)
MAX_PINNED = 20
QUOTA_BYTES = 2 * 1024**3
MAX_ITEMS = 500
KEEP_REMOVED = 50


@dataclass
class Item:
    id: str
    created: datetime
    size: int
    title: str = "(untitled)"
    publisher: str = ""
    expires: datetime | None = None
    pinned: bool = False
    meta_ok: bool = True


@dataclass
class Limits:
    default_ttl: timedelta = DEFAULT_TTL
    max_ttl: timedelta = MAX_TTL
    max_pinned: int = MAX_PINNED
    quota_bytes: int = QUOTA_BYTES
    max_items: int = MAX_ITEMS


def parse_time(value) -> datetime | None:
    if not isinstance(value, str):
        return None
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None
    return parsed if parsed.tzinfo else parsed.replace(tzinfo=timezone.utc)


def stamp(moment: datetime) -> str:
    return moment.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def normalize(items: list[Item], limits: Limits) -> None:
    """Apply the expiry rules in place."""
    pinned = sorted((i for i in items if i.pinned), key=lambda i: (i.created, i.id), reverse=True)
    for stale in pinned[limits.max_pinned:]:
        stale.pinned = False
    for item in items:
        if item.pinned:
            item.expires = None
            continue
        ceiling = item.created + limits.max_ttl
        if item.expires is None:
            item.expires = item.created + limits.default_ttl
        item.expires = min(item.expires, ceiling)


def plan(items: list[Item], now: datetime, limits: Limits) -> tuple[list[Item], list[tuple[Item, str]]]:
    """Return (kept, removed with reasons). Mutates the items' expiry fields."""
    normalize(items, limits)
    removed: list[tuple[Item, str]] = []
    kept: list[Item] = []
    for item in items:
        if not item.pinned and item.expires <= now:
            removed.append((item, "expired"))
        else:
            kept.append(item)
    evictable = sorted((i for i in kept if not i.pinned), key=lambda i: (i.expires, i.created, i.id))
    total = sum(i.size for i in kept)
    count = len(kept)
    for item in evictable:
        if total <= limits.quota_bytes and count <= limits.max_items:
            break
        removed.append((item, "quota"))
        kept.remove(item)
        total -= item.size
        count -= 1
    return kept, removed


def load(data: Path) -> tuple[list[Item], list[str]]:
    """Read the artifacts. Also return orphan metadata ids."""
    folder = data / "a"
    items: list[Item] = []
    orphans: list[str] = []
    if not folder.is_dir():
        return items, orphans
    htmls = {p.stem for p in folder.glob("*.html") if ID.match(p.stem)}
    for meta in folder.glob("*.json"):
        if ID.match(meta.stem) and meta.stem not in htmls:
            orphans.append(meta.stem)
    for stem in sorted(htmls):
        page = folder / f"{stem}.html"
        info = page.stat()
        item = Item(
            id=stem,
            created=datetime.fromtimestamp(info.st_mtime, timezone.utc),
            size=info.st_size,
        )
        meta_path = folder / f"{stem}.json"
        try:
            meta = json.loads(meta_path.read_text())
            if not isinstance(meta, dict):
                raise ValueError
        except (OSError, ValueError):
            item.meta_ok = False
            items.append(item)
            continue
        item.title = str(meta.get("title") or item.title)[:200]
        item.publisher = str(meta.get("publisher") or "")[:100]
        item.expires = parse_time(meta.get("expires"))
        item.pinned = meta.get("pinned") is True
        items.append(item)
    return items, orphans


def remove(data: Path, artifact_id: str) -> None:
    for suffix in ("html", "json"):
        try:
            (data / "a" / f"{artifact_id}.{suffix}").unlink()
        except FileNotFoundError:
            pass


def write_index(data: Path, document: dict) -> None:
    fd, tmp = tempfile.mkstemp(dir=data, prefix=".index-")
    with os.fdopen(fd, "w") as handle:
        json.dump(document, handle, indent=1)
    os.chmod(tmp, 0o644)
    os.replace(tmp, data / "index.json")


def sweep(data: Path, now: datetime, limits: Limits, dry_run: bool = False) -> dict:
    items, orphans = load(data)
    kept, removed = plan(items, now, limits)
    previous: list = []
    try:
        previous = json.loads((data / "index.json").read_text()).get("removed", [])
    except (OSError, ValueError, AttributeError):
        pass
    log = [
        {"id": item.id, "title": item.title, "reason": reason, "at": stamp(now)}
        for item, reason in removed
    ] + [{"id": oid, "title": "", "reason": "orphan metadata", "at": stamp(now)} for oid in orphans]
    document = {
        "generated": stamp(now),
        "count": len(kept),
        "bytes": sum(i.size for i in kept),
        "limits": {
            "default_ttl_days": limits.default_ttl.days,
            "max_ttl_days": limits.max_ttl.days,
            "max_pinned": limits.max_pinned,
            "quota_bytes": limits.quota_bytes,
            "max_items": limits.max_items,
        },
        "items": [
            {
                "id": i.id,
                "title": i.title,
                "publisher": i.publisher,
                "created": stamp(i.created),
                "expires": stamp(i.expires) if i.expires else None,
                "pinned": i.pinned,
                "size": i.size,
            }
            for i in sorted(kept, key=lambda i: (i.pinned, i.expires or now, i.id))
        ],
        "removed": (log + previous)[:KEEP_REMOVED],
    }
    if not dry_run:
        for entry in log:
            remove(data, entry["id"])
        write_index(data, document)
    return document | {"just_removed": log}


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--data", type=Path, required=True)
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--quota-bytes", type=int, default=QUOTA_BYTES)
    parser.add_argument("--max-items", type=int, default=MAX_ITEMS)
    args = parser.parse_args(argv)
    limits = Limits(quota_bytes=args.quota_bytes, max_items=args.max_items)
    result = sweep(args.data, datetime.now(timezone.utc), limits, args.dry_run)
    for entry in result["just_removed"]:
        print(f"{'would remove' if args.dry_run else 'removed'} {entry['id']} ({entry['reason']}) {entry['title']}")
    print(f"{result['count']} live, {result['bytes']} bytes")
    return 0


if __name__ == "__main__":
    sys.exit(main())
