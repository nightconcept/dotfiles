"""Check the package boundary and security settings of generated stacks."""

import hashlib
import json
import tempfile
import unittest
from pathlib import Path
from unittest import mock

import prepare
import yaml


class PrepareTest(unittest.TestCase):
    """Exercise runtime configuration generation with representative upstream input."""

    def test_central_keeps_internal_apis_private(self):
        """Only publish agent transport and authenticated user interfaces."""
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            upstream = root / "upstream"
            upstream.mkdir()
            services = {
                name: {"image": "wazuh/test:4.14.5", "ports": ["9200:9200"], "volumes": []}
                for name in ["wazuh.manager", "wazuh.indexer", "wazuh.dashboard"]
            }
            (upstream / "docker-compose.yml").write_text(yaml.safe_dump({"services": services}))
            settings = {
                "role": "central",
                "interfaces": ["ens18"],
                "hostname": "vincent",
                "serverAddress": "192.168.1.185",
                "listenAddress": "192.168.1.185",
                "eveboxUrl": "https://evebox.local.solivan.dev",
                "retentionDays": 3,
                "gotifyTokenFile": "/run/secrets/gotify",
                "gotifyUrl": "http://gotify:80",
            }
            stack = prepare.compose(settings, upstream)
            self.assertEqual(
                set(stack["services"]),
                {"suricata", "evebox", "evebox-gotify", *services},
            )
            self.assertNotIn("ports", stack["services"]["wazuh.indexer"])
            self.assertNotIn("55000", json.dumps(stack))
            self.assertNotIn("9200:9200", json.dumps(stack))
            self.assertIn(
                "suricata-logs:/var/log/suricata:ro",
                stack["services"]["wazuh.manager"]["volumes"],
            )
            self.assertNotIn("SecretPassword", json.dumps(stack))

    def test_sensor_has_forwarders_without_central_databases(self):
        """A sensor uses authenticated forwarding and keeps both agent positions."""
        settings = {
            "role": "sensor",
            "interfaces": ["ens18", "ens19"],
            "hostname": "rinoa",
            "serverAddress": "192.168.1.185",
            "eveboxUrl": "https://evebox.local.solivan.dev",
        }
        stack = prepare.compose(settings, Path("/unused"))
        self.assertEqual(
            set(stack["services"]), {"suricata", "evebox-agent", "wazuh-agent", "evebox-gotify"}
        )
        self.assertIn("-i ens18 -i ens19", stack["services"]["suricata"]["command"][0])
        self.assertIn("EVEBOX_SERVER_KEY", stack["services"]["evebox-agent"]["environment"])
        self.assertIn("wazuh-agent-queue", stack["volumes"])
        for interfaces in [[], ["ens18; id"], ["ens18\n"]]:
            with self.assertRaises(ValueError):
                prepare.compose({**settings, "interfaces": interfaces}, Path("/unused"))

    def test_manager_configuration_only_collects_eve_and_cannot_block(self):
        """Keep the ruleset while disabling response and requiring enrollment auth."""
        import xml.etree.ElementTree as ET

        original = """<ossec_config><ruleset><rule_dir>ruleset/rules</rule_dir></ruleset>
        <auth><use_password>no</use_password></auth></ossec_config>
        <ossec_config><localfile><location>/old</location></localfile></ossec_config>"""
        text = prepare.manager_configuration(original)
        tree = ET.fromstring("<root>" + text + "</root>")
        self.assertEqual(tree.findtext("ossec_config/active-response/disabled"), "yes")
        self.assertEqual(tree.findtext("ossec_config/auth/use_password"), "yes")
        self.assertEqual(
            tree.findtext("ossec_config/localfile/location"), "/var/log/suricata/eve.json"
        )
        self.assertEqual(tree.findtext("ossec_config/ruleset/rule_dir"), "ruleset/rules")

    def test_capture_setup_refuses_the_default_route_interface(self):
        """An incorrect capture declaration must not flush a management interface."""
        with mock.patch("prepare.run", return_value='[{"dev":"ens18"}]') as run:
            with self.assertRaises(ValueError):
                prepare.isolate_capture_interfaces(["ens18"])
            self.assertTrue(all("flush" not in call.args[0] for call in run.call_args_list))

    def test_manager_replays_events_written_during_downtime(self):
        """Persisted log positions must permit replay after a collector restart."""
        original = "<ossec_config><auth><use_password>no</use_password></auth></ossec_config>"
        self.assertIn(
            "<only-future-events>no</only-future-events>", prepare.manager_configuration(original)
        )

    def test_evebox_bootstrap_keeps_plaintext_out_of_process_arguments(self):
        """The initialization helper receives only a hash through stdin."""
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            password = "test-bootstrap-password"
            (root / "credentials.json").write_text(json.dumps({"EVEBOX_PASSWORD": password}))
            with mock.patch("prepare.run", return_value="") as run:
                prepare.enroll_evebox({"sensors": [], "projectName": "test-bootstrap"}, root)
            for call in run.call_args_list:
                self.assertNotIn(password, json.dumps(call.args))
                self.assertNotIn(password, str(call.kwargs))

    def test_bootstrap_preserves_credentials_and_accepts_readonly_sources(self):
        """A repeated Nix activation keeps identities and produces usable private files."""
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            upstream = root / "upstream"
            upstream.mkdir()
            services = {
                name: {"environment": [], "volumes": []}
                for name in [
                    "wazuh.manager",
                    "wazuh.indexer",
                    "wazuh.dashboard",
                ]
            }
            (upstream / "docker-compose.yml").write_text(yaml.safe_dump({"services": services}))
            fixtures = {
                "wazuh_cluster/wazuh_manager.conf": (
                    "<ossec_config><auth><use_password>no</use_password></auth></ossec_config>"
                ),
                "wazuh_indexer/wazuh.indexer.yml": "{}",
                "wazuh_dashboard/wazuh.yml": "hosts: [{1: {password: sample}}]",
                "wazuh_dashboard/opensearch_dashboards.yml": "{}",
            }
            for relative, value in fixtures.items():
                path = upstream / "config" / relative
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(value)
                path.chmod(0o444)
            settings = {
                "role": "central",
                "hostname": "vincent",
                "interfaces": ["ens18"],
                "listenAddress": "127.0.0.1",
                "serverAddress": "127.0.0.1",
                "gotifyUrl": "http://gotify",
                "gotifyTokenFile": "/secret",
                "retentionDays": 3,
            }
            runtime = root / "runtime"
            with mock.patch("prepare.password_hash", return_value="test-bcrypt-hash"):
                prepare.initialize(settings, upstream, runtime)
                names = ["credentials.json", "config/wazuh_indexer_ssl_certs/root-ca.key"]
                before = [hashlib.sha256((runtime / name).read_bytes()).digest() for name in names]
                prepare.initialize(settings, upstream, runtime)
                after = [hashlib.sha256((runtime / name).read_bytes()).digest() for name in names]
            self.assertEqual(before, after)
            self.assertEqual(runtime.stat().st_mode & 0o777, 0o700)
            self.assertEqual((runtime / ".env").stat().st_mode & 0o777, 0o600)
            self.assertEqual((runtime / "gotify_bridge.py").stat().st_mode & 0o777, 0o644)


if __name__ == "__main__":
    unittest.main()
