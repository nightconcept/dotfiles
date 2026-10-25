"""Check delivery, restart, rotation, partial writes and failed requests."""

import json
import tempfile
import unittest
from pathlib import Path
from unittest import mock

import gotify_bridge


class BridgeTest(unittest.TestCase):
    """Exercise the persisted cursor with actual EVE files."""

    def test_resume_retry_rotation_and_partial_lines(self):
        """Never checkpoint an undelivered alert or an incomplete record."""
        with tempfile.TemporaryDirectory() as directory:
            log = Path(directory) / "eve.json"
            state = Path(directory) / "position.json"
            alert = json.dumps({"event_type": "alert", "alert": {"signature": "test"}})
            log.write_text('{"event_type":"flow"}\ninvalid\n' + alert + "\n")
            send = mock.Mock(side_effect=OSError("offline"))
            with self.assertRaises(OSError):
                gotify_bridge.forward(log, state, send)
            send.side_effect = None
            gotify_bridge.forward(log, state, send)
            gotify_bridge.forward(log, state, send)
            self.assertEqual(send.call_count, 2)
            with log.open("a") as output:
                output.write(alert)
            gotify_bridge.forward(log, state, send)
            self.assertEqual(send.call_count, 2)
            with log.open("a") as output:
                output.write("\n")
            log.rename(log.with_suffix(".json.1"))
            log.write_text(alert + "\n")
            gotify_bridge.forward(log, state, send)
            gotify_bridge.forward(log, state, send)
            self.assertEqual(send.call_count, 4)
            log.write_text("{}\n")
            gotify_bridge.forward(log, state, send)
            self.assertEqual(json.loads(state.read_text())["offset"], 3)

    def test_gotify_request(self):
        """Use Gotify authentication headers and exclude packet payloads."""
        with mock.patch("gotify_bridge.request.urlopen") as urlopen:
            gotify_bridge.notify(
                {"alert": {"signature": "test"}, "payload": "private"},
                "http://gotify/",
                "secret",
            )
            req = urlopen.call_args.args[0]
            self.assertEqual(req.full_url, "http://gotify/message")
            self.assertEqual(req.get_header("X-gotify-key"), "secret")
            self.assertNotIn("private", req.data.decode())
            self.assertNotIn("secret", req.full_url)


if __name__ == "__main__":
    unittest.main()
