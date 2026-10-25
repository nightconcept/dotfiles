"""Prepare the role-specific Compose project without putting secrets in the Nix store."""

import json
import os
import re
import secrets
import shutil
import ssl
import subprocess
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

import bcrypt
import yaml

HERE = Path(__file__).parent
EVEBOX_IMAGE = "jasonish/evebox:0.31.0"


def compose(settings, upstream):
    """Build one Compose project for a central server or a remote sensor."""
    if settings["role"] not in {"central", "sensor"}:
        raise ValueError("Unknown security-stack role")
    interfaces = settings["interfaces"]
    if not interfaces or any(not re.fullmatch(r"[A-Za-z0-9_.:-]+", i) for i in interfaces):
        raise ValueError("Capture interfaces must be nonempty Linux interface names")
    stack = yaml.safe_load((HERE / "compose.base.yml").read_text())
    services = stack["services"]
    services["evebox-gotify"]["environment"]["SENSOR_NAME"] = settings["hostname"]
    flags = " ".join(f"-i {interface}" for interface in interfaces)
    services["suricata"]["command"] = [
        "/docker-entrypoint.sh -V\nsuricata-update --no-test --no-reload\n"
        f"exec /docker-entrypoint.sh {flags} --set unix-command.enabled=yes "
        f"--set sensor-name={settings['hostname']}\n"
    ]
    if settings["role"] == "central":
        wazuh = yaml.safe_load((upstream / "docker-compose.yml").read_text())
        for name, service in wazuh["services"].items():
            service.pop("ports", None)
            service.pop("links", None)
            environment = service.get("environment", [])
            service["environment"] = dict(
                item.replace('"', "").split("=", 1) for item in environment
            )
            for key in ["INDEXER_PASSWORD", "API_PASSWORD", "DASHBOARD_PASSWORD"]:
                if key in service["environment"]:
                    service["environment"][key] = "${" + key + "}"
            service["logging"] = {"driver": "local", "options": {"max-size": "10m"}}
        services.update(wazuh["services"])
        stack["volumes"].update(wazuh.get("volumes", {}))
        manager = services["wazuh.manager"]
        manager["ports"] = [f"{settings['listenAddress']}:{p}:{p}" for p in [1514, 1515]]
        manager["volumes"] += [
            "suricata-logs:/var/log/suricata:ro",
            "./enrollment/wazuh.password:/var/ossec/etc/authd.pass:ro",
        ]
        manager["healthcheck"] = {
            "test": [
                "CMD-SHELL",
                "/var/ossec/bin/wazuh-control status | grep -q 'wazuh-analysisd is running'",
            ],
            "interval": "30s",
            "timeout": "10s",
            "retries": 10,
            "start_period": "120s",
        }
        services["wazuh.dashboard"]["ports"] = [f"{settings['listenAddress']}:5601:5601"]
        services["wazuh.dashboard"]["healthcheck"] = {
            "test": [
                "CMD-SHELL",
                'printf \'user = "admin:%s"\\n\' "$$INDEXER_PASSWORD" | '
                "curl -sf --config - --cacert /usr/share/wazuh-dashboard/certs/root-ca.pem "
                "https://wazuh.dashboard:5601/api/status"
                " >/dev/null",
            ],
            "interval": "30s",
            "timeout": "10s",
            "retries": 10,
            "start_period": "120s",
        }
        services["wazuh.indexer"]["environment"]["INDEXER_PASSWORD"] = "${INDEXER_PASSWORD}"
        services["wazuh.indexer"]["healthcheck"] = {
            "test": [
                "CMD-SHELL",
                'printf \'user = "admin:%s"\\n\' "$$INDEXER_PASSWORD" | '
                "curl -sf --config - --cacert config/certs/root-ca.pem "
                "https://wazuh.indexer:9200/_cluster/health"
                " >/dev/null",
            ],
            "interval": "30s",
            "timeout": "10s",
            "retries": 10,
            "start_period": "120s",
        }
        services["evebox"] = {
            "image": EVEBOX_IMAGE,
            "restart": "unless-stopped",
            "command": [
                "evebox",
                "server",
                "--config",
                "/etc/evebox.yaml",
                "--no-tls",
                "--host",
                "0.0.0.0",
                "-D",
                "/var/lib/evebox",
            ],
            "ports": [f"{settings['listenAddress']}:5636:5636"],
            "volumes": [
                "./evebox.yaml:/etc/evebox.yaml:ro",
                "evebox-data:/var/lib/evebox",
                "suricata-logs:/var/log/suricata:ro",
            ],
            "healthcheck": {
                "test": ["CMD", "curl", "-sf", "http://localhost:5636/"],
                "interval": "30s",
                "retries": 5,
            },
        }
        stack["volumes"]["evebox-data"] = None
    else:
        services["evebox-agent"] = {
            "image": EVEBOX_IMAGE,
            "restart": "unless-stopped",
            "command": [
                "evebox",
                "agent",
                "--server",
                settings["eveboxUrl"],
                "-D",
                "/var/lib/evebox",
                "/var/log/suricata/eve.json",
            ],
            "environment": {"EVEBOX_SERVER_KEY": "${EVEBOX_SERVER_KEY}"},
            "volumes": ["suricata-logs:/var/log/suricata:ro", "evebox-agent:/var/lib/evebox"],
            "healthcheck": {
                "test": [
                    "CMD-SHELL",
                    "find /var/lib/evebox -name '*.bookmark' -mmin -3 | grep -q .",
                ],
                "interval": "30s",
                "timeout": "5s",
                "retries": 5,
                "start_period": "120s",
            },
        }
        services["wazuh-agent"] = {
            "image": "wazuh/wazuh-agent:4.14.5",
            "restart": "unless-stopped",
            "environment": {
                "WAZUH_MANAGER_SERVER": settings["serverAddress"],
                "WAZUH_AGENT_NAME": settings["hostname"],
                "WAZUH_REGISTRATION_PASSWORD": "${WAZUH_REGISTRATION_PASSWORD}",
            },
            "volumes": [
                "./agent.conf:/wazuh-config-mount/etc/ossec.conf:ro",
                "suricata-logs:/var/log/suricata:ro",
                "wazuh-agent:/var/ossec/etc",
                "wazuh-agent-queue:/var/ossec/queue",
                "./enrollment/root-ca.pem:/run/secrets/root-ca.pem:ro",
            ],
            "healthcheck": {
                "test": [
                    "CMD-SHELL",
                    'grep -q "status=\x27connected\x27" /var/ossec/var/run/wazuh-agentd.state',
                ],
                "interval": "15s",
                "timeout": "5s",
                "retries": 12,
                "start_period": "120s",
            },
        }
        stack["volumes"].update(
            {
                name: None
                for name in [
                    "evebox-agent",
                    "wazuh-agent",
                    "wazuh-agent-queue",
                ]
            }
        )
    project = settings.get("projectName", "security-stack")
    stack["name"] = project
    for name, service in services.items():
        service["container_name"] = project + "-" + name.replace(".", "-")
        service.setdefault("logging", {"driver": "local", "options": {"max-size": "10m"}})
    return stack


def manager_configuration(original):
    """Retain upstream rules and indexing while collecting only local EVE input."""
    tree = ET.fromstring("<root>" + original + "</root>")
    manager = tree.find("ossec_config")
    if manager is None:
        raise ValueError("Wazuh configuration has no manager section")
    for section in tree:
        for tag in [
            "localfile",
            "active-response",
            "command",
            "rootcheck",
            "syscheck",
            "sca",
            "wodle",
            "vulnerability-detection",
        ]:
            for child in section.findall(tag):
                section.remove(child)
    ET.SubElement(ET.SubElement(manager, "active-response"), "disabled").text = "yes"
    local = ET.SubElement(manager, "localfile")
    ET.SubElement(local, "log_format").text = "json"
    ET.SubElement(local, "only-future-events").text = "no"
    ET.SubElement(local, "location").text = "/var/log/suricata/eve.json"
    auth = manager.find("auth")
    if auth is None:
        raise ValueError("Wazuh configuration has no enrollment section")
    password = auth.find("use_password")
    if password is None:
        raise ValueError("Wazuh enrollment configuration changed upstream")
    password.text = "yes"
    for name, value in {
        "ssl_manager_cert": "/etc/ssl/filebeat.pem",
        "ssl_manager_key": "/etc/ssl/filebeat.key",
    }.items():
        element = auth.find(name)
        if element is None:
            element = ET.SubElement(auth, name)
        element.text = value
    return "\n".join(ET.tostring(child, encoding="unicode") for child in tree)


def run(args, **kwargs):
    """Capture tool output so credentials never reach service logs on failures."""
    result = subprocess.run(args, capture_output=True, text=True, **kwargs)
    if result.returncode:
        raise RuntimeError(f"Security-stack setup failed in {Path(args[0]).name}; output withheld")
    return result.stdout


def write(path, value):
    """Write configuration inside the private runtime directory, readable by containers."""
    path.parent.mkdir(parents=True, exist_ok=True)
    path.parent.chmod(0o700)
    if path.exists():
        path.chmod(0o644)
    path.write_text(value)
    path.chmod(0o644)


def certificates(directory, server_address):
    """Create the stack CA and required PKCS8 certificates once."""
    names = ["admin", "wazuh.indexer", "wazuh.manager", "wazuh.dashboard"]
    if directory.exists():
        required = ["root-ca.pem", "root-ca-manager.pem", "root-ca.key"]
        required += [name + suffix for name in names for suffix in [".pem", "-key.pem"]]
        if not all((directory / name).is_file() for name in required):
            raise RuntimeError(
                "Incomplete certificates; restore the certificate backup before starting"
            )
        return
    temporary = directory.with_name(directory.name + ".new")
    temporary.mkdir(mode=0o700)
    run(
        [
            "openssl",
            "req",
            "-x509",
            "-newkey",
            "rsa:3072",
            "-nodes",
            "-days",
            "3650",
            "-subj",
            "/C=US/L=California/O=Wazuh/OU=Wazuh/CN=Security Stack CA",
            "-keyout",
            str(temporary / "root-ca.key"),
            "-out",
            str(temporary / "root-ca.pem"),
        ]
    )
    shutil.copyfile(temporary / "root-ca.pem", temporary / "root-ca-manager.pem")
    for name in names:
        key, csr, cert = [temporary / (name + suffix) for suffix in ["-key.pem", ".csr", ".pem"]]
        run(
            [
                "openssl",
                "req",
                "-new",
                "-newkey",
                "rsa:2048",
                "-nodes",
                "-subj",
                f"/C=US/L=California/O=Wazuh/OU=Wazuh/CN={name}",
                "-keyout",
                str(key),
                "-out",
                str(csr),
            ]
        )
        extensions = temporary / "extensions.cnf"
        extensions.write_text(
            f"subjectAltName=DNS:{name},IP:{server_address}\n"
            "basicConstraints=CA:FALSE\nkeyUsage=digitalSignature,keyEncipherment\n"
            "extendedKeyUsage=serverAuth,clientAuth\n"
        )
        run(
            [
                "openssl",
                "x509",
                "-req",
                "-in",
                str(csr),
                "-CA",
                str(temporary / "root-ca.pem"),
                "-CAkey",
                str(temporary / "root-ca.key"),
                "-CAcreateserial",
                "-days",
                "825",
                "-extfile",
                str(extensions),
                "-out",
                str(cert),
            ]
        )
        csr.unlink()
    for path in temporary.iterdir():
        path.chmod(0o644 if path.suffix == ".pem" else 0o600)
    temporary.rename(directory)


def password_hash(password):
    """Hash in process so plaintext credentials never enter command arguments."""
    return bcrypt.hashpw(password.encode(), bcrypt.gensalt()).decode()


def isolate_capture_interfaces(interfaces):
    """Prepare explicitly declared mirror NICs without touching any default-route NIC."""
    if not interfaces:
        return
    routes = json.loads(run(["ip", "-j", "route", "show", "default"]))
    routes += json.loads(run(["ip", "-6", "-j", "route", "show", "default"]))
    if any(route.get("dev") in interfaces for route in routes):
        raise ValueError("Refusing to isolate a default-route interface")
    for interface in interfaces:
        run(["ip", "link", "set", "dev", interface, "addrgenmode", "none"])
        run(["sysctl", "-q", "-w", f"net.ipv6.conf.{interface}.disable_ipv6=1"])
        run(["sysctl", "-q", "-w", f"net.ipv4.conf.{interface}.forwarding=0"])
        run(["ip", "address", "flush", "dev", interface])
        run(["ip", "link", "set", "dev", interface, "up"])


def initialize(settings, upstream, root):
    """Prepare runtime files; enrollment files are copied once from the central host."""
    os.umask(0o077)
    root.mkdir(mode=0o700, parents=True, exist_ok=True)
    root.chmod(0o700)
    enrollment = root / "enrollment"
    enrollment.mkdir(exist_ok=True)
    environment = {
        "GOTIFY_URL": settings["gotifyUrl"],
        "GOTIFY_TOKEN_FILE": settings["gotifyTokenFile"],
    }
    stack = compose(settings, upstream)
    for name in ["gotify_bridge.py", "evebox.yaml", "suricata-logrotate"]:
        shutil.copyfile(HERE / name, root / name)
        (root / name).chmod(0o644)
    if settings["role"] == "central":
        credentials_file = root / "credentials.json"
        if credentials_file.exists():
            credentials = json.loads(credentials_file.read_text())
        else:
            credentials = {
                key: secrets.token_hex(24) + "Aa1!"
                for key in [
                    "INDEXER_PASSWORD",
                    "API_PASSWORD",
                    "DASHBOARD_PASSWORD",
                    "EVEBOX_PASSWORD",
                    "WAZUH_REGISTRATION_PASSWORD",
                ]
            }
            credentials_file.write_text(json.dumps(credentials))
        environment.update(credentials)
        config = root / "config"
        config.mkdir(exist_ok=True)
        config.chmod(0o700)
        for relative in [
            "wazuh_cluster/wazuh_manager.conf",
            "wazuh_indexer/wazuh.indexer.yml",
            "wazuh_dashboard/wazuh.yml",
            "wazuh_dashboard/opensearch_dashboards.yml",
        ]:
            write(config / relative, (upstream / "config" / relative).read_text())
        cert_dir = config / "wazuh_indexer_ssl_certs"
        certificates(cert_dir, settings["serverAddress"])
        users_path = config / "wazuh_indexer/internal_users.yml"
        if not users_path.exists():
            users = {
                "_meta": {"type": "internalusers", "config_version": 2},
                "admin": {
                    "hash": password_hash(credentials["INDEXER_PASSWORD"]),
                    "reserved": True,
                    "backend_roles": ["admin"],
                },
                "kibanaserver": {
                    "hash": password_hash(credentials["DASHBOARD_PASSWORD"]),
                    "reserved": True,
                },
            }
            write(users_path, yaml.safe_dump(users))
        manager = config / "wazuh_cluster/wazuh_manager.conf"
        write(manager, manager_configuration(manager.read_text()))
        dashboard = config / "wazuh_dashboard/wazuh.yml"
        data = yaml.safe_load(dashboard.read_text())
        for entry in data["hosts"]:
            for host in entry.values():
                host["password"] = credentials["API_PASSWORD"]
        write(dashboard, yaml.safe_dump(data))
        # Upstream disables disk watermarks; keep shared-host disk protection enabled.
        indexer = config / "wazuh_indexer/wazuh.indexer.yml"
        data = yaml.safe_load(indexer.read_text())
        data["cluster.routing.allocation.disk.threshold_enabled"] = True
        write(indexer, yaml.safe_dump(data))
        write(enrollment / "wazuh.password", credentials["WAZUH_REGISTRATION_PASSWORD"] + "\n")
        shutil.copyfile(cert_dir / "root-ca.pem", enrollment / "root-ca.pem")
        evebox = yaml.safe_load((root / "evebox.yaml").read_text())
        evebox["database"]["retention"]["days"] = settings["retentionDays"]
        write(root / "evebox.yaml", yaml.safe_dump(evebox))
    else:
        for name in ["evebox.key", "wazuh.password", "root-ca.pem"]:
            if not (enrollment / name).is_file():
                raise RuntimeError(
                    f"Copy {name} from the central enrollment directory before enabling this sensor"
                )
        # The enrollment daemon drops privileges; its CA is public, unlike the agent keys.
        (enrollment / "root-ca.pem").chmod(0o644)
        ssl.PEM_cert_to_DER_cert((enrollment / "root-ca.pem").read_text())
        if any(
            not (enrollment / name).read_text().strip() for name in ["evebox.key", "wazuh.password"]
        ):
            raise ValueError("Sensor enrollment key and password files must not be empty")
        environment["EVEBOX_SERVER_KEY"] = (enrollment / "evebox.key").read_text().strip()
        environment["WAZUH_REGISTRATION_PASSWORD"] = (
            (enrollment / "wazuh.password").read_text().strip()
        )
        agent = ET.Element("ossec_config")
        client = ET.SubElement(agent, "client")
        server = ET.SubElement(client, "server")
        ET.SubElement(server, "address").text = "CHANGE_MANAGER_IP"
        ET.SubElement(server, "port").text = "CHANGE_MANAGER_PORT"
        ET.SubElement(server, "protocol").text = "tcp"
        enroll = ET.SubElement(client, "enrollment")
        for key, value in {
            "enabled": "yes",
            "manager_address": "CHANGE_ENROLL_IP",
            "port": "CHANGE_ENROLL_PORT",
            "agent_name": "CHANGE_AGENT_NAME",
            "authorization_pass_path": "etc/authd.pass",
            "server_ca_path": "/run/secrets/root-ca.pem",
        }.items():
            ET.SubElement(enroll, key).text = value
        ET.SubElement(ET.SubElement(agent, "active-response"), "disabled").text = "yes"
        local = ET.SubElement(agent, "localfile")
        ET.SubElement(local, "log_format").text = "json"
        ET.SubElement(local, "only-future-events").text = "no"
        ET.SubElement(local, "location").text = "/var/log/suricata/eve.json"
        write(root / "agent.conf", ET.tostring(agent, encoding="unicode"))
    # JSON quoting protects dotenv parsing; Compose requires doubled dollar signs.
    (root / ".env").write_text(
        "".join(
            key + "=" + json.dumps(value.replace("$", "$$")) + "\n"
            for key, value in environment.items()
        )
    )
    (root / ".env").chmod(0o600)
    write(root / "docker-compose.yml", yaml.safe_dump(stack, sort_keys=False))


def enroll_evebox(settings, root):
    """Initialize EveBox users and export named sensor credentials without logging them."""
    credentials = json.loads((root / "credentials.json").read_text())
    command = [
        "docker",
        "compose",
        "--project-directory",
        str(root),
        "run",
        "--rm",
        "--no-deps",
        "evebox",
        "evebox",
        "-D",
        "/var/lib/evebox",
        "config",
    ]
    users = run(command + ["users", "list"])
    if not re.search(r"\badmin\b", users):
        # The pinned EveBox CLI only accepts plaintext passwords in argv or a TTY.
        # shortcut: SQLite schema follows EveBox 0.31.0; review it before upgrading.
        seed = (
            "import json,sqlite3,sys,uuid; value=json.load(sys.stdin); "
            "db=sqlite3.connect('/data/config.sqlite'); "
            "db.execute('INSERT INTO users (uuid,username,password) VALUES (?,?,?)', "
            "(str(uuid.uuid4()),'admin',value['hash'])); db.commit()"
        )
        project = settings.get("projectName", "security-stack")
        run(
            [
                "docker",
                "run",
                "--rm",
                "--network",
                "none",
                "-i",
                "-v",
                f"{project}_evebox-data:/data",
                "python:3.13-alpine",
                "python",
                "-c",
                seed,
            ],
            input=json.dumps({"hash": password_hash(credentials["EVEBOX_PASSWORD"])}),
        )
    for sensor in settings["sensors"]:
        if not re.fullmatch(r"[A-Za-z0-9_-]+", sensor):
            raise ValueError("Invalid sensor identity")
        destination = root / "enrollment" / sensor
        destination.mkdir(mode=0o700, exist_ok=True)
        keyfile = destination / "evebox.key"
        if not keyfile.exists():
            output = run(command + ["agents", "add", sensor])
            match = re.search(r"eba_[A-Za-z0-9_-]+", output)
            if not match:
                raise RuntimeError(
                    "EveBox enrollment returned no key; restore the enrollment backup"
                )
            keyfile.write_text(match[0] + "\n")
            keyfile.chmod(0o600)
        for name in ["root-ca.pem", "wazuh.password"]:
            shutil.copyfile(root / "enrollment" / name, destination / name)
            (destination / name).chmod(0o600)


def main():
    """Prepare the project using a non-secret Nix-generated settings file."""
    settings = json.loads(Path(sys.argv[1]).read_text())
    isolate_capture_interfaces(settings.get("captureInterfaces", []))
    initialize(settings, Path(sys.argv[2]), Path(sys.argv[3]))
    if settings["role"] == "central":
        enroll_evebox(settings, Path(sys.argv[3]))


if __name__ == "__main__":
    main()
