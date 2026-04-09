import json
import os
import subprocess
import sys
from datetime import datetime
from pathlib import Path

# Apps listed here must be managed in install-windows.ps1 as they will not be automatically added.
EXCLUDED_LIST = [
    "k-lite-codec-pack-full-np",
    "freefilesync",
]


def get_scoop_export():
    scoop_cmd = "scoop"
    userprofile = os.environ.get("USERPROFILE")
    if userprofile:
        shim = Path(userprofile) / "scoop" / "shims" / "scoop.cmd"
        if shim.exists():
            scoop_cmd = str(shim)

    try:
        print("Run 'scoop export'...")
        result = subprocess.run(
            [scoop_cmd, "export"],
            capture_output=True,
            check=True,
            text=True,
            encoding="utf-8",
        )
    except FileNotFoundError:
        print("Error: 'scoop' command not found.", file=sys.stderr)
        sys.exit(1)
    except subprocess.CalledProcessError as e:
        print(f"Error: 'scoop export' failed with return code {e.returncode}.", file=sys.stderr)
        print(f"Stderr: {e.stderr}", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(f"An unexpected error occurred during 'scoop export': {e}", file=sys.stderr)
        sys.exit(1)

    try:
        export = json.loads(result.stdout)
    except json.JSONDecodeError as e:
        print(f"Error: failed to parse 'scoop export' output as JSON: {e}", file=sys.stderr)
        sys.exit(1)

    print("Successfully obtained and parsed 'scoop export' output.")
    return export


export_data = get_scoop_export()

app_data = []
buckets = set()

print("--- Parsing application list ---")
for app in export_data.get("apps", []):
    name = app.get("Name")
    source = app.get("Source")
    if not name or name in EXCLUDED_LIST:
        continue
    if not source:
        continue

    app_data.append({"name": name, "source": source})

    if source != "main":
        buckets.add(source)

print("--- Finished parsing ---")

output_lines = []
output_lines.append("# PowerShell script generated from 'scoop export' output")
now = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
output_lines.append(f"# Generated on: {now}")
output_lines.append("")

if buckets:
    output_lines.append("# Add required buckets (if not already added)")
    for bucket in sorted(buckets):
        output_lines.append(f"scoop bucket add {bucket}")
    output_lines.append("")
else:
    output_lines.append("# No custom buckets found to add (only 'main' is used)")
    output_lines.append("")

output_lines.append("# Install applications")

app_data.sort(key=lambda x: x["name"].lower())

for app in app_data:
    output_lines.append(f"scoop install {app['source']}/{app['name']}")

output_filename = Path(__file__).with_name("scoop-install-script.ps1")
try:
    with open(output_filename, "w", encoding="utf-8") as f:
        for line in output_lines:
            f.write(line + "\n")
    print(f"\nSuccessfully generated {output_filename}")
except IOError as e:
    print(f"\nError writing to file {output_filename}: {e}", file=sys.stderr)
    sys.exit(1)
