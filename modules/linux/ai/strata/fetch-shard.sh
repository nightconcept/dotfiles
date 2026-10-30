#!/bin/bash
# Put one Strata model shard in place: keep it, reuse a copy already on disk, or download it.
#
#   fetch-shard.sh <dest-dir> <name> <size> <sha256> <url> <search-dir>...
#
# Never deletes or overwrites model data. A shard already on the storage disk is moved (or
# hard-linked when it belongs to another Strata quant folder), never copied or downloaded again.
# Downloads go to <name>.part with aria2 and resume across failures. Each attempt resolves the
# Hugging Face URL again, because its signed CDN redirect expires during long downloads.
# On success the shard has Strata's own <name>.done mark (its sha256), so setup.sh skips it.
set -euo pipefail

dest_dir=$1 name=$2 size=$3 sha=$4 url=$5
shift 5
dest=$dest_dir/$name
attempts=${STRATA_FETCH_ATTEMPTS:-40}
log=$dest_dir/download.log

say() { echo "[$(date -Is)] $name: $*" | tee -a "$log"; }
size_of() { stat -c %s "$1"; }

verify_and_mark() {
  say "verifying sha256"
  local got
  got=$(sha256sum "$dest" | cut -d' ' -f1)
  if [ "$got" != "$sha" ]; then
    say "sha256 mismatch (got $got, want $sha); left in place for inspection"
    exit 1
  fi
  printf '%s' "$sha" > "$dest.done"
  say "ok"
}

mkdir -p "$dest_dir"

# 1. Already in place.
if [ -f "$dest" ]; then
  if [ "$(size_of "$dest")" != "$size" ]; then
    say "present but $(size_of "$dest") bytes, want $size; left in place for inspection"
    exit 1
  fi
  if [ -f "$dest.done" ] && [ "$(cat "$dest.done")" = "$sha" ]; then
    say "present and marked"
    exit 0
  fi
  verify_and_mark
  exit 0
fi

# 2. A copy elsewhere on the storage disk: same name anywhere under the search dirs, or the same
# size inside another Strata quant folder (shards shared between quants have different names).
if [ ! -f "$dest.part" ]; then
  for dir in "$@"; do
    [ -d "$dir" ] || continue
    while IFS= read -r -d '' cand; do
      [ "$cand" -ef "$dest" ] && continue
      [ "$(size_of "$cand")" = "$size" ] || continue
      if [ "$(basename "$cand")" != "$name" ] && [[ "$cand" != */Strata-data/models/* ]]; then
        continue
      fi
      say "checking $cand"
      [ "$(sha256sum "$cand" | cut -d' ' -f1)" = "$sha" ] || continue
      if [[ "$cand" == */Strata-data/models/* ]]; then
        say "hard-linking from $cand"
        ln "$cand" "$dest"
      else
        say "moving from $cand"
        mv -n "$cand" "$dest"
      fi
      printf '%s' "$sha" > "$dest.done"
      say "ok (reused, not downloaded)"
      exit 0
    done < <(find "$dir" -maxdepth 3 -type f -name '*.gguf' -print0 2>/dev/null)
  done
fi

# 3. Download (or resume) with aria2.
have=0
[ -f "$dest.part" ] && have=$(size_of "$dest.part")
need=$(( size - have ))
free=$(df --output=avail -B1 "$dest_dir" | tail -1)
if [ "$need" -gt "$free" ]; then
  say "needs $need more bytes but only $free are free; stopping"
  exit 1
fi
for i in $(seq 1 "$attempts"); do
  say "download attempt $i/$attempts"
  if aria2c --continue=true --max-connection-per-server=16 --split=16 --min-split-size=16M \
      --file-allocation=none --max-tries=5 --retry-wait=30 --summary-interval=60 \
      --console-log-level=warn --download-result=hide \
      --dir="$dest_dir" --out="$name.part" "$url" >> "$log" 2>&1; then
    break
  fi
  [ "$i" = "$attempts" ] && { say "download failed after $attempts attempts; rerun to resume"; exit 1; }
  sleep 30
done
if [ -f "$dest.part.aria2" ] || [ "$(size_of "$dest.part")" != "$size" ]; then
  say "download incomplete; rerun to resume"
  exit 1
fi
mv -n "$dest.part" "$dest"
verify_and_mark
