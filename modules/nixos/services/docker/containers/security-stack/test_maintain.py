"""Check retention cannot remove unrelated or current-day indices."""

import datetime
import unittest

import maintain


class RetentionTest(unittest.TestCase):
    """Verify the retention boundary using index metadata."""

    def test_expire_only_old_wazuh_indices(self):
        """Preserve current events, security configuration, and other applications."""
        indices = [
            {"index": name, "store.size": "100"}
            for name in [
                "wazuh-alerts-4.x-2026.10.20",
                "wazuh-alerts-4.x-2026.10.24",
                "wazuh-alerts-4.x-2026.10.25",
                ".opendistro_security",
                "other-2026.10.20",
            ]
        ]
        self.assertEqual(
            maintain.expired_indices(indices, 3, datetime.date(2026, 10, 25)),
            ["wazuh-alerts-4.x-2026.10.20"],
        )


if __name__ == "__main__":
    unittest.main()
