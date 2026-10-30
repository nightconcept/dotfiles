# Hermes upgrade research, 2026-10-30

## Recommendation and scope

Upgrade Terra's source installation from `b4f978d983b24ad4ba5ced5bf2c528bcf1c1fb0c`
(August 19) to stable **v0.22.5**, commit
`bf0203a794a07aac3ff764972ab9087baa4e4f4e` (October 22).
Git's peeled release tag resolves to that exact commit. The release page marks it
as latest. This is a substantial runtime migration, not just a Python dependency
refresh. [Release](https://github.com/NousResearch/hermes-agent/releases/tag/v0.22.5),
[installed commit](https://github.com/NousResearch/hermes-agent/commit/b4f978d983b24ad4ba5ced5bf2c528bcf1c1fb0c).

Research inspected a separate `/tmp/hermes-research-20261030` checkout at the
selected stable commit. The installed checkout and its state were not changed.
Local comparisons against the installed commit confirm that the new tool-argument
and reasoning-route regression tests did not exist at the baseline revision.

Terra uses the existing named custom provider `Terra:8080` through llama-swap,
with Qwen3.8 Flash Next IQ2_XS and a 131072-token context. Keep that provider.
The new Hermes-managed llama.cpp/model-download feature is optional; adopting it
would duplicate the existing serving stack. Neither its engine recommendations
nor its MTP model catalog automatically accelerates Terra's Strata server.
[Local-model feature scope](https://github.com/NousResearch/hermes-agent/releases/tag/v0.22.0).

## Benefits for this instance

| Change | Expected benefit on Terra | Evidence and qualification |
| --- | --- | --- |
| Smaller fixed prompt and deferred tool definitions | Less prefill work and more usable context on a heavily quantized local model | Upstream reports about 2,100 fewer fixed prompt tokens and roughly half the desktop tool-schema payload. Measure the actual Hermes tool set; the desktop figure is not a Terra guarantee. [Release notes](https://github.com/NousResearch/hermes-agent/releases/tag/v0.22.0). |
| Local OpenAI-compatible reasoning replay | Better continuity in long reasoning/tool sessions | The selected source tests local `http://127.0.0.1:8080/v1` routes with reasoning carriers. Verify Qwen/Strata actually emits the supported carrier and does not expose reasoning as final text. [Route tests](https://github.com/NousResearch/hermes-agent/blob/bf0203a794a07aac3ff764972ab9087baa4e4f4e/tests/agent/test_reasoning_replay_routes.py). |
| Tool-call recovery | Fewer failed resumed sessions after malformed/truncated tool arguments | New tests accept dict-shaped arguments and replace corrupt historical JSON with a marked empty object. This repairs protocol shape; it cannot recover the lost arguments. [Dict tests](https://github.com/NousResearch/hermes-agent/blob/bf0203a794a07aac3ff764972ab9087baa4e4f4e/tests/agent/test_dict_tool_call_args.py), [sanitizer tests](https://github.com/NousResearch/hermes-agent/blob/bf0203a794a07aac3ff764972ab9087baa4e4f4e/tests/agent/test_tool_call_args_sanitizer.py). |
| Compaction fallback continuity | Better retention of task details across long sessions | The new regression preserves fallback handoff anchors for the next summary; structural no-op compression now backs off instead of permanently disabling useful compression. [Compaction tests](https://github.com/NousResearch/hermes-agent/blob/bf0203a794a07aac3ff764972ab9087baa4e4f4e/tests/agent/test_context_compressor_summary_continuity.py). |
| Managed dependency generations | More dependable idempotent upgrades | PM checks a fresh environment before selecting it. A failed preparation keeps the previous selection, rather than partially replacing a live venv. [Pinned PM contract](https://github.com/NousResearch/hermes-agent/blob/bf0203a794a07aac3ff764972ab9087baa4e4f4e/website/docs/reference/package-management.md). |
| Wider approval guards | Useful defense for the configured local model | Command-deny globs use normalized/deobfuscated variants before YOLO bypass; gateway `execute_code` requests whole-script approval. These remain execution controls, not a change to the model's behavior. [Deny implementation](https://github.com/NousResearch/hermes-agent/blob/bf0203a794a07aac3ff764972ab9087baa4e4f4e/tools/approval_floors.py), [script guard](https://github.com/NousResearch/hermes-agent/blob/bf0203a794a07aac3ff764972ab9087baa4e4f4e/tools/approval.py#L1216). |

Expected gains are agent reliability and prefill savings. No evidence establishes
higher decode tokens/second or improved IQ2_XS model quality from Hermes alone.
That needs the controlled benchmark below.

## Exact pin-compatible installation flow

The selected stable `pm/lock.json` pins **Python `3.14.9+20261021`**, uv `0.13.5`,
and Node `26.12.1`, with platform artifacts and SHA-256 hashes. PM owns these
pins; repeating them independently in dotfiles risks disagreement. The broad
Python requirement permits updater bootstrapping, but the supported managed
runtime is Python 3.14. Do not retain the old Python 3.11 venv as the new runtime.
[Exact tool lock](https://github.com/NousResearch/hermes-agent/blob/bf0203a794a07aac3ff764972ab9087baa4e4f4e/pm/lock.json),
[pinned installer](https://github.com/NousResearch/hermes-agent/blob/bf0203a794a07aac3ff764972ab9087baa4e4f4e/scripts/install.sh).

After stopping the gateway, taking the existing full backup, and selecting the
exact Git commit, the official script's isolated stages provide a concrete
noninteractive implementation path:

```bash
checkout="$HOME/.hermes/hermes-agent"
bash "$checkout/scripts/install.sh" --stage python-deps \
  --dir "$checkout" --hermes-home "$HOME/.hermes" --non-interactive
bash "$checkout/scripts/install.sh" --stage products \
  --dir "$checkout" --hermes-home "$HOME/.hermes" --non-interactive
"$HOME/.local/bin/hermes" gateway install --force --no-start-now
```

These stage calls do not run the installer `repository` stage, so they do not
replace the caller's selected Git commit. `python-deps` bootstraps verified uv
and a bootstrap interpreter, then calls `python -m pm.cli install`.
`products` calls isolated `hermes_cli/source_completion.py --source`, which
re-enters PM's selected environment, publishes the launcher, builds interfaces,
synchronizes bundled skills and migrates configuration. It does not request the
interactive setup wizard. Its default `gateway_mode` is false; the full Terra
module should retain responsibility for starting the gateway after model config.
[Installer stage dispatch](https://github.com/NousResearch/hermes-agent/blob/bf0203a794a07aac3ff764972ab9087baa4e4f4e/scripts/install.sh#L1203),
[source completion](https://github.com/NousResearch/hermes-agent/blob/bf0203a794a07aac3ff764972ab9087baa4e4f4e/hermes_cli/source_completion.py).

The bare PM install matches official source defaults (`all`, not `--all-extras`).
Browser/computer-use downloads are optional defaults. Their explicit installer
opt-outs persist across later runs, so do not introduce them casually during
migration. PM builds the union of core, recorded extras and enabled plugins;
plugin dependencies can require an extended resolution outside the committed
core lock. This is stronger managed ownership, not a claim that arbitrary
plugins and lazy tools are frozen by the Hermes commit.
[PM install implementation](https://github.com/NousResearch/hermes-agent/blob/bf0203a794a07aac3ff764972ab9087baa4e4f4e/pm/cli.py#L344),
[PM state and plugin contract](https://github.com/NousResearch/hermes-agent/blob/bf0203a794a07aac3ff764972ab9087baa4e4f4e/website/docs/reference/package-management.md).

After migration, the launcher resolves PM's chosen environment under
`~/.hermes/installs/INSTALL_KEY/environments/`; `venv/bin/python` is no longer the
runtime authority. Regenerate the unit using the published launcher. The new
unit generator uses `installation_command` and PM-managed tool paths. Validate
with `hermes pm doctor`, `hermes pm status`, and CLI import/version checks.
A matching deploy should validate existing state without resynchronizing or
building. New generations remain path-dependent; do not move them manually.
[PM paths](https://github.com/NousResearch/hermes-agent/blob/bf0203a794a07aac3ff764972ab9087baa4e4f4e/website/docs/reference/package-management.md),
[unit generation](https://github.com/NousResearch/hermes-agent/blob/bf0203a794a07aac3ff764972ab9087baa4e4f4e/hermes_cli/gateway.py#L3196).

## State and safety checks

- Take the old CLI's full backup before changing source. The new gateway session
  runtime writes history older releases cannot safely consume. Restoring an old
  commit alone is not a rollback; restoring compatible prior state is required.
  Interrupted admitted work can become `unknown` and need explicit discard.
  [Pinned update/migration guide](https://github.com/NousResearch/hermes-agent/blob/bf0203a794a07aac3ff764972ab9087baa4e4f4e/website/docs/getting-started/updating.md).
- Source beats older release summaries: v0.22.0 notes say automatic 90-day
  pruning defaults on, but **v0.22.5 source sets `sessions.auto_prune: false`**.
  Confirm the effective existing config, rather than assuming either retention
  policy. [Selected defaults](https://github.com/NousResearch/hermes-agent/blob/bf0203a794a07aac3ff764972ab9087baa4e4f4e/hermes_cli/config_defaults.py#L2274).
- Existing `approvals.deny` remains supported. Arbitrary Python does not become
  equivalent to a shell deny-pattern check: gateway whole-script approval is
  skipped by YOLO/off, while local interactive viewer turns have exemptions.
  Keep Pi-hole and the independent IoC monitor.
  [Selected approval contract](https://github.com/NousResearch/hermes-agent/blob/bf0203a794a07aac3ff764972ab9087baa4e4f4e/website/docs/user-guide/security.md#execute-code-scripts).
- The IoC reader's SQL columns still exist (`messages.id`, `session_id`,
  `tool_calls`, `content`, `role`; `sessions.id`, `source`). Read-only schema
  compatibility looks intact, but verify scanner health after the first gateway
  writes. [Selected database schema](https://github.com/NousResearch/hermes-agent/blob/bf0203a794a07aac3ff764972ab9087baa4e4f4e/hermes_state_common.py#L461).
- Run `hermes config check` and inspect migration notices. Config completion
  touches profiles as well as the default config; unsupported plugins may sit
  out or be disabled. Keep the backup and avoid simultaneous old/new processes
  on the same home. [Pinned update behavior](https://github.com/NousResearch/hermes-agent/blob/bf0203a794a07aac3ff764972ab9087baa4e4f4e/website/docs/getting-started/updating.md).

## Benchmark protocol

Record exact software SHAs, serving flags, model hash/quantization, context,
GPU memory, temperatures and concurrent load. Use the same model and test input
before/after. Distinguish cold model load from a warm request and repeat warm
cases at least three times.

1. **Serving:** fixed short completion, longer generation and long-context
   prompt through llama-swap. Record load time, first-token latency, prompt and
   completion token counts, elapsed time, decode rate and peak memory.
2. **Tools:** one structured call with required arguments, parallel calls,
   tool result followed by final text, and malformed argument recovery. Require
   correct calls and answers; count retries as failures or extra work.
3. **Hermes:** a harmless read/search task on fixed files, a multi-step reasoning
   task, and resume/compaction continuity. Record task success, tool-call count,
   request/prompt tokens and total latency. This captures agent gains serving
   throughput alone misses.
4. **Safety:** exercise a synthetic deny match with `hermes approvals test`
   against the configured rules. Never execute real exfiltration commands.
   Check `hermes-ioc-alert` service logs and database-read health separately.
5. **Idempotence:** deploy the same pins twice. The second run must skip runtime
   preparation and backup, retain source SHA/environment selection, and leave
   the intended gateway and router healthy.

These are measurements to run after deployment; this research did not execute
production inference, upgrade Hermes, or claim measured speed improvements.
