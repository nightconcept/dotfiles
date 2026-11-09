"""Offline checks for edition matching and preservation of protected metadata."""

import contextlib
import copy
import io
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

    def test_preparation_replaces_portrait_but_keeps_square_artwork(self):
        """Replace ebook-shaped art without replacing suitable square artwork."""
        for width, height, expected in [(300, 500, True), (300, 300, True), (500, 500, False)]:
            book = dict(self.book, id=10, covers={"audio": {"width": width, "height": height}})
            source = dict(
                self.source, providerId="FAKE000001", coverUrl="https://example.test/cover.jpg"
            )
            with (
                tempfile.TemporaryDirectory() as directory,
                mock.patch.object(cleanup, "remote", side_effect=[[book], [source]]),
                contextlib.redirect_stdout(io.StringIO()),
            ):
                path = Path(directory) / "batch.json"
                cleanup.prepare(path, [10])
                item = json.loads(path.read_text())["items"][0]
                self.assertEqual(item["status"], "ready")
                self.assertEqual(item["replace_cover"], expected)

    def test_save_rejects_repository_paths(self):
        """Never write library records into the dotfiles repository."""
        with self.assertRaises(ValueError):
            cleanup.save(cleanup.REPOSITORY / "private-library-data.json", {"items": []})

    def test_audiobook_score_prioritizes_essentials_and_review(self):
        """Square covers and actual review matter; populated fields are not verified."""
        book: dict[str, Any] = dict(
            self.book, id=10, metadataScore=70, covers={"audio": {"width": 500, "height": 500}}
        )
        score = cleanup.metadata_score(book, "audiobook")
        self.assertEqual(score["score"], 82)
        self.assertFalse(score["reviewed"])
        self.assertEqual(
            cleanup.metadata_score(book, "audiobook", reviewed=True, held=True)["score"], 87
        )
        book["covers"]["audio"]["width"] = 300
        self.assertEqual(cleanup.metadata_score(book, "audiobook")["score"], 57)

    def test_book_and_comic_portrait_covers_and_generic_titles(self):
        """Portrait books and comics qualify; a volume-only title is flagged."""
        book: dict[str, Any] = dict(
            self.book,
            id=11,
            title="A Real Title",
            metadataScore=70,
            covers={"ebook": {"width": 500, "height": 750}},
        )
        for medium in ("book", "comic"):
            self.assertEqual(cleanup.metadata_score(book, medium)["score"], 82)
            book["covers"]["ebook"]["width"] = 499
            self.assertEqual(cleanup.metadata_score(book, medium)["score"], 57)
            book["covers"]["ebook"]["width"] = 500
        book["title"] = "v01"
        score = cleanup.metadata_score(book, "comic")
        self.assertTrue(score["title_needs_review"])
        self.assertEqual(score["score"], 57)

    def test_cover_only_pass_does_not_count_as_metadata_review(self):
        """A cover-only cleanup must not remove an audiobook from future review."""
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "batch-003.json").write_text(
                json.dumps({"items": [{"id": 1, "status": "audited"}]})
            )
            (root / "batch-003.covers.json").write_text(
                json.dumps({"items": [{"id": 2, "status": "audited"}]})
            )
            with mock.patch.object(cleanup, "ROOT", root):
                reviewed, _, seen = cleanup.review_state()
                self.assertEqual(reviewed, {1})
                self.assertEqual(seen, {1})

    def test_inventory_respects_custom_score_cutoff_and_seen_entries(self):
        """Keep in-progress entries out and use our score rather than BookOrbit's."""
        scored = [{"id": 1, "score": 50}, {"id": 2, "score": 82}, {"id": 3, "score": 90}]
        with mock.patch.object(cleanup, "scores", return_value=(scored, {1})):
            self.assertEqual(cleanup.inventory(10), ["2"])
            self.assertEqual(cleanup.inventory(10, 82), [])
            with self.assertRaises(ValueError):
                cleanup.inventory(10, 101)

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
