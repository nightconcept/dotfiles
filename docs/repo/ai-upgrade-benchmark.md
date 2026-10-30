# Terra AI upgrade benchmark

Run the same harness on Terra before and after the upgrade. Use a quiet inference
window. Pause interactive Hermes use so other requests do not distort timings.
The script checks Foreman status and refuses GPU lease windows or dirty installed
Strata and Hermes sources. Three known generated Strata download-list and backup
files are allowed; all other untracked files fail the check. It does not stop
services or change configuration.

Before deployment:

```bash
cd /home/danny/git/dotfiles
uv run python scripts/bench-ai-stack.py --label before --samples 3
```

Deploy through the existing full host command, then repeat:

```bash
just terra
uv run python scripts/bench-ai-stack.py --label after --samples 3
```

If the upgrade has already happened, label its first run `after`; no valid before
measurement exists. Do not infer a speed improvement from two upgraded runs.

Artifacts go under `~/.local/state/ai-bench/<timestamp>-<label>/`. New directories
are private. `metadata.json` records installed full source commits, catalog model
settings, inference arguments, and the harness revision. It does not read Hermes
personal configuration, credentials, chat history, or memory. `results.jsonl`
contains synthetic prompts' responses and individual request measurements.

The harness uses `http://127.0.0.1:8080/v1` and the catalog default model. It sends
one warmup, then three repetitions of these cases:

- Short exact-output instruction.
- A longer generated explanation to measure sustained decode.
- Retrieval of an exact marker from 512 synthetic context records.
- A forced fixture tool call, followed by a tool-result completion.

The fixture tool returns a constant string. The harness validates its name and
arguments. It never executes model-generated commands. Exact-output checks test
instruction following. The explanation checks only that text exists; it does not
score answer quality. Tool completion must return the fixture value exactly.

Compare medians for each case across the three samples. Exclude warmup. Compare
output checks first, then first-delta latency (`ttft_s`), total latency, usage,
and server decode tokens per second. The first delta can contain reasoning or a
tool-call fragment. It is an HTTP observation, not the engine's first-token clock.
Missing usage or timing stays absent. Decode speed comes only from the server's
`predicted_per_second`; the script does not estimate tokens from text length.
Total latency includes loading, queueing, and prompt processing. Prefix caching,
model settings, tokenization changes, and concurrent requests affect comparisons.
Keep catalog settings and request counts the same across runs. Long-context
repetitions may benefit from prefix reuse; retain individual samples.

This HTTP benchmark exercises Strata through llama-swap. Recording the Hermes
revision does not measure Hermes behavior. After upgrading Hermes, separately
check gateway health and use a fresh synthetic Hermes session to confirm local
provider selection, a permitted read-only tool, context compaction, and session
resume. Do not use production conversations as benchmark fixtures. Hermes agent
improvements require an agent-level evaluation with the same tasks and tool
permissions before and after.
