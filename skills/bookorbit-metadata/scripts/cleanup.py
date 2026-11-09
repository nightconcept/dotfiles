#!/usr/bin/env python3
"""Prepare and apply tracked BookOrbit audiobook metadata batches on Rinoa."""

import argparse
import base64
import datetime
import json
import re
import subprocess
import sys
from pathlib import Path
from typing import Any

REMOTE = Path(__file__).with_name("bookorbit.mjs")
REPOSITORY = Path(__file__).resolve().parents[3]
ROOT = Path.home() / ".local/share/bookorbit-metadata"
LIBRARIES = {1: "book", 2: "audiobook", 4: "comic"}


def save(path, value):
    """Replace a progress file atomically after each operation."""
    if path.resolve().is_relative_to(REPOSITORY):
        raise ValueError("Library data must be stored outside the dotfiles repository")
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
                    replace_cover=bool(
                        book["covers"].get("audio")
                        and (
                            not book["covers"]["audio"].get("width")
                            or not book["covers"]["audio"].get("height")
                            or min(
                                book["covers"]["audio"]["width"], book["covers"]["audio"]["height"]
                            )
                            < 500
                            or abs(
                                book["covers"]["audio"]["width"] - book["covers"]["audio"]["height"]
                            )
                            > max(
                                book["covers"]["audio"]["width"], book["covers"]["audio"]["height"]
                            )
                            * 0.05
                        )
                    ),
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
            cover_data = None
            if item.get("cover_file"):
                content = Path(item["cover_file"]).read_bytes()
                if not content.startswith(b"\x89PNG\r\n\x1a\n") or len(content) > 20_000_000:
                    raise RuntimeError("Cover must be a PNG smaller than 20 MB")
                cover_data = {
                    "base64": base64.b64encode(content).decode(),
                    "contentType": "image/png",
                }
            item["result"] = remote(
                "apply",
                book=item["before"],
                patch=item["patch"],
                cover=item.get("cover"),
                replaceCover=item.get("replace_cover", False),
                coverData=cover_data,
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


def review_state():
    """Collect reviewed entries and documented holds from the metadata batches."""
    reviewed, held, seen = set(), set(), set()
    for path in ROOT.glob("batch-*.json"):
        record = json.loads(path.read_text())
        if not isinstance(record, dict):
            continue
        if not re.fullmatch(r"batch-\d+\.json", path.name):
            continue
        for item in record.get("items", []):
            seen.add(int(item["id"]))
            if item.get("status") in (
                "audited",
                "applied_and_reviewed",
            ):
                reviewed.add(int(item["id"]))
                if item.get("held_fields") or item.get("remaining_issues"):
                    held.add(int(item["id"]))
    progress = ROOT / "progress.json"
    if progress.exists():
        held.update(json.loads(progress.read_text()).get("edition_holds", []))
    return reviewed, held, seen


def metadata_score(book, medium, reviewed=False, held=False):
    """Score essentials and review evidence without claiming unchecked fields are correct."""
    cover_key = "audio" if medium == "audiobook" else "ebook"
    cover = (book.get("covers") or {}).get(cover_key) or {}
    width, height = cover.get("width") or 0, cover.get("height") or 0
    title = (book.get("title") or "").strip()
    generic_title = bool(
        re.fullmatch(r"(?:v|vol(?:ume)?|ch(?:apter)?|issue|part)[ ._-]*\d+", title, re.I)
    )
    if medium == "audiobook":
        cover_ok = min(width, height) >= 500 and abs(width - height) <= max(width, height) * 0.05
    else:
        cover_ok = width >= 500 and height >= 700 and 0.45 <= width / height <= 0.90
    parts = {
        "title_present": 25 if title and not generic_title else 0,
        "author_present": 25
        if any((a.get("name") or "").strip() for a in book.get("authors", []))
        else 0,
        "suitable_cover": 25 if cover_ok else 0,
        "metadata_reviewed": 15 if reviewed else 0,
        "documented_uncertainty": -10 if held else 0,
        "bookorbit_score": max(0, min(100, book.get("metadataScore") or 0)) // 10,
    }
    return {
        "id": book["id"],
        "title": book.get("title"),
        "medium": medium,
        "cover_dimensions": {"width": width or None, "height": height or None},
        "title_needs_review": generic_title or not title,
        "score": max(0, sum(parts.values())),
        "points": parts,
        "bookorbit_score": book.get("metadataScore"),
        "reviewed": reviewed,
        "documented_uncertainty": held,
    }


def scores(medium="audiobook"):
    """Score the selected libraries using BookOrbit data and tracked reviews."""
    library_ids = [str(key) for key, value in LIBRARIES.items() if medium in ("all", value)]
    if not library_ids:
        raise ValueError("Unknown medium")
    query = (
        f"select id from books where library_id in ({','.join(library_ids)}) "
        "and status='present' order by id"
    )
    ids = [
        int(i)
        for i in subprocess.check_output(
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
    ]
    reviewed, held, seen = review_state()
    books = remote("score-snapshot", ids=ids) if ids else []
    result = [
        metadata_score(b, LIBRARIES[b["libraryId"]], b["id"] in reviewed, b["id"] in held)
        for b in books
    ]
    return sorted(
        result,
        key=lambda item: (
            item["score"],
            item["bookorbit_score"] if item["bookorbit_score"] is not None else -1,
            item["id"],
        ),
    ), seen


def inventory(count, cutoff=90):
    """Select the least complete unreviewed audiobooks below our score cutoff."""
    if not 1 <= cutoff <= 100:
        raise ValueError("Cutoff must be between 1 and 100")
    scored, seen = scores()
    return [
        str(item["id"]) for item in scored if item["id"] not in seen and item["score"] < cutoff
    ][:count]


def main():
    """Run the requested batch operation."""
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    p = sub.add_parser("prepare")
    p.add_argument("batch", type=Path)
    p.add_argument("--ids", type=int, nargs="+")
    p.add_argument("--count", type=int, default=10)
    p.add_argument("--cutoff", type=int, default=90)
    for command in ("apply", "audit"):
        p = sub.add_parser(command)
        p.add_argument("batch", type=Path)
    p = sub.add_parser("score")
    p.add_argument("report", type=Path)
    p.add_argument("--medium", choices=["all", "audiobook", "book", "comic"], default="all")
    p = sub.add_parser("automation")
    p.add_argument("--ids", nargs="+", type=int, default=[1, 2])
    args = parser.parse_args()
    ROOT.mkdir(mode=0o700, parents=True, exist_ok=True)
    if args.command == "prepare":
        if not 1 <= args.count <= 50:
            parser.error("--count must be between 1 and 50")
        if not 1 <= args.cutoff <= 100:
            parser.error("--cutoff must be between 1 and 100")
        ids = args.ids or [int(i) for i in inventory(args.count, args.cutoff)]
        if not ids:
            print(f"No unreviewed audiobooks below score {args.cutoff}")
            return
        prepare(args.batch, ids)
    elif args.command == "score":
        entries, _ = scores(args.medium)
        save(
            args.report,
            {
                "date": datetime.date.today().isoformat(),
                "cutoff": 90,
                "medium": args.medium,
                "items": entries,
            },
        )
        print(f"Scored {len(entries)} entries; {sum(i['score'] < 90 for i in entries)} below 90")
    elif args.command == "automation":
        save(ROOT / "automation-settings.json", remote("automation", ids=args.ids, audio=True))
        print("Enabled file writing, audio tags, and renaming; settings saved")
    else:
        {"apply": apply, "audit": audit}[args.command](args.batch)


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, ValueError, subprocess.CalledProcessError) as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
