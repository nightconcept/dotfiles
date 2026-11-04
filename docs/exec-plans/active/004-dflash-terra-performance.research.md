# Research: DFlash2 performance on Terra

**ID:** 004
**Date:** 2026-11-03
**Issue/Ref:** Explain the DFlash2 regression and restore MTP.
**Status:** complete

## Summary

Terra's Strata v0.2.10 benchmark recorded 57.6 tokens/s with DFlash2 and 73.5 tokens/s with MTP, a 21.6% regression. DFlash2 proposed more tokens for essentially the same accepted-token count, so verification did more work. Upstream's defaults and reported gains do not establish a win for Terra's IQ2_XS target. Keep MTP active; attribute the regression to lower proposal efficiency and probable draft/verification overhead until profiling separates those costs.

## Relevant Files

| File | Role |
|------|------|
| `modules/linux/ai/catalog.py` | Target model, MTP serving arguments, and model storage pins. |
| `modules/linux/ai/strata/module.py` | Deploys Strata and renders its server configuration. |
| `modules/linux/ai/versions.toml` | Pins Strata v0.2.10 to `ffa80d73133ea5c548aefe57889a16e8085a938f`. |
| `scripts/bench-ai-stack.py` | Runs correctness cases and records server timings and client latency. |
| Terra: `~/.local/state/ai-bench/20261103T162716918443Z-after/` | MTP baseline, three samples per case. |
| Terra: `~/.local/state/ai-bench/20261103T165232316076Z-dflash2/` | DFlash2 samples and `drafting-runtime.json` evidence. |
| Terra: `~/git/Strata/strata-iq2_xs.log` | Actual engine commands, cache statistics, and draft acceptance. |
| Upstream: `strata_control/drafting.py` | Drafter pack integrity checks and hardware/default selection. |
| Upstream: `src/spec/window_rule_test.cpp` | Tests confidence-based speculative window selection. |

## Data / Control Flow

The repository catalog feeds the deployed Strata server configuration. llama-swap launches the server, which starts the HIP engine on Terra's R9700. A drafter proposes tokens; the target verifies them, commits accepted tokens, and rejects the remainder. The benchmark saves server-reported `predicted_per_second`, `draft_n`, and `draft_n_accepted` separately from request latency.

DFlash2 ran with `--draft dflash2 --spec 6 --draft-conf 0.35 --draft-fallback none`, a verified Q4_0 pack, and an internal window of up to eight tokens. The log confirms a 725 MiB drafter and no loaded MTP layer. The DFlash artifact's `metadata.json` contains catalog MTP arguments; use its `drafting-runtime.json` and the engine log for the actual drafting mode.

## Root Cause / Insertion Point

These are measured results for the three sustained-generation requests, each producing 256 tokens:

| Mode | Sample | Decode tokens/s | Accepted/proposed | Acceptance |
|------|--------|-----------------|-------------------|------------|
| MTP | 0 | 67.2 | 123/231 | 53.2% |
| MTP | 1 | 73.7 | 123/228 | 53.9% |
| MTP | 2 | 73.5 | 117/243 | 48.1% |
| DFlash2 | 0 | 54.6 | 122/259 | 47.1% |
| DFlash2 | 1 | 57.6 | 123/288 | 42.7% |
| DFlash2 | 2 | 62.8 | 123/296 | 41.6% |

Aggregate acceptance fell from 363/702 (51.7%) to 368/843 (43.7%). DFlash proposed 20.1% more tokens for five more accepted tokens. The counters include the engine's drafting mechanisms; they are not a drafter-only quality score. In warm sample 1, expert lookups increased from 172,604 to 201,312 (+16.6%), and KV block reads from 185,208 to 211,656 (+14.3%). This supports extra verification work as a contributor, while separate draft/verify timings were not recorded.

A smaller expert cache does not explain this run: DFlash had 19,431 slots against MTP's 19,378, and both warm sample-1 cache hit rates were 99.8%. The adaptive PCIe share differed (0.25 versus 0.20), which is a confound for precise attribution.

Upstream's [v0.2.10 release](https://github.com/Niko1221/Strata/releases/tag/v0.2.10) reports R9700 gains with app sampling, while [the pinned drafting policy](https://github.com/Niko1221/Strata/blob/v0.2.10/strata_control/drafting.py) identifies its R9700 measurements as UD-Q4_K_XL. That differs from Terra's IQ2_XS target. The same policy says `spec=6` was selected on Blackwell and the confidence steps were calibrated on CUDA cards; HIP has no separate confidence override. Terra's settings therefore are supported defaults rather than a demonstrated optimum for this target.

The pinned policy also reports Q4_0 versus Q8 draft speed differing by only -0.3%. That is evidence against blaming Q4_0 alone, although this benchmark did not directly compare the two. [Issue 3965](https://github.com/Niko1221/Strata/issues/3965) records another hardware-specific slowdown with higher draft and expert-pool costs; its RTX 4060 Ti setup and MTP fallback differ from Terra's run.

## Recommended Approach

Restore catalog MTP arguments (`--spec 4 --spec-min-p 0.5 --mtp …/mtp/rt`) and verify the live engine reports MTP. Retain the draft pack and benchmark artifacts. Any later DFlash experiment should use interleaved MTP/DFlash requests on the same target, sweep confidence/window settings, and capture stage timings before drawing a quantization conclusion.

## Risks & Non-Obvious Dependencies

- Three samples per case cannot establish small performance differences; the consistent sustained regression is the useful signal here.
- Sequential runs allow thermal, cache, and adaptive PCIe policy effects.
- Fifteen output checks passed per mode; these checks do not measure general agent quality or distribution equivalence.
- A draft matching the model family does not guarantee high acceptance against every target quantization.
- Missing draft context was logged for tool-result turns, not for the sustained-generation comparison; it cannot explain that main regression.

## Rejected Approaches

| Approach | Why Rejected |
|----------|-------------|
| Blame a smaller expert cache | The measured DFlash cache was larger. |
| Treat Q4 draft and IQ2 target as incompatible | The runtime loaded correctly and all fixture checks passed. |
| Assume upstream R9700 gains apply unchanged | The measured target quantization and sampling profile differ. |
| Tune production immediately | MTP already delivers better measured throughput; tuning can remain a later experiment. |

## Open Questions

- [ ] How much time does this HIP build spend drafting versus verifying under each mode?
- [ ] Would different confidence/window settings improve acceptance enough on IQ2_XS?
- [ ] How much of the gap remains with interleaved runs and a fixed PCIe policy?
