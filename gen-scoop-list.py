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

# Find the start of the data (after the header and separator)
data_start_index = -1
# Compile the regex for ANSI escape codes for efficiency
# This pattern matches most common ANSI sequences
ansi_escape_pattern = re.compile(r'\x1b(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~])')

for i, line in enumerate(lines):
    line_no_ansi = ansi_escape_pattern.sub('', line)
    line_stripped = line_no_ansi.strip() 
    if line_stripped.startswith('----'):
        # print(f"FOUND separator at line {i}")
        data_start_index = i + 1
        break

if data_start_index == -1:
    print("Error: Could not find the data header separator line (starting with '----') after removing ANSI codes.", file=sys.stderr)
    print("--- Received Output (first 1000 chars) ---", file=sys.stderr)
    print(scoop_list_output[:1000] + ("..." if len(scoop_list_output) > 1000 else ""), file=sys.stderr)
    print("------------------------------------------", file=sys.stderr)
    sys.exit(1)

print("--- Parsing application list ---")
# --- Parse Data Lines ---
for i, line in enumerate(lines[data_start_index:], start=data_start_index):
    line_no_ansi = ansi_escape_pattern.sub('', line)
    line_stripped = line_no_ansi.strip()
    
    if not line_stripped: 
        continue

    # Split by 2 or more whitespace characters - this is the primary column delimiter
    parts = re.split(r'\s{2,}', line_stripped)

    name = None
    source = None
    is_url_source = False

    # --- Try to extract Name, Version, Source ---
    if len(parts) >= 2: # Need at least a potential Name and potential Source/Date
        potential_name_version = parts[0].strip()
        
        # --- NAME CORRECTION: Check if version got stuck to the name ---
        # If the first part contains an internal space, try splitting off the last word
        if ' ' in potential_name_version:
            name_parts = potential_name_version.rsplit(' ', 1)
            # Check if the second part looks like a version (contains digit or 'nightly')
            # and the first part isn't empty
            if len(name_parts) == 2 and name_parts[0] and \
               (any(c.isdigit() for c in name_parts[1]) or 'nightly' in name_parts[1].lower()):
                
                name = name_parts[0].strip() # Real name is before the last space
                # Version is name_parts[1] - we don't strictly need it
                
                # Source should now be in parts[1] (index 1 because version was part of index 0)
                if len(parts) >= 2:
                    source = parts[1].strip()
                # else: source remains None
            else:
                 # Contains space, but doesn't look like version appended. Treat as full name.
                 name = potential_name_version
                 # Source might be in parts[1] or parts[2] depending on if Version column exists
                 if len(parts) >= 3:
                      source = parts[2].strip()
                 elif len(parts) == 2:
                      source = parts[1].strip() # Assume Name, Source (no version)
        else:
            # No space in first part, it's the name
            name = potential_name_version
            # Source might be in parts[1] or parts[2]
            if len(parts) >= 3:
                source = parts[2].strip() # Assume Name, Version, Source
            elif len(parts) >= 2:
                source = parts[1].strip() # Assume Name, Source

        # --- Validate Source ---
        # If source looks like a date, it's wrong. Source must come before date.
        if source and re.match(r'^\d{4}-\d{2}-\d{2}', source):
             print(f"Warning line {i}: Possible incorrect source parsing for '{name}'. Found date '{source}' instead of source. Skipping.")
             name = None
             source = None
        # If source looks like a URL
        elif source and (source.startswith('http') or source.endswith('.json')):
             is_url_source = True
             # Keep source as the URL for adding buckets if needed later (though usually not)
             # But for install command, we might just use the name
             
    # --- Store Valid Data ---
    if name and source:
        # print(f"Parsed: Name='{name}', Source='{source}', IsURL={is_url_source}")
        app_data.append({'name': name, 'source': source, 'is_url': is_url_source})

        # Add bucket if it's not main and not a URL
        if source != 'main' and not is_url_source:
             # Basic sanity check for bucket names
             if ':' not in source and '/' not in source and ' ' not in source: 
                buckets.add(source)
                
    elif line_stripped: # Log if we stripped a line but failed to parse name/source
         print(f"Warning line {i}: Failed to parse name/source from: '{line_stripped}' - Parts: {parts}")

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
    if app.get('is_url', False) and not app['name'] in EXCLUDED_LIST:
         # For direct URL manifests, standard is just 'scoop install <name>'
         # Scoop remembers the URL or finds the manifest if it was cached/added.
         # Installing directly via URL isn't idempotent for *reinstalling*.
         # print(f"Install command for URL source '{app['name']}' (using name only)")
         output_lines.append(f"scoop install {app['name']}")
    else:
         # Per user request: Prepend source bucket even for 'main'
         safe_source = app['source'].split(' ')[0] # Basic sanitize just in case
         #print(f"Install command for bucket source '{safe_source}/{app['name']}'")
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
