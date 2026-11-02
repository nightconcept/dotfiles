"""Check yuffie's flake update policy: cooldown, new-revision trigger and retry limit."""

import importlib.util
import tempfile
import unittest
from pathlib import Path

SCRIPT = (
    Path(__file__).resolve().parents[1] / "modules/nixos/services/flake-updater/flake_updater.py"
)
spec = importlib.util.spec_from_file_location("flake_updater", SCRIPT)
updater = importlib.util.module_from_spec(spec)
spec.loader.exec_module(updater)

NOW = 1_800_000_000.0
OLD, NEW = "a" * 40, "b" * 40


def decide(state, latest=NEW, locked=OLD):
    """Calls decide with the production defaults: 7-day cooldown, 2 attempts."""
    return updater.decide(state, NOW, latest, locked, cooldown_days=7, max_attempts=2)


class DecideTest(unittest.TestCase):
    """Covers each rule in decide()."""

    def test_new_unstable_runs(self):
        """A new revision with no history runs."""
        self.assertIsNone(decide(updater.State()))

    def test_cooldown_skips_within_a_week(self):
        """A push six days ago blocks the update."""
        state = updater.State(last_push=NOW - 6 * updater.DAY)
        self.assertIn("cooldown", decide(state))

    def test_cooldown_ends_after_a_week(self):
        """A push eight days ago no longer blocks the update."""
        state = updater.State(last_push=NOW - 8 * updater.DAY)
        self.assertIsNone(decide(state))

    def test_same_revision_skips(self):
        """Nothing runs when flake.lock already has the newest revision."""
        self.assertIn("already", decide(updater.State(), latest=OLD))

    def test_one_failure_retries_next_night(self):
        """A revision that failed once is tried again."""
        self.assertIsNone(decide(updater.State(attempts={NEW: 1})))

    def test_two_failures_wait_for_newer_revision(self):
        """A revision that failed twice is skipped; a newer one runs."""
        state = updater.State(attempts={NEW: 2})
        self.assertIn("waiting", decide(state))
        self.assertIsNone(decide(state, latest="c" * 40))


class StateTest(unittest.TestCase):
    """Covers state persistence and flake.lock parsing."""

    def test_round_trip(self):
        """Saved state loads back unchanged."""
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "state.json"
            state = updater.State(last_push=NOW, attempts={NEW: 1}, consecutive_failures=2)
            state.save(path)
            self.assertEqual(updater.State.load(path), state)

    def test_missing_file_is_empty_state(self):
        """A first run starts with no history."""
        self.assertEqual(updater.State.load(Path("/nonexistent/state.json")), updater.State())

    def test_locked_rev_follows_root_input(self):
        """The rev comes from the node that the root's nixpkgs input names."""
        lock = {
            "root": "root",
            "nodes": {
                "root": {"inputs": {"nixpkgs": "nixpkgs_2"}},
                "nixpkgs": {"locked": {"rev": OLD}},
                "nixpkgs_2": {"locked": {"rev": NEW}},
            },
        }
        self.assertEqual(updater.locked_nixpkgs_rev(lock), NEW)


if __name__ == "__main__":
    unittest.main()
