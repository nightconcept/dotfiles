#!/usr/bin/env python3
"""Prepare and apply tracked BookOrbit audiobook metadata batches on Rinoa."""

import argparse
import datetime
import json
import re
import subprocess
import sys
from pathlib import Path
from typing import Any

REMOTE = Path(__file__).with_name("bookorbit.mjs")
ROOT = Path.home() / ".local/share/bookorbit-metadata"


def save(path, value):
    """Replace a progress file atomically after each operation."""
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(value, indent=2) + "\n")
    temporary.replace(path)


def remote(operation, **kwargs):
    """Use the existing active admin session without copying secrets off Rinoa."""
    query = (
        "select s.id,s.user_id,s.token_version,s.authentication_method from auth_sessions s "
        "join users u on u.id=s.user_id where u.is_superuser and u.active "
        "and s.revoked_at is null and s.expires_at>now() and s.token_version=u.token_version "
        "order by s.id desc limit 1"
    )
    session = (
        subprocess.check_output(
            [
                "ssh",
                "-o",
                "BatchMode=yes",
                "rinoa",
                "docker exec -i bookorbit-db psql -U bookorbit -d bookorbit -At",
            ],
            input=query.encode(),
        )
        .decode()
        .strip()
    )
    if not session:
        raise RuntimeError("No active BookOrbit admin session; log into BookOrbit and retry")
    sid, uid, version, method = session.split("|")
    payload = dict(
        operation=operation,
        session=dict(sid=int(sid), sub=int(uid), ver=int(version), amr=method),
        **kwargs,
    )
    # Feed the program as an argument and the operation as stdin; no credential enters argv.
    import shlex

    command = "docker exec -i bookorbit node --input-type=module -e " + shlex.quote(
        REMOTE.read_text()
    )
    process = subprocess.run(
        ["ssh", "-o", "BatchMode=yes", "rinoa", command],
        input=json.dumps(payload).encode(),
        capture_output=True,
    )
    if not process.stdout:
        raise RuntimeError("Remote operation failed before returning a result")
    output = json.loads(process.stdout)
    if "error" in output:
        raise RuntimeError(output["error"])
    return output["result"]


def title_key(title):
    """Normalize title punctuation and a trailing track-part suffix."""
    title = re.sub(r"\s*[-–—:]?\s*Part\s+\d+\s*$", "", title or "", flags=re.I)
    return re.sub(r"[^\w]+", "", title.casefold())


def matching(book, candidate):
    """Require title, contributor, language, and measured runtime agreement."""
    ids = book.get("providerIds") or {}
    existing_id = ids.get("audibleId") or ids.get("audible")
    if existing_id and existing_id != candidate.get("audibleId", candidate.get("providerId")):
        return False
    titles = {
        title_key(book["title"]),
        title_key((book["title"] or "") + " " + (book.get("subtitle") or "")),
    }
    candidate_titles = {
        title_key(candidate.get("title")),
        title_key(candidate.get("title", "") + " " + candidate.get("subtitle", "")),
    }
    if not titles.intersection(candidate_titles):
        return False
    authors = {a["name"].casefold() for a in book["authors"]}
    source_authors = {a.casefold() for a in candidate.get("authors", [])}
    contributors = source_authors | {a.casefold() for a in candidate.get("narrators", [])}
    duration = (book.get("audioMetadata") or {}).get("durationSeconds")
    source_duration = candidate.get("durationSeconds")
    narrators = {
        n["name"].casefold() for n in (book.get("audioMetadata") or {}).get("narrators", [])
    }
    return bool(
        authors & source_authors
        and authors <= contributors
        and (not narrators or narrators <= contributors)
        and candidate.get("language", "").lower() in ("en", "english")
        and duration
        and source_duration
        and abs(duration - source_duration) <= 120
    )


def make_patch(book, source):
    """Fill provider metadata while retaining protected local values."""
    patch = {
        key: source[key]
        for key in (
            "title",
            "subtitle",
            "authors",
            "publisher",
            "publishedDate",
            "publishedYear",
            "audibleId",
            "seriesName",
            "seriesIndex",
            "seriesMemberships",
        )
        if source.get(key) is not None
    }
    # Keep existing descriptions; indexed provider snippets can end with an ellipsis.
    if not book.get("description") and source.get("description"):
        patch["description"] = source["description"]
    patch["language"] = "en"
    patch["genres"] = list(dict.fromkeys(book["genres"] + source.get("genres", [])))
    patch["audioMetadata"] = {
        key: source[key] for key in ("narrators", "abridged") if key in source
    }
    audio = book.get("audioMetadata") or {}
    if audio.get("chaptersSource") == "tracks" and audio.get("chapters"):
        patch["audioMetadata"]["chapters"] = audio["chapters"]
    if source.get("communityRating") is not None:
        patch["communityRatings"] = [
            {key: r[key] for key in ("provider", "rating", "ratingCount") if key in r}
            for r in book.get("communityRatings", [])
            if r["provider"] != "audible"
        ] + [
            dict(
                provider="audible",
                rating=source["communityRating"],
                ratingCount=source.get("communityRatingCount"),
            )
        ]
    for key in book["lockedFields"]:
        patch.pop(key, None)
        if "audioMetadata" in patch:
            patch["audioMetadata"].pop(key.removeprefix("audioMetadata."), None)
    return patch


def prepare(path, ids):
    """Snapshot a batch and prepare unique Audible matches."""
    if path.exists():
        raise RuntimeError("Batch exists; use a new filename to preserve its history")
    batch: dict[str, Any] = dict(
        date=datetime.date.today().isoformat(), status="prepared", items=[]
    )
    books = remote("snapshot", ids=ids)
    for book in books:
        item = dict(id=book["id"], status="pending", before=book, candidates=[])
        batch["items"].append(item)
        save(path, batch)
        try:
            candidates = remote("search", book=book, provider="audible")
            item["candidates"] = candidates
            matches = {c["providerId"]: c for c in candidates if matching(book, c)}
            if len(matches) == 1:
                source = next(iter(matches.values()))
                item.update(
                    status="ready",
                    patch=make_patch(book, source),
                    cover=source.get("coverUrl"),
                    source_url="https://www.audible.com/pd/" + source["providerId"],
                    match_reason="Unique title/author/English/runtime match within 120 seconds",
                )
            else:
                item.update(
                    status="needs_review", reason="No unique title/author/language/runtime match"
                )
        except RuntimeError as error:
            item.update(status="needs_review", reason=str(error))
        save(path, batch)
        print(book["id"], item["status"], book["title"], flush=True)


def apply(path):
    """Apply prepared patches and save a result after each entry."""
    batch = json.loads(path.read_text())
    for item in batch["items"]:
        if item["status"] != "ready":
            continue
        item["status"] = "applying"
        save(path, batch)
        try:
            item["result"] = remote(
                "apply", book=item["before"], patch=item["patch"], cover=item.get("cover")
            )
            item["status"] = "applied"
        except RuntimeError as error:
            # A failed response may follow a successful mutation. Audit instead of retrying blindly.
            item.update(status="needs_audit", error=str(error))
        save(path, batch)
        print(item["id"], item["status"], flush=True)
    batch["status"] = (
        "applied_with_holds" if any(i["status"] != "applied" for i in batch["items"]) else "applied"
    )
    save(path, batch)


def audit(path):
    """Read changed entries and record integrity checks."""
    batch = json.loads(path.read_text())
    for item in batch["items"]:
        if item["status"] not in ("applied", "needs_audit", "applying", "audited"):
            continue
        try:
            item["audit"] = remote("audit", book=item["before"], patch=item["patch"])
            item["status"] = "audited"
            previous_error = item.pop("error", None)
            if previous_error:
                item.setdefault("error_history", []).append(previous_error)
        except RuntimeError as error:
            item.update(status="needs_audit", error=str(error))
        save(path, batch)
        print(item["id"], item["status"], flush=True)
    batch["status"] = (
        "reviewed"
        if all(i["status"] == "audited" for i in batch["items"])
        else "reviewed_with_holds"
    )
    save(path, batch)


def inventory(count):
    """Select unreviewed audiobooks by metadata score."""
    reviewed = set()
    for path in ROOT.glob("batch-*.json"):
        record = json.loads(path.read_text())
        if not isinstance(record, dict):
            continue
        for item in record.get("items", []):
            reviewed.add(int(item["id"]))
    excluded = ",".join(map(str, sorted(reviewed))) or "0"
    query = (
        "select b.id from books b join book_metadata m on m.book_id=b.id "
        f"where b.library_id=2 and b.status='present' and b.id not in ({excluded}) "
        f"order by m.metadata_score nulls first,b.id limit {count}"
    )
    return (
        subprocess.check_output(
            [
                "ssh",
                "-o",
                "BatchMode=yes",
                "rinoa",
                "docker exec -i bookorbit-db psql -U bookorbit -d bookorbit -At",
            ],
            input=query.encode(),
        )
        .decode()
        .split()
    )


def main():
    """Run the requested batch operation."""
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    p = sub.add_parser("prepare")
    p.add_argument("batch", type=Path)
    p.add_argument("--ids", type=int, nargs="+")
    p.add_argument("--count", type=int, default=10)
    for command in ("apply", "audit"):
        p = sub.add_parser(command)
        p.add_argument("batch", type=Path)
    p = sub.add_parser("automation")
    p.add_argument("--ids", nargs="+", type=int, default=[1, 2])
    args = parser.parse_args()
    if args.command == "prepare":
        if not 1 <= args.count <= 50:
            parser.error("--count must be between 1 and 50")
        prepare(args.batch, args.ids or [int(i) for i in inventory(args.count)])
    elif args.command == "automation":
        save(ROOT / "automation-settings.json", remote("automation", ids=args.ids, audio=True))
        print("Enabled file writing, audio tags, and renaming; settings saved")
    else:
        {"apply": apply, "audit": audit}[args.command](args.batch)


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, subprocess.CalledProcessError) as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
