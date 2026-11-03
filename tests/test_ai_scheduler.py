"""Check Rotom lease detection with a local status command."""

import os
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from modules.linux.ai import scheduler


class SchedulerTest(unittest.TestCase):
    """Exercise the deployed shell pipeline against status fixtures."""

    def test_gpu_window(self):
        """Recognize both status shapes and tolerate unavailable status."""
        with tempfile.TemporaryDirectory(prefix="scheduler test ") as directory:
            binary = Path(directory) / ".local/bin/rotom"
            binary.parent.mkdir(parents=True)
            for status, expected in (
                ('{"gpu_leases": true}', True),
                ('{"terra": {"gpu_leases": true}}', True),
                ('{"gpu_leases": false}', False),
                ('{"gpu_leases": false, "terra": {"gpu_leases": true}}', False),
                ("{}", False),
                ("unavailable", False),
            ):
                with self.subTest(status=status):
                    binary.write_text("#!/bin/sh\ncat <<'STATUS'\n" + status + "\nSTATUS\n")
                    binary.chmod(0o755)
                    with (
                        patch.dict(os.environ, {"HOME": directory}),
                        patch.object(scheduler, "host") as host,
                    ):
                        host.get_fact.side_effect = lambda fact, command: subprocess.check_output(
                            command, shell=True, text=True
                        )
                        self.assertEqual(scheduler.gpu_window_open(), expected)


if __name__ == "__main__":
    unittest.main()
