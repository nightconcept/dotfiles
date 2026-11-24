"""Run with: python3 -m unittest test_sweep (from this folder)."""
import json
import os
import tempfile
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path

import sweep

NOW = datetime(2026, 11, 24, 12, 0, tzinfo=timezone.utc)
DAY = timedelta(days=1)


def item(name, age_days=0, expires=None, pinned=False, size=10):
    return sweep.Item(id=name.ljust(16, "0"), created=NOW - age_days * DAY, size=size, expires=expires, pinned=pinned)


class PlanTests(unittest.TestCase):
    def removed_ids(self, items, limits=None):
        _, removed = sweep.plan(items, NOW, limits or sweep.Limits())
        return {i.id[:3]: reason for i, reason in removed}

    def test_missing_expiry_defaults_to_fourteen_days(self):
        self.assertEqual(self.removed_ids([item("old", 15), item("new", 13)]), {"old": "expired"})

    def test_expiry_is_cut_back_to_ninety_days_from_creation(self):
        far = item("far", 91, expires=NOW + 400 * DAY)
        self.assertEqual(self.removed_ids([far]), {"far": "expired"})
        near = item("nea", 80, expires=NOW + 400 * DAY)
        kept, _ = sweep.plan([near], NOW, sweep.Limits())
        self.assertEqual(kept[0].expires, NOW - 80 * DAY + 90 * DAY)

    def test_pinned_never_expires(self):
        self.assertEqual(self.removed_ids([item("pin", 500, pinned=True)]), {})

    def test_only_newest_pins_count(self):
        pins = [item(f"p{n:02d}", age_days=n, pinned=True) for n in range(22)]
        kept, removed = sweep.plan(pins, NOW, sweep.Limits(max_pinned=20))
        self.assertEqual(sum(1 for i in kept if i.pinned), 20)
        # the two oldest pins fall back to the normal rules, and are past 14 days
        self.assertEqual({i.id[:3] for i, _ in removed}, {"p20", "p21"})

    def test_quota_evicts_soonest_expiring_first_and_spares_pins(self):
        items = [
            item("soo", 1, expires=NOW + 1 * DAY, size=60),
            item("lat", 1, expires=NOW + 9 * DAY, size=60),
            item("pin", 1, pinned=True, size=60),
        ]
        self.assertEqual(self.removed_ids(items, sweep.Limits(quota_bytes=130)), {"soo": "quota"})

    def test_count_limit(self):
        items = [item(f"i{n:02d}", 0, expires=NOW + (n + 1) * DAY) for n in range(5)]
        removed = self.removed_ids(items, sweep.Limits(max_items=3))
        self.assertEqual(set(removed), {"i00", "i01"})


class DiskTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.data = Path(self.tmp.name)
        (self.data / "a").mkdir()

    def tearDown(self):
        self.tmp.cleanup()

    def put(self, name, meta=None, age_days=0, raw_meta=None):
        stem = name.ljust(16, "0")
        page = self.data / "a" / f"{stem}.html"
        page.write_text("<!doctype html><title>x</title>")
        stamp = (NOW - age_days * DAY).timestamp()
        os.utime(page, (stamp, stamp))
        if meta is not None or raw_meta is not None:
            (self.data / "a" / f"{stem}.json").write_text(raw_meta if raw_meta is not None else json.dumps(meta))
        return stem

    def test_sweep_removes_expired_and_writes_index(self):
        gone = self.put("aaaa", {"title": "Old", "expires": sweep.stamp(NOW - DAY)}, age_days=5)
        keep = self.put("bbbb", {"title": "Fresh", "expires": sweep.stamp(NOW + 3 * DAY)})
        result = sweep.sweep(self.data, NOW, sweep.Limits())
        self.assertFalse((self.data / "a" / f"{gone}.html").exists())
        self.assertFalse((self.data / "a" / f"{gone}.json").exists())
        index = json.loads((self.data / "index.json").read_text())
        self.assertEqual([i["id"] for i in index["items"]], [keep])
        self.assertEqual(index["removed"][0]["reason"], "expired")
        self.assertEqual(result["count"], 1)

    def test_dry_run_changes_nothing(self):
        gone = self.put("aaaa", {"expires": sweep.stamp(NOW - DAY)}, age_days=5)
        sweep.sweep(self.data, NOW, sweep.Limits(), dry_run=True)
        self.assertTrue((self.data / "a" / f"{gone}.html").exists())
        self.assertFalse((self.data / "index.json").exists())

    def test_who_published_is_indexed_and_survives_removal(self):
        who = {"publisher": "red-star", "agent": "claude-code", "model": "claude-sonnet-5-5", "session": "sess-1", "host": "terra", "source": "r@abc"}
        keep = self.put("aaaa", {"title": "Kept", "expires": sweep.stamp(NOW + DAY), **who})
        self.put("bbbb", {"title": "Gone", "expires": sweep.stamp(NOW - DAY), **who}, age_days=3)
        sweep.sweep(self.data, NOW, sweep.Limits())
        index = json.loads((self.data / "index.json").read_text())
        item = index["items"][0]
        self.assertEqual((item["id"], item["model"], item["session"], item["host"], item["source"]),
                         (keep, "claude-sonnet-5-5", "sess-1", "terra", "r@abc"))
        self.assertEqual((index["removed"][0]["publisher"], index["removed"][0]["session"]), ("red-star", "sess-1"))

    def test_who_fields_are_cut_to_length(self):
        self.put("aaaa", {"session": "s" * 500, "expires": sweep.stamp(NOW + DAY)})
        sweep.sweep(self.data, NOW, sweep.Limits())
        index = json.loads((self.data / "index.json").read_text())
        self.assertEqual(len(index["items"][0]["session"]), 200)

    def test_bad_or_missing_metadata_still_expires_on_the_default(self):
        self.put("dead", age_days=20)
        self.put("beef", raw_meta="{not json", age_days=1)
        result = sweep.sweep(self.data, NOW, sweep.Limits())
        self.assertEqual(result["count"], 1)

    def test_orphan_metadata_is_removed(self):
        orphan = self.data / "a" / ("c" * 16 + ".json")
        orphan.write_text("{}")
        sweep.sweep(self.data, NOW, sweep.Limits())
        self.assertFalse(orphan.exists())

    def test_foreign_files_are_left_alone(self):
        stranger = self.data / "a" / "notes.txt"
        stranger.write_text("x")
        sweep.sweep(self.data, NOW, sweep.Limits())
        self.assertTrue(stranger.exists())


if __name__ == "__main__":
    unittest.main()
