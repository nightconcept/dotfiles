"""Offline checks for edition matching and preservation of protected metadata."""

import copy
import json
import tempfile
import unittest
from pathlib import Path
from typing import Any
from unittest import mock

import cleanup
from cleanup import make_patch, matching


class MetadataMatchTest(unittest.TestCase):
    """Exercise edition rejection and metadata preservation."""

    def setUp(self):
        """Build local and provider records for matching tests."""
        self.book: dict[str, Any] = dict(
            title="The Clockwork Garden - Part 01",
            subtitle=None,
            authors=[dict(name="Example Author"), dict(name="Example Narrator")],
            audioMetadata=dict(durationSeconds=11944, narrators=[]),
            description="Existing description",
            genres=["Fantasy"],
            lockedFields=[],
        )
        self.source: dict[str, Any] = dict(
            title="The Clockwork Garden",
            authors=["Example Author"],
            narrators=["Example Narrator"],
            language="english",
            durationSeconds=11940,
            audibleId="FAKE000001",
            genres=["Classics"],
            description="Provider snippet...",
        )

    def test_rejects_wrong_narrator_even_with_close_runtime(self):
        """Reject a different recording with a similar length."""
        self.assertTrue(matching(self.book, self.source))
        wrong = dict(self.source, narrators=["Other Narrator"])
        self.assertFalse(matching(self.book, wrong))

    def test_rejects_other_language_and_runtime(self):
        """Reject candidates that disagree with local identity."""
        self.assertFalse(matching(self.book, dict(self.source, language="italian")))
        self.assertFalse(matching(self.book, dict(self.source, durationSeconds=9000)))
        self.assertFalse(matching(self.book, dict(self.source, authors=["Another Author"])))

    def test_rejects_conflicting_existing_edition(self):
        """Keep an existing edition identity intact."""
        self.book["providerIds"] = {"audibleId": "DIFFERENT"}
        self.assertFalse(matching(self.book, self.source))

    def test_preserves_track_chapters_before_renaming(self):
        """Keep episode names and other provider ratings."""
        audio = self.book["audioMetadata"]
        audio.update(chaptersSource="tracks", chapters=[dict(title="Episode One", startMs=0)])
        self.book["communityRatings"] = [dict(provider="goodreads", rating=4.0, ratingCount=10)]
        self.source.update(communityRating=4.5, communityRatingCount=20)
        patch = make_patch(self.book, self.source)
        self.assertEqual(patch["audioMetadata"]["chapters"], audio["chapters"])
        self.assertEqual(
            [r["provider"] for r in patch["communityRatings"]], ["goodreads", "audible"]
        )

    def test_inventory_skips_legacy_action_lists(self):
        """Exclude reviewed IDs without treating action arrays as batch records."""
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "batch-001.actions.json").write_text(json.dumps([{"id": 9}]))
            (root / "batch-001.json").write_text(json.dumps({"items": [{"id": 12}]}))
            with (
                mock.patch.object(cleanup, "ROOT", root),
                mock.patch.object(
                    cleanup.subprocess, "check_output", return_value=b"20\n"
                ) as query,
            ):
                self.assertEqual(cleanup.inventory(10), ["20"])
                self.assertIn(b"not in (12)", query.call_args.kwargs["input"])

    def test_keeps_description_genres_and_locked_fields(self):
        """Preserve local metadata and explicit field locks."""
        book = copy.deepcopy(self.book)
        book["lockedFields"] = ["title", "narrators"]
        patch = make_patch(book, self.source)
        self.assertNotIn("title", patch)
        self.assertNotIn("narrators", patch["audioMetadata"])
        self.assertNotIn("description", patch)
        self.assertEqual(patch["genres"], ["Fantasy", "Classics"])
        self.assertNotIn("durationSeconds", patch["audioMetadata"])
        self.assertNotIn("chapters", patch["audioMetadata"])
        self.assertNotIn("rating", patch)


if __name__ == "__main__":
    unittest.main()
