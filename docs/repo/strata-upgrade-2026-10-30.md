# Strata upgrade assessment, 2026-10-30

## Candidate

Upgrade Terra from `v0.2.4.2` (`dfa3f4025c9f1bc4af8cee201b20a2d223061813`)
to stable `v0.2.8`, published 2026-10-29. Its full **commit** is
`870aedd9e1ebe1c91f94da93b59af17729f6c5c0`. The annotated tag object is
`878ef09cc9092a41a37dac32fd6fe461e47fa326`; use the peeled commit for the manifest.
Verified with `git rev-parse 'v0.2.8^{commit}'` in an independent upstream checkout.
[Official release](https://github.com/Niko1221/Strata/releases/tag/v0.2.8).

## Benefits for Terra

Terra uses one R9700 (`gfx1201`) and Qwen3.8-Flash-Next IQ2_XS through
llama-swap. The 0.2.7 Radeon changes retain the large PLE lookup table in RAM
when memory permits and improve the CPU/GPU decode split. Upstream measured
12–22% faster prompts and 14–31% faster decode at 8K/32K on one R9700 with
IQ3_S. Those percentages are **not predictions for Terra's IQ2_XS**.
[Versioned release notes](https://github.com/Niko1221/Strata/blob/v0.2.8/docs/release-notes-0.2.7.md).

The PLE admission policy checks available RAM against the lookup table,
expert arena and safety reserve. It can decline residency, so check the startup
log before attributing benchmark changes to that feature.
[Admission implementation](https://github.com/Niko1221/Strata/blob/v0.2.8/include/strata/core/ple_residency.hpp).

Version 0.2.8 turns tool-call recovery on by default. Upstream reports 98.3%
correct parsing across 1,462 agent turns, versus 92.9% without recovery. This
helps Hermes when the model emits almost-correct tool syntax. It only recovers
calls to tools declared by the request. String arguments containing quoted
tool syntax also have a preservation fix.
[Server behavior and evidence](https://github.com/Niko1221/Strata/blob/v0.2.8/docs/DETAILS.md).

The same release repairs conversation-cache RAM pressure when PLE memory is
locked, accounts for expert-cache reserve, and waits for an old engine to
release memory. Upstream's single-R9700 comparison against 0.2.7.1 reports
story decode 73.7 to 79.7 tokens/s and code 106.3 to 107.8. Four-card throughput,
Arc and Mac improvements do not apply to this instance.
[Official release](https://github.com/Niko1221/Strata/releases/tag/v0.2.8).

## Compatibility and deployment

- All existing arguments remain accepted: `--yes --build --family qwen
  --model IQ2_XS --backend hip --data-dir ... --port ... --context ...
  --vision no --no-browser --no-start`. The output remains
  `strata-iq2_xs.json`. Existing `serve/server.py --engine strata --config ...
  --port ...` remains supported.
  [Setup](https://github.com/Niko1221/Strata/blob/v0.2.8/setup.py),
  [server](https://github.com/Niko1221/Strata/blob/v0.2.8/serve/server.py).
- Both IQ2_XS shard names, byte counts and SHA-256 values exactly match the
  current dotfiles catalog. No model download or quant change is needed.
  [Upstream shard manifest](https://github.com/Niko1221/Strata/blob/v0.2.8/setup.py).
- `requirements.txt` is unchanged between these pins. The CMake floor remains
  3.24, C++20 remains required, and ggml is fetched at exact llama.cpp revision
  `3cf03257f219afbe7334045ff7c6a06ac68c627d`. This is separate from Terra's
  standalone llama.cpp pin.
  [Dependencies](https://github.com/Niko1221/Strata/blob/v0.2.8/requirements.txt),
  [build configuration](https://github.com/Niko1221/Strata/blob/v0.2.8/CMakeLists.txt).
- No new ROCm requirement was identified. Source setup uses system ROCm 7
  where available, otherwise its pinned TheRock wheel selection. The HIP
  build checks source hashes and architecture before skipping a rebuild.
  [AMD guide](https://github.com/Niko1221/Strata/blob/v0.2.8/docs/AMD_HIP.md),
  [build implementation](https://github.com/Niko1221/Strata/blob/v0.2.8/setup.py).

## Benchmark priorities

Record the actual commit, engine BUILD.json, model hashes, RAM/VRAM, and
generated config. Hold model, context and prompts constant. Run three paired
repetitions of short chat/code, cold 8K/32K prompts, warm shared-prefix turns,
and a declared-tool round trip with quoted JSON/string arguments. Report time
to first token, generated tokens/s, end-to-end duration, memory, tool-call
validity and errors. Keep single-client results separate from concurrent
requests. Exercise unload/reload through llama-swap.

Expect possible answer changes from decode scheduling and recovered calls.
Keep approximate long-prompt mode (`STRATA_KVA`) off during the initial test.
An optional same-build diagnostic with `STRATA_DEFAULTS=026` can help isolate
new defaults; it does not reproduce the old executable.
[Default switches and limitations](https://github.com/Niko1221/Strata/blob/v0.2.8/docs/release-notes-0.2.7.md).
