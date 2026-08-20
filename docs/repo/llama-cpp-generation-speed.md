# Qwen3.8-27B generation-speed options on Terra

Research date: 2026-08-19. Target stack: `llama.cpp` on ROCm/HIP, AMD Radeon AI PRO R9700 (`gfx1201`), Qwen3.8-27B UD-Q5_K_XL. Qwen3.6-MTP and Muse-Glimmer are reference points, not the optimization target.

## Recommendation

Enable Qwen3.8's embedded MTP first, then measure draft widths 2, 3, and 4 against the current non-speculative server. Terra's local GGUF metadata contains `qwen35.nextn_predict_layers=1`, so it already carries an MTP/NextN head; the current catalog simply does not request it. No second model download is required for this file.

Start with:

```text
--spec-type draft-mtp --spec-draft-n-max 2
```

Sweep `2`, `3`, and `4`; do not assume a larger draft is faster. Upstream's merged MTP work shows acceptance and speed vary materially by task and draft width, and a later regression investigation found that the corrected implementation can favor `n=2` over `n=3`. MTP also adds its own context/KV state, so confirm that ROCm VRAM remains resident rather than spilling to GTT. [Merged MTP implementation and usage](https://github.com/ggml-org/llama.cpp/pull/22673), [draft-width regression discussion](https://github.com/ggml-org/llama.cpp/issues/23230), [ROCm GTT spill report](https://github.com/ggml-org/llama.cpp/issues/26432)

Keep `llama-bench` as the official raw target-model benchmark. It measures prompt processing and single-token generation without tokenization or sampling, but it does **not** exercise server speculative decoding. Use upstream's SPEED-Bench client only for the separate server A/B of baseline versus MTP; it reports end-to-end decode speed, latency, and draft acceptance by workload category. [llama-bench README](https://github.com/ggml-org/llama.cpp/blob/master/tools/llama-bench/README.md), [SPEED-Bench README](https://github.com/ggml-org/llama.cpp/blob/master/tools/server/bench/speed-bench/README.md)

## Measured on Terra

The 2026-08-19 SPEED-Bench run used two prompts from each of `coding`, `reasoning`, `summarization`, and `writing`, 256 maximum output tokens, and concurrency one. All configurations used the same Qwen3.8 UD-Q5_K_XL target, 131072 context, full GPU offload, flash attention, and Q8 K/V. The raw artifacts are in `/home/danny/.hermes/benchmarks/20260819-083809-qwen38-speed/`.

| Configuration | Decode t/s | Decode vs baseline | Average latency | Latency vs baseline | Draft acceptance |
| --- | ---: | ---: | ---: | ---: | ---: |
| Baseline | 24.006 | 1.000x | 10.948 s | 1.000x | n/a |
| MTP, width 2 | 40.129 | 1.672x | 6.891 s | 1.589x | 68.43% |
| MTP, width 3 | 39.745 | 1.656x | 7.036 s | 1.556x | 59.16% |
| MTP, width 4 | 36.777 | 1.532x | 7.551 s | 1.450x | 49.92% |
| MTP2, one slot | 40.090 | 1.670x | 6.867 s | 1.594x | 68.43% |
| MTP2, one slot, backend sampling | 40.604 | 1.691x | 6.834 s | 1.602x | 68.43% |
| MTP2, one slot, ngram-mod | 42.453 | 1.768x | 6.606 s | 1.657x | 63.80% |

The selected Qwen3.8 candidate is MTP width 2 plus `ngram-mod` and one server slot. It was the fastest measured configuration at 42.453 decode tokens/s, 76.8% above baseline. Its gain over plain MTP2 was driven by reasoning and writing; coding was effectively unchanged. One slot was neutral in isolation, but it is retained so the selected profile exactly matches the winning benchmark configuration. The 1.3% backend-sampling change is too small to distinguish confidently from run variance and is not enabled.

## Available now

### 1. Embedded MTP: highest-priority trial

`llama.cpp` merged Qwen3.5/3.6 NextN support in May 2026 and exposes it as `draft-mtp`. The implementation creates an MTP context against the main model and uses heads carried by that GGUF. Upstream examples use `--spec-type draft-mtp --spec-draft-n-max N`; the same `qwen35` architecture loader handles Qwen3.8. [MTP PR](https://github.com/ggml-org/llama.cpp/pull/22673), [current Qwen35 model implementation](https://github.com/ggml-org/llama.cpp/blob/master/src/models/qwen35.cpp), [speculative-decoding reference](https://github.com/ggml-org/llama.cpp/blob/master/docs/speculative.md)

Expected impact must be measured on Terra. Upstream Qwen3.6 tests show that MTP can improve generation substantially, but gains depend on acceptance, backend, prompt type, and width. A current Qwen3.8 DFlash2 evaluation on H200 reports built-in MTP at roughly 1.96-2.59x autoregressive throughput across five tasks, while an open llama.cpp PR reports smaller hardware-dependent gains. These are useful ceilings, not predictions for ROCm/RDNA4. [Qwen3.8 DFlash2 model card](https://huggingface.co/incoai/Qwen3.8-27B-DFlash2), [open llama.cpp DFlash2 PR](https://github.com/ggml-org/llama.cpp/pull/27342)

The current Unsloth Qwen3.8 repository also publishes a 1.37 GB `MTP/mtp-Qwen3.8-27B-Q4_0.gguf` sidecar. Current llama.cpp can identify a NextN sidecar after the August 13 MTP auto-detection merge. This is relevant when refreshing to a newer target GGUF that has separated its MTP weights. It is unnecessary for Terra's present combined file. [Unsloth Qwen3.8 GGUF repository](https://huggingface.co/unsloth/Qwen3.8-27B-GGUF/tree/main), [MTP sidecar auto-detection PR](https://github.com/ggml-org/llama.cpp/pull/27005)

### 2. N-gram speculation: workload-specific, near-zero memory cost

Current llama.cpp provides `ngram-simple`, `ngram-map-*`, and `ngram-mod` without a draft model. `ngram-mod` uses about 16 MB and is intended for repeated text, code editing, summarization, and reasoning that restates prior content. It is unlikely to accelerate novel prose consistently. After selecting the best MTP width, test MTP plus `ngram-mod` on Hermes coding/tool workloads; draftless speculation takes precedence when it finds a match. Upstream labels the MTP-plus-ngram combination advanced/experimental, so it should not be enabled from synthetic throughput alone. [Speculative-decoding documentation](https://github.com/ggml-org/llama.cpp/blob/master/docs/speculative.md), [MTP combined example](https://github.com/ggml-org/llama.cpp/pull/22673)

### 3. Backend sampling: small end-to-end opportunity

`--backend-sampling` moves supported target-model sampling to the backend; draft sampling is already backend-enabled by default. It can remove CPU/device synchronization overhead but will not change a `llama-bench` result. Compare it through the server with the real Qwen sampling settings. Unsupported samplers or layouts fall back to CPU, and stochastic output can differ slightly because floating-point operations differ. [Backend-sampling documentation](https://github.com/ggml-org/llama.cpp/blob/master/docs/speculative.md#backend-sampling)

### 4. Retain the current basic decode configuration

For one interactive stream, retain full GPU offload, HIP/ROCm, and flash attention, and test one server slot (`-np 1`) against the current automatic slot count. More slots improve aggregate concurrency, not necessarily single-request latency. Q8 K/V is a reasonable quality/memory balance; moving to Q4 K/V primarily frees memory for longer context or speculation and should not be assumed to increase short-context token generation. A smaller target quant can increase memory-bandwidth-limited decode, but it changes model quality and must be treated as a separate model-quality decision. ROCm fully supports K-quants, while some I-quants can use slower paths. [llama.cpp feature matrix](https://github.com/ggml-org/llama.cpp/wiki/Feature-matrix)

## Promising but not production-ready

### DFlash2 for Qwen3.8

A target-specific Qwen3.8-27B DFlash2 draft now exists in BF16, Q8_0, and Q4_K_M; the Q4_K_M draft is about 1.1 GB. Its first-party model card reports 2.67-3.43x autoregressive throughput at concurrency 1 on H200, outperforming built-in MTP in that environment. However, llama.cpp support is still open in PR #27342 as of this report, not present in the pinned production commit. The PR reports 1.77-1.85x on Apple M5 Pro and also contains reports that optimal draft width varies by hardware, multi-sequence performance can collapse, and vision requests currently need additional fixes. Do not pin production to this PR yet. Re-evaluate after merge, then test Q4_K_M with widths 4-7 on Terra. [DFlash2 GGUF model card](https://huggingface.co/z-lab/Qwen3.8-27B-DFlash2-GGUF), [open llama.cpp DFlash2 PR](https://github.com/ggml-org/llama.cpp/pull/27342)

EAGLE3, original DFlash, DSpark, and a generic small autoregressive draft all require a draft trained for or tokenizer-compatible with this exact target. The current official llama.cpp documentation lists examples for older Qwen3 models, not a supported Qwen3.8-27B assistant other than the newly published DFlash2 work. They are lower-priority than the embedded MTP that Terra already owns. [Current speculative methods](https://github.com/ggml-org/llama.cpp/blob/master/docs/speculative.md)

## RDNA4/ROCm notes

Stay on HIP/ROCm. An open gfx1201 report measures Vulkan generation 4.7-6.7x slower than HIP for dense Qwen shapes with hidden size 4096 or larger. [RDNA4 Vulkan issue](https://github.com/ggml-org/llama.cpp/issues/26663)

Do not downgrade llama.cpp solely to recover the removed rocWMMA flash-attention path for generation speed. On the same R9700/gfx1201 hardware, the reported native-kernel regression is in deep-context prompt processing; token generation is unchanged to 3.9% faster with the current native path. A frozen older build is only a possible prefill workaround. [RDNA4 flash-attention issue](https://github.com/ggml-org/llama.cpp/issues/26220)

Watch actual VRAM and GTT use during all speculative tests. MTP creates additional context/KV allocations, and upstream has documented silent ROCm spill at large context with more than 60% throughput loss. If this occurs at the configured 131072 context, reduce the configured context or the draft KV type before judging MTP itself. [ROCm MTP spill issue](https://github.com/ggml-org/llama.cpp/issues/26432)

## Concrete evaluation order

1. Preserve the existing five-repetition `llama-bench` Qwen3.8 baseline as the raw, non-speculative reference.
2. Run SPEED-Bench against the same server configuration with no speculation, then MTP `n=2`, `n=3`, and `n=4`. Use `qualitative` categories relevant to Hermes and `concurrency=1`.
3. Select by end-to-end latency and decode speed, with acceptance rate and VRAM/GTT as diagnostics. Do not compare server MTP numbers directly with `llama-bench` TG numbers.
4. Test the winner with `--backend-sampling`, then with `ngram-mod`, one change at a time.
5. After DFlash2 lands upstream, compare its Q4_K_M draft against the winning MTP setup. Keep Qwen3.6-MTP live until Qwen3.8 wins on representative Hermes work, not only a short synthetic decode.
