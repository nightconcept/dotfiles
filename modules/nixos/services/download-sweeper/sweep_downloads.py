"""Download sweeper for /mnt/titan/downloads.

Safely prunes already-imported media, spam executables, and orphaned junk
from downloads while protecting active qBittorrent torrents and in-progress
downloads.
"""

from __future__ import annotations

import argparse
import http.cookiejar
import json
import logging
import os
import shutil
import sys
import time
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET
from typing import Any

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)
logger = logging.getLogger("download-sweeper")

VIDEO_EXTS = {".mkv", ".mp4", ".avi", ".ts", ".m4v", ".webm"}
AUDIO_EXTS = {".m4b", ".mp3", ".flac"}
MEDIA_EXTS = VIDEO_EXTS | AUDIO_EXTS
JUNK_EXTS = {
    ".nfo",
    ".txt",
    ".url",
    ".exe",
    ".ds_store",
    ".lnk",
    ".html",
    ".htm",
    ".jpg",
    ".jpeg",
    ".png",
    ".gif",
    ".torrent",
    ".nzb",
}


def extract_api_key_from_xml(xml_path: str) -> str | None:
    """Extract API key from Sonarr or Radarr config.xml."""
    if not os.path.isfile(xml_path):
        return None
    try:
        tree = ET.parse(xml_path)
        root = tree.getroot()
        api_key_elem = root.find("ApiKey")
        if api_key_elem is not None and api_key_elem.text:
            return api_key_elem.text.strip()
    except Exception as e:
        logger.warning("Could not read API key from %s: %s", xml_path, e)
    return None


def get_qbittorrent_active_torrents(
    host: str,
    port: int,
    username: str,
    password_file: str,
) -> list[dict[str, Any]] | None:
    """Authenticate and fetch active torrents from qBittorrent WebUI.

    Returns a list of torrent dicts, or None if authentication/connection
    failed.
    """
    if not os.path.isfile(password_file):
        logger.warning("qBittorrent password file not found: %s", password_file)
        return None

    try:
        with open(password_file, "r", encoding="utf-8") as f:
            password = f.read().strip()
    except OSError as e:
        logger.warning("Failed to read qBittorrent password file: %s", e)
        return None

    cookie_jar = http.cookiejar.CookieJar()
    opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(cookie_jar))

    base_url = f"http://{host}:{port}"
    login_url = f"{base_url}/api/v2/auth/login"
    login_data = urllib.parse.urlencode(
        {
            "username": username,
            "password": password,
        }
    ).encode("utf-8")

    login_req = urllib.request.Request(login_url, data=login_data)
    try:
        with opener.open(login_req, timeout=10) as resp:
            resp_text = resp.read().decode("utf-8").strip()
            if resp_text != "Ok.":
                logger.warning("qBittorrent login failed: %s", resp_text)
                return None
    except Exception as e:
        logger.warning("Error connecting to qBittorrent login: %s", e)
        return None

    info_url = f"{base_url}/api/v2/torrents/info"
    info_req = urllib.request.Request(info_url)
    try:
        with opener.open(info_req, timeout=15) as resp:
            data = resp.read().decode("utf-8")
            return json.loads(data)
    except Exception as e:
        logger.warning("Error fetching torrents info from qBittorrent: %s", e)
        return None


def get_servarr_queue_titles(base_url: str, api_key: str | None) -> set[str]:
    """Fetch active queue titles from Sonarr or Radarr API."""
    if not api_key:
        return set()
    url = f"{base_url}/api/v3/queue"
    req = urllib.request.Request(url, headers={"X-Api-Key": api_key})
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            data = json.loads(resp.read().decode("utf-8"))
            records = data.get("records", [])
            titles = set()
            for r in records:
                title = r.get("title")
                if title:
                    titles.add(title)
                source_title = r.get("sourceTitle")
                if source_title:
                    titles.add(source_title)
            return titles
    except Exception as e:
        logger.debug("Could not fetch queue from %s: %s", base_url, e)
        return set()


def get_servarr_imported_paths(base_url: str, api_key: str | None) -> set[str]:
    """Fetch recently imported dropped paths from Sonarr or Radarr history."""
    if not api_key:
        return set()
    url = f"{base_url}/api/v3/history?pageSize=1000&eventType=downloadFolderImported"
    req = urllib.request.Request(url, headers={"X-Api-Key": api_key})
    try:
        with urllib.request.urlopen(req, timeout=15) as resp:
            data = json.loads(resp.read().decode("utf-8"))
            records = data.get("records", [])
            imported_paths = set()
            for r in records:
                dropped_path = r.get("data", {}).get("droppedPath")
                if dropped_path:
                    imported_paths.add(os.path.normpath(dropped_path))
            return imported_paths
    except Exception as e:
        logger.debug("Could not fetch history from %s: %s", base_url, e)
        return set()


def build_library_index(
    library_dirs: list[str],
) -> dict[int, list[str]]:
    """Index media files in destination library directories by file size."""
    size_to_paths: dict[int, list[str]] = {}
    for lib_dir in library_dirs:
        if not os.path.isdir(lib_dir):
            continue
        for root, _, files in os.walk(lib_dir):
            for file in files:
                ext = os.path.splitext(file)[1].lower()
                if ext in MEDIA_EXTS:
                    full_path = os.path.join(root, file)
                    try:
                        sz = os.path.getsize(full_path)
                        size_to_paths.setdefault(sz, []).append(full_path)
                    except OSError:
                        pass
    return size_to_paths


def prune_empty_dirs(root_dir: str, dry_run: bool) -> int:
    """Recursively remove empty subdirectories under root_dir."""
    pruned_count = 0
    for root, dirs, _ in os.walk(root_dir, topdown=False):
        if root == root_dir:
            continue
        for d in dirs:
            dir_path = os.path.join(root, d)
            try:
                if not os.listdir(dir_path):
                    if dry_run:
                        logger.info(
                            "[DRY RUN] Would remove empty directory: %s",
                            dir_path,
                        )
                    else:
                        os.rmdir(dir_path)
                        logger.info("Removed empty directory: %s", dir_path)
                    pruned_count += 1
            except OSError as e:
                logger.debug("Could not remove dir %s: %s", dir_path, e)
    return pruned_count


def sweep_downloads(
    downloads_dir: str,
    library_dirs: list[str],
    qbittorrent_host: str,
    qbittorrent_port: int,
    qbittorrent_user: str,
    qbittorrent_password_file: str,
    sonarr_url: str,
    sonarr_config: str,
    radarr_url: str,
    radarr_config: str,
    min_age_minutes: int,
    dry_run: bool,
    prune_spam_only: bool,
) -> None:
    """Perform download sweep."""
    if not os.path.isdir(downloads_dir):
        logger.error("Downloads directory does not exist: %s", downloads_dir)
        sys.exit(1)

    # Verify that parent mount is healthy (prevent acting on an empty unmounted dir)
    parent_mount = os.path.dirname(os.path.normpath(downloads_dir))
    if not os.path.isdir(parent_mount) or not os.listdir(parent_mount):
        logger.error(
            "Parent directory %s appears unmounted or empty. Aborting.",
            parent_mount,
        )
        sys.exit(1)

    now = time.time()
    min_age_seconds = min_age_minutes * 60

    logger.info(
        "Starting download sweep on %s (dry_run=%s, min_age=%dm)",
        downloads_dir,
        dry_run,
        min_age_minutes,
    )

    # 1. Query qBittorrent active torrents
    active_torrents = get_qbittorrent_active_torrents(
        qbittorrent_host,
        qbittorrent_port,
        qbittorrent_user,
        qbittorrent_password_file,
    )

    if active_torrents is None:
        logger.warning("Could not query qBittorrent! Operating in high-caution mode.")
        active_names: set[str] = set()
        active_content_paths: set[str] = set()
        active_hashes: set[str] = set()
    else:
        active_names = {t["name"] for t in active_torrents if "name" in t}
        active_content_paths = {
            os.path.normpath(t["content_path"]) for t in active_torrents if "content_path" in t
        }
        active_hashes = {t["hash"].lower() for t in active_torrents if "hash" in t}
        logger.info(
            "Active torrents in qBittorrent: %d (%s)",
            len(active_torrents),
            ", ".join(active_names) or "none",
        )

    # 2. Query Sonarr & Radarr APIs
    sonarr_api_key = extract_api_key_from_xml(sonarr_config)
    radarr_api_key = extract_api_key_from_xml(radarr_config)

    sonarr_queue = get_servarr_queue_titles(sonarr_url, sonarr_api_key)
    radarr_queue = get_servarr_queue_titles(radarr_url, radarr_api_key)
    active_queue_titles = sonarr_queue | radarr_queue
    if active_queue_titles:
        logger.info("Active queue items in Sonarr/Radarr: %d", len(active_queue_titles))

    sonarr_imported = get_servarr_imported_paths(sonarr_url, sonarr_api_key)
    radarr_imported = get_servarr_imported_paths(radarr_url, radarr_api_key)
    known_imported_paths = sonarr_imported | radarr_imported
    logger.info("Known imported paths from *arr history: %d", len(known_imported_paths))

    # 3. Index destination libraries if not spam-only
    size_to_library: dict[int, list[str]] = {}
    if not prune_spam_only:
        logger.info("Indexing library paths for exact size verification...")
        size_to_library = build_library_index(library_dirs)
        logger.info(
            "Indexed %d media files across destination libraries.",
            sum(len(v) for v in size_to_library.values()),
        )

    # 4. Scan downloads directory
    entries = sorted(os.listdir(downloads_dir))
    pruned_bytes = 0
    pruned_count = 0
    protected_count = 0
    kept_count = 0

    for item in entries:
        item_path = os.path.join(downloads_dir, item)
        norm_item_path = os.path.normpath(item_path)

        # Safety Gate: Active torrent in qBittorrent
        if item in active_names or norm_item_path in active_content_paths:
            logger.debug("Protected (active in qBittorrent): %s", item)
            protected_count += 1
            continue

        # Safety Gate: Matches active .hash.parts file
        if any(item.startswith(f".{h}") and item.endswith(".parts") for h in active_hashes):
            logger.debug("Protected (.parts for active torrent): %s", item)
            protected_count += 1
            continue

        # Safety Gate: In *arr queue
        if any(q.lower() in item.lower() for q in active_queue_titles):
            logger.debug("Protected (active in *arr queue): %s", item)
            protected_count += 1
            continue

        try:
            mtime = os.path.getmtime(item_path)
        except OSError:
            continue

        # Age gate: skip recently modified items
        if (now - mtime) < min_age_seconds:
            logger.debug("Protected (modified recently): %s", item)
            protected_count += 1
            continue

        # Check files vs directories
        if os.path.isfile(item_path):
            ext = os.path.splitext(item)[1].lower()
            try:
                sz = os.path.getsize(item_path)
            except OSError:
                continue

            # Case A: Standalone spam executable
            if ext == ".exe":
                pruned_bytes += sz
                pruned_count += 1
                if dry_run:
                    logger.info(
                        "[DRY RUN] Would delete spam executable: %s (%.2f MB)",
                        item,
                        sz / (1024**2),
                    )
                else:
                    os.unlink(item_path)
                    logger.info(
                        "Deleted spam executable: %s (%.2f MB)",
                        item,
                        sz / (1024**2),
                    )
                continue

            if prune_spam_only:
                kept_count += 1
                continue

            # Case B: Standalone media file
            if ext in MEDIA_EXTS:
                matched = size_to_library.get(sz)
                in_history = norm_item_path in known_imported_paths

                if matched or in_history:
                    match_desc = (
                        f"matches {os.path.basename(matched[0])}"
                        if matched
                        else "confirmed in *arr history"
                    )
                    pruned_bytes += sz
                    pruned_count += 1
                    if dry_run:
                        logger.info(
                            "[DRY RUN] Would prune moved media: %s (%.2f MB, %s)",
                            item,
                            sz / (1024**2),
                            match_desc,
                        )
                    else:
                        os.unlink(item_path)
                        logger.info(
                            "Pruned moved media: %s (%.2f MB, %s)",
                            item,
                            sz / (1024**2),
                            match_desc,
                        )
                else:
                    kept_count += 1
                continue

            # Case C: Standalone residual junk file
            if ext in {".ds_store", ".url"} or item.startswith("._"):
                pruned_bytes += sz
                pruned_count += 1
                if dry_run:
                    logger.info("[DRY RUN] Would delete residual junk file: %s", item)
                else:
                    os.unlink(item_path)
                    logger.info("Deleted residual junk file: %s", item)
                continue

            # Any other standalone file
            kept_count += 1

        elif os.path.isdir(item_path):
            if prune_spam_only:
                kept_count += 1
                continue

            # Inspect directory contents recursively
            subitems: list[str] = []
            for root, _, fs in os.walk(item_path):
                for f in fs:
                    subitems.append(os.path.join(root, f))

            if not subitems:
                # Empty directory
                pruned_count += 1
                if dry_run:
                    logger.info("[DRY RUN] Would delete empty folder: %s", item)
                else:
                    shutil.rmtree(item_path)
                    logger.info("Deleted empty folder: %s", item)
                continue

            media_subfiles = [f for f in subitems if os.path.splitext(f)[1].lower() in MEDIA_EXTS]

            # Case D: Directory with NO media (only junk / nfo / txt / sample / exe)
            if not media_subfiles:
                all_junk = all(os.path.splitext(f)[1].lower() in JUNK_EXTS for f in subitems)
                if all_junk:
                    dir_sz = sum(os.path.getsize(f) for f in subitems if os.path.exists(f))
                    pruned_bytes += dir_sz
                    pruned_count += 1
                    if dry_run:
                        logger.info(
                            "[DRY RUN] Would delete junk-only folder: %s (%.2f MB, %d files)",
                            item,
                            dir_sz / (1024**2),
                            len(subitems),
                        )
                    else:
                        shutil.rmtree(item_path)
                        logger.info(
                            "Deleted junk-only folder: %s (%.2f MB, %d files)",
                            item,
                            dir_sz / (1024**2),
                            len(subitems),
                        )
                else:
                    kept_count += 1
                continue

            # Case E: Directory with media files
            # Check if all media files in directory are matched in library or history
            all_media_accounted_for = True
            for mf in media_subfiles:
                norm_mf = os.path.normpath(mf)
                try:
                    msz = os.path.getsize(mf)
                    if msz in size_to_library or norm_mf in known_imported_paths:
                        continue
                    all_media_accounted_for = False
                    break
                except OSError:
                    all_media_accounted_for = False
                    break

            if all_media_accounted_for:
                dir_sz = sum(os.path.getsize(f) for f in subitems if os.path.exists(f))
                pruned_bytes += dir_sz
                pruned_count += 1
                if dry_run:
                    logger.info(
                        "[DRY RUN] Would purge moved release folder: %s"
                        " (%.2f MB, %d media files, %d total files)",
                        item,
                        dir_sz / (1024**2),
                        len(media_subfiles),
                        len(subitems),
                    )
                else:
                    shutil.rmtree(item_path)
                    logger.info(
                        "Purged moved release folder: %s (%.2f MB, %d media files, %d total files)",
                        item,
                        dir_sz / (1024**2),
                        len(media_subfiles),
                        len(subitems),
                    )
            else:
                kept_count += 1

    # 5. Clean up any leftover empty directories
    if not prune_spam_only:
        empty_pruned = prune_empty_dirs(downloads_dir, dry_run)
        pruned_count += empty_pruned

    logger.info(
        "Sweep completed. Pruned: %d items (%.2f GB freed). Protected: %d. Kept: %d.",
        pruned_count,
        pruned_bytes / (1024**3),
        protected_count,
        kept_count,
    )


def main() -> None:
    """CLI entrypoint."""
    parser = argparse.ArgumentParser(
        description="Sweep /mnt/titan/downloads and prune already-moved media."
    )
    parser.add_argument(
        "--downloads-dir",
        default="/mnt/titan/downloads",
        help="Path to downloads directory",
    )
    parser.add_argument(
        "--library-dir",
        action="append",
        dest="library_dirs",
        default=[],
        help="Destination library directory (can be specified multiple times)",
    )
    parser.add_argument(
        "--qbittorrent-host",
        default="192.168.1.117",
        help="qBittorrent host",
    )
    parser.add_argument(
        "--qbittorrent-port",
        type=int,
        default=8112,
        help="qBittorrent WebUI port",
    )
    parser.add_argument(
        "--qbittorrent-user",
        default="danny",
        help="qBittorrent username",
    )
    parser.add_argument(
        "--qbittorrent-password-file",
        default="/run/secrets/vpn/qbittorrent_password",
        help="Path to qBittorrent password file",
    )
    parser.add_argument(
        "--sonarr-url",
        default="http://127.0.0.1:8989",
        help="Sonarr base URL",
    )
    parser.add_argument(
        "--sonarr-config",
        default="/home/danny/docker/sonarr/config/config.xml",
        help="Path to Sonarr config.xml",
    )
    parser.add_argument(
        "--radarr-url",
        default="http://127.0.0.1:7878",
        help="Radarr base URL",
    )
    parser.add_argument(
        "--radarr-config",
        default="/home/danny/docker/radarr/config/config.xml",
        help="Path to Radarr config.xml",
    )
    parser.add_argument(
        "--min-age-minutes",
        type=int,
        default=60,
        help="Minimum age in minutes before a file can be pruned",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print actions without deleting anything",
    )
    parser.add_argument(
        "--prune-spam-only",
        action="store_true",
        help="Only prune spam executables and junk",
    )
    parser.add_argument(
        "--verbose",
        action="store_true",
        help="Enable verbose debug logging",
    )

    args = parser.parse_args()

    if args.verbose:
        logger.setLevel(logging.DEBUG)

    library_dirs = args.library_dirs
    if not library_dirs:
        library_dirs = [
            "/mnt/titan/TVShows",
            "/mnt/titan/Movies",
            "/mnt/titan/Audiobooks",
        ]

    sweep_downloads(
        downloads_dir=args.downloads_dir,
        library_dirs=library_dirs,
        qbittorrent_host=args.qbittorrent_host,
        qbittorrent_port=args.qbittorrent_port,
        qbittorrent_user=args.qbittorrent_user,
        qbittorrent_password_file=args.qbittorrent_password_file,
        sonarr_url=args.sonarr_url,
        sonarr_config=args.sonarr_config,
        radarr_url=args.radarr_url,
        radarr_config=args.radarr_config,
        min_age_minutes=args.min_age_minutes,
        dry_run=args.dry_run,
        prune_spam_only=args.prune_spam_only,
    )


if __name__ == "__main__":
    main()
