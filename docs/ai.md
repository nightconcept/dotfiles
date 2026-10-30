# Terra AI stack

`modules/linux/ai/module.py` exposes `AIStackModule.deploy()` to Terra's host config.
The module owns the model catalog, Strata, llama.cpp, llama-swap, Hermes, and Hermes alerts.
Foreman, Hugging Face CLI, and Colab remain independent tooling in the host config.

The deployment order is:

1. Prepare model storage and catalog files.
2. Prepare Strata and its model packs.
3. Prepare llama.cpp.
4. Configure and restart llama-swap, unless Foreman's GPU lease window is open.
5. Prepare the pinned Hermes runtime and update its model config.
6. Restart Hermes and enable its alert timer.

Foreman remains the authority for GPU lease windows.
The router does not start during an open window.
Hermes skips the router model-list check during that window.

## Software and model pins

`modules/linux/ai/versions.toml` records software pins for llama.cpp, llama-swap, Strata, and Hermes.
Git source pins use full commit hashes.
The Strata release label describes its commit and selects the initial shallow clone.
The llama-swap binary downloads use architecture-specific SHA-256 hashes.
The Hermes pin also selects Python and the upstream extras.
Environment variables no longer override llama.cpp or llama-swap source versions.

`modules/linux/ai/catalog.py` records model IDs, files, serving arguments, and the default model.
Strata model shards retain their repository revision and SHA-256 hashes.
The existing GGUF downloads retain their filename-based installation behavior.
The module does not delete existing model data during a deploy.

These pins select source revisions and selected downloads.
The system ROCm packages and compilers remain host dependencies, outside this manifest.
The llama.cpp build cache still uses the source revision and HIP library presence.
Changes to compiler packages or build flags require an explicit rebuild of that engine.

## Deploy and update

On Terra, run this command from the dotfiles directory:

```bash
just terra
```

`flake-rebuild terra` remains the normal wrapper for local or remote deployment.
Both entrypoints deploy the full host, including independent tooling.
Hugging Face and Colab retain their existing upgrade behavior.

For software updates, edit `versions.toml` and deploy Terra.
An AI can resolve the selected upstream commits and download hashes directly.
No separate update command or deployment entrypoint is necessary.
Strata release labels and commits must refer to the same revision.
For llama-swap updates, update the version and both architecture hashes together.
For Hermes updates, use the [pinned upgrade procedure](hermes.md#pinned-upgrades).

The initial consolidation preserves the existing software revisions.
The first managed Hermes deploy creates a backup and synchronizes its locked environment.
Later matching deploys skip Hermes runtime preparation.

## Checks

Run the isolated Hermes deployment tests:

```bash
python3 -m unittest discover -s tests -p 'test_ai_*.py' -v
```

These tests use temporary Git checkouts and command adapters.
They do not change the running gateway or install host packages.
They cover repeated deploys, state backups, edited source, failed upgrades, and downgrade refusal.

For a full host preview, run:

```bash
uv run pyinfra --dry @local hosts/linux/terra/main.py
```

The preview gathers host facts but does not run deployment operations.
Some facts require sudo access.
