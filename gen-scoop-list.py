import re
import subprocess
import sys
import locale
from datetime import datetime

# Apps listed here must be managed in install-windows.ps1 as they will not be automatically added.
EXCLUDED_LIST = [
    "k-lite-codec-pack-full-np",
    "freefilesync"
]

# --- Function to run 'scoop list', capture bytes, and decode carefully ---
def get_scoop_list_output():
    """Runs 'scoop list', captures output, and decodes it, handling potential encoding issues."""
    scoop_output_str = None
    result_stdout_bytes = None
    
    # Determine which command to run
    command_args = ['scoop', 'list']

    try:
        print("Run 'scoop list'...")
        # Capture as bytes
        result = subprocess.run(command_args, capture_output=True, check=True, shell=True)
        result_stdout_bytes = result.stdout

    except FileNotFoundError:
        print("Error: 'scoop' command not found even with shell=True.", file=sys.stderr)
        sys.exit(1)
    except subprocess.CalledProcessError as e:
        print(f"Error: 'scoop list' (with shell=True) failed with return code {e.returncode}.", file=sys.stderr)
        try:
            stderr_decoded = e.stderr.decode(locale.getpreferredencoding(False), errors='replace')
        except:
            stderr_decoded = str(e.stderr)
        print(f"Stderr: {stderr_decoded}", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
            print(f"An unexpected error occurred during shell 'scoop list' run: {e}", file=sys.stderr)
            sys.exit(1)

    # --- If we have bytes, try to decode them ---
    if result_stdout_bytes is not None:
        print("Decoding 'scoop list' output...")
        decoded = False
        encodings_to_try = [
            'utf-8', 
            locale.getpreferredencoding(False),
            'cp1252',
            'cp437',
            'latin-1'
        ]
        unique_encodings = []
        for enc in encodings_to_try:
             if enc and enc.lower() not in [ue.lower() for ue in unique_encodings]:
                 unique_encodings.append(enc)

        for encoding in unique_encodings:
            try:
                # print(f"Attempting decode with: {encoding}")
                scoop_output_str = result_stdout_bytes.decode(encoding)
                # print(f"Successfully decoded using {encoding}.")
                decoded = True
                break 
            except UnicodeDecodeError:
                # print(f"Decoding with {encoding} failed.")
                continue 
            except Exception as e:
                # print(f"Unexpected error decoding with {encoding}: {e}")
                continue

        if not decoded:
            fallback_encoding = locale.getpreferredencoding(False) or 'cp1252'
            print(f"Warning: Could not decode perfectly. Decoding using {fallback_encoding} with error replacement.")
            try:
                 scoop_output_str = result_stdout_bytes.decode(fallback_encoding, errors='replace')
                 decoded = True
            except Exception as e:
                 print(f"Critical Error: Failed even decoding with replacement: {e}", file=sys.stderr)
                 
    # --- Final Check and Return ---
    if scoop_output_str:
        print("Successfully obtained and decoded 'scoop list' output.")
        return scoop_output_str
    else:
        print("Error: Failed to obtain and decode 'scoop list' output after all attempts.", file=sys.stderr)
        sys.exit(1)

# --- Get Input Data ---
scoop_list_output = get_scoop_list_output()

# --- Script Logic (Parsing) ---
app_data = []
buckets = set()
if not scoop_list_output:
     print("Error: No output received from scoop list to process.", file=sys.stderr)
     sys.exit(1)

lines = scoop_list_output.splitlines()

# Compile the regex for ANSI escape codes for efficiency
ansi_escape_pattern = re.compile(r'\x1b(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~])')

# --- Find header and column positions ---
header_line_text = None
separator_line_index = -1

for i, line in enumerate(lines):
    line_no_ansi = ansi_escape_pattern.sub('', line)
    if line_no_ansi.strip().startswith('----'):
        separator_line_index = i
        # The header is the first non-empty line before the separator
        for j in range(i - 1, -1, -1):
            prev_line_no_ansi = ansi_escape_pattern.sub('', lines[j])
            if prev_line_no_ansi.strip():
                header_line_text = prev_line_no_ansi
                break
        break

if separator_line_index == -1 or not header_line_text:
    print("Error: Could not find the data header and separator lines (e.g., 'Name Version Source' and '---- ...').", file=sys.stderr)
    print("--- Received Output (first 1000 chars) ---", file=sys.stderr)
    print(scoop_list_output[:1000] + ("..." if len(scoop_list_output) > 1000 else ""), file=sys.stderr)
    print("------------------------------------------", file=sys.stderr)
    sys.exit(1)

version_col_start = header_line_text.find('Version')
source_col_start = header_line_text.find('Source')

if version_col_start == -1 or source_col_start == -1:
    print(f"Error: Could not find 'Version' or 'Source' columns in header line: '{header_line_text.strip()}'", file=sys.stderr)
    sys.exit(1)

data_start_index = separator_line_index + 1

print("--- Parsing application list ---")
# --- Parse Data Lines ---
for i, line in enumerate(lines[data_start_index:], start=data_start_index):
    line_no_ansi = ansi_escape_pattern.sub('', line)
    
    if not line_no_ansi.strip():
        continue

    # --- Parse based on column positions from header ---
    name = line_no_ansi[:version_col_start].strip()
    # We don't use version, but it's here for completeness
    # version = line_no_ansi[version_col_start:source_col_start].strip()
    source = line_no_ansi[source_col_start:].strip()

    if not name:
        print(f"Warning line {i}: Skipping line with no application name: '{line_no_ansi.strip()}'")
        continue

    # Handle cases where source is empty
    if not source:
        source = None

    is_url_source = False
    if source and (source.startswith('http') or source.endswith('.json')):
        is_url_source = True
        
    app_data.append({'name': name, 'source': source, 'is_url': is_url_source})

    # Add bucket if it's not main, not a URL, and not None
    if source and source != 'main' and not is_url_source:
         # Basic sanity check for bucket names
         if ':' not in source and '/' not in source and ' ' not in source:
            buckets.add(source)

print("--- Finished parsing ---")


# Generate output
output_lines = []
output_lines.append("# PowerShell script generated from 'scoop list' output")
now = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
output_lines.append(f"# Generated on: {now}")
output_lines.append("")

if buckets:
    output_lines.append("# Add required buckets (if not already added)")
    for bucket in sorted(list(buckets)):
        output_lines.append(f"scoop bucket add {bucket}")
    output_lines.append("")
else:
     output_lines.append("# No custom buckets found to add (only 'main' or direct URLs used)")
     output_lines.append("")

output_lines.append("# Install applications")

# Alphabetize applications
app_data.sort(key=lambda x: x['name'].lower())

# Format scoop install list
for app in app_data:
    if app['name'] in EXCLUDED_LIST:
        continue

    # For URL sources or apps with no source, install by name only
    if app.get('is_url', False) or app['source'] is None:
        output_lines.append(f"scoop install {app['name']}")
    else:
        # Prepend source bucket
        safe_source = app['source'].split(' ')[0] # Basic sanitize just in case
        output_lines.append(f"scoop install {safe_source}/{app['name']}")

# Write output file
output_filename = "scoop-install-script.ps1"
try:
    with open(output_filename, 'w', encoding='utf-8') as f:
        for line in output_lines:
            f.write(line + "\n")
    print(f"\nSuccessfully generated {output_filename}")
except IOError as e:
    print(f"\nError writing to file {output_filename}: {e}", file=sys.stderr)
    sys.exit(1)
