---
name: bookorbit-metadata
description: Clean up and enrich the user's BookOrbit book, audiobook, and comic metadata in tracked batches, using Audible first for audiobooks and Goodreads first for books. Use for continuing library cleanup, applying reviewed matches, or auditing metadata, embedded tags, and automatic renaming.
---

# BookOrbit metadata cleanup

This skill targets BookOrbit on Rinoa in the dotfiles repository.
The user prefers automation followed by an AI review, in batches of ten.
The baseline is a clean title, correct author, and beautiful square audiobook artwork.
Prefer artwork at least 500 × 500 pixels, ideally 1024 × 1024 or larger.
Artwork may come from another edition if it clearly represents the same title.
Recording metadata must match the original recording; missing details are preferable to incorrect details.
Use intelligence for ambiguous identities and the final audit, rather than manually copying every provider field.

## State and access

- Find the repository from this skill's resolved path.
- Keep all library inventories, progress records, artwork and generated reports in `~/.local/share/bookorbit-metadata`, outside the repository. Never commit them.
- Read `~/.local/share/bookorbit-metadata/README.md` and unfinished batch files before selecting another batch.
- Bundled scripts: `scripts/cleanup.py`, `scripts/bookorbit.mjs`, and `scripts/test_cleanup.py`.
- Python uses only its standard library. JavaScript runs in the existing BookOrbit container with its installed dependencies.
- SSH to `rinoa` and Docker access are required. An active BookOrbit administrator session is required.
- The script signs a short-lived token inside the container using that active session. Credentials and tokens never leave Rinoa.
- Use BookOrbit APIs for metadata and file changes. Database queries only select inventory and session identifiers.
- If authentication or schema changes break the script, stop mutations and inspect the installed source under `/app/src`.

## Repeatable workflow

Run commands from the repository root; substitute the next unused batch number.

```bash
python3 skills/bookorbit-metadata/scripts/cleanup.py prepare ~/.local/share/bookorbit-metadata/batch-003.json
python3 skills/bookorbit-metadata/scripts/cleanup.py apply ~/.local/share/bookorbit-metadata/batch-003.json
python3 skills/bookorbit-metadata/scripts/cleanup.py audit ~/.local/share/bookorbit-metadata/batch-003.json
```

`prepare` selects ten unreviewed audiobooks with the lowest custom scores below 90.
Run `python3 skills/bookorbit-metadata/scripts/cleanup.py score ~/.local/share/bookorbit-metadata/library-scores.json` for a fresh report across books, audiobooks, and comics. Add `--medium book`, `--medium audiobook`, or `--medium comic` to restrict it.
All media use the same 100-point score: 25 each for a populated title, populated author, and suitable cover; 15 for tracked metadata review; and up to 10 from BookOrbit’s score. Documented uncertainty subtracts 10, with a zero floor.
Audiobook covers must be at least 500 × 500 and square within 5%. Book and comic covers must be at least 500 × 700 and portrait, with width/height between 0.45 and 0.90. These are review heuristics; legitimate landscape and square editions may be intentional.
A title that is only a volume, issue, part, or chapter marker is flagged for review.
The bundled automatic prepare/matching command remains audiobook-only; use the score report to select book and comic reviews and match their own media sources.
Presence and dimensions do not prove correctness or artwork quality; the review flag does not prove every recording field. Verify claims against evidence.
Previously reviewed entries with unresolved holds remain visible in the report but do not automatically repeat in the queue.
Use `--cutoff N` to set a different exclusive cutoff. Explicit `--ids` bypasses selection.
It saves snapshots before searching, then records provider candidates and prepared patches.
Use `--ids ID ...` to select specific books. Use `--count N` to change batch size when requested.
`apply` changes only items marked `ready`; it records each result before continuing.
`audit` reads each changed entry again and checks metadata, personal ratings, field locks, runtime, chapters, and file IDs.

Apply when the current conversation authorizes applying metadata changes.
Do not infer perpetual authorization from this skill alone.
An existing instruction to automate cleanup authorizes routine batches within its stated scope; do not ask again for each entry.
When approval is missing, prepare the batch and present its proposals.

For this library, the user also authorizes automatic file writing and renaming.
Check current settings with `remote('settings')` from the Python module.
If those features are disabled and the current task authorizes enabling them, run:

```bash
python3 skills/bookorbit-metadata/scripts/cleanup.py automation
```

This enables file writing, audio tag writing, and renaming for Books and Audiobooks, and records previous settings.
Keep the user's naming patterns and file-size limits. Report unsupported or skipped file writes.
Metadata saves use synchronous BookOrbit file writing and renaming; inspect returned write results and write logs.
Do not directly move files or edit embedded tags behind BookOrbit's database.

## Matching and review

- Audiobooks: Audible first; publisher or library catalogs as fallback. Books: Goodreads first; publisher or local material as fallback. Comics and manga: publisher or official creator sources first, then established catalogs; verify series, volume or issue, writer, and artist against the actual files.
- The script requires a unique title, author, English-language, and runtime match within 120 seconds for automatic audiobook selection.
- Existing narrator evidence must agree. A narrator incorrectly listed as an author can move to narrators only when the provider supports that identity.
- The English-language selector is intentionally conservative for this library. Other languages need explicit review.
- Missing results, competing editions, course audio, supplements, adaptations, and fan compilations require review.
- Use local title pages and tags to reject catalog mismatches. Record the decision and source URLs in the batch.
- Keep measured duration and embedded chapters. Never fill an audiobook's ISBN from its print edition.
- Do not copy a print page count onto a PDF with different pagination.
- Store provider ratings as community ratings. Never replace the user's personal rating.
- Preserve existing genres and field locks. The API remains responsible for validating locked audio fields.
- Fill missing audiobook covers and replace portrait or undersized artwork with square artwork for the same title.
- Prefer publisher or Audible square artwork. A cover match does not authorize copying that edition's narrator, publisher, date, or identifiers.
- If suitable square artwork is unavailable, adapt the existing cover with the available image-generation skill; retain readable title and author.
- Review generated artwork for correct text, attractive composition, and square dimensions before uploading.
- The batch fields `replace_cover: true` and `cover_file: path/to/cover.png` support reviewed local PNG replacements.
- Back up existing art with `remote('cover', id=BOOK_ID)` before replacing it; the result contains base64 image bytes.
- Use a separate cover pass after an active metadata batch finishes; changing a cover during preparation invalidates its snapshot.
- Provider descriptions may be truncated search snippets. During the final audit, replace incomplete snippets with a short sourced summary.
- Goodreads access can be blocked. Record whether evidence came from a full page or indexed result; do not pretend an exact edition was checked.

For a reviewed exception, edit the pending item's `patch`, `source_url`, `match_reason`, and `status: ready` in its batch file.
Retain its original `before` snapshot and rejected candidates.
The Python module exposes `remote('lookup', provider='audible', id='ASIN')` for an exact provider lookup.

## Recovery and progress

Before a write, the script checks that the entry still matches its preparation snapshot.
An API failure can occur after a successful save; items become `needs_audit` instead of being blindly retried.
Run `audit` first for those items. Inspect any file-write error separately from metadata-save success.
Keep original paths in snapshots because renaming changes paths.
If a stale snapshot is rejected, save a fresh snapshot as an additional attempt; retain the earlier snapshot and applied history.

After each batch, update the progress README and show ten rows with the action taken, source, and unresolved issues.
Separate metadata applied, embedded files written, renamed entries, audited entries, and entries needing review.
A higher metadata score does not prove an edition match or a successful file write.
Do not mark a held edition field complete merely because all other fields are filled.

Check script changes with:

```bash
python3 -m unittest discover -s skills/bookorbit-metadata/scripts -p 'test_*.py'
node --check skills/bookorbit-metadata/scripts/bookorbit.mjs
```
