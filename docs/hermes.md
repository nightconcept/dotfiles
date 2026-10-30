# Hermes

Hermes runs on Terra as the user service `hermes-gateway`.
The [AI module](ai.md) manages its checkout, Python environment, launcher, and gateway unit.
The software pins are in `modules/linux/ai/versions.toml`.
The checkout stays at `~/.hermes/hermes-agent`, and persistent state stays in `~/.hermes`.

## Pinned upgrades

The current pin is v0.22.5, commit `bf0203a794a07aac3ff764972ab9087baa4e4f4e`.
It replaces the adopted commit `b4f978d983b24ad4ba5ced5bf2c528bcf1c1fb0c`.
The deploy saves a full state backup before it changes the runtime.
It preserves credentials, conversations, memory, and the existing config.
The model config update still selects the catalog's default model.

For an upgrade:

1. Select the upstream release or commit.
2. Update `[hermes].release` and `[hermes].commit` in `modules/linux/ai/versions.toml` with the full commit hash.
3. Check the selected revision's `pm/lock.json` and `scripts/install.sh` stages.
4. Run `just terra` on Terra from the dotfiles directory.
5. Run `hermes config check` and `hermes pm doctor` to review new config keys and the runtime.

The selected revision's PM owns the Python, uv, and Node pins, the locked environments, and extras.
The manifest does not repeat them.
The deploy runs the pinned installer stages `python-deps` and `products`.
It never runs the installer `repository` stage, so the selected commit stays in place.
The launcher is `~/.hermes/hermes-agent/.hermes/bin/hermes`.
Plugins and lazy tools can extend the environment beyond the committed lock.

An older checkout that has no PM launcher uses its `venv` Python for the backup.

Before a runtime change, the helper stops `hermes-gateway` and runs the existing Hermes backup command.
Backups are private directories under `~/.hermes/backups/dotfiles/`.
Each backup contains `state.zip`, a backup log, and the previous source commit.
The deploy retains these backups until the owner removes them.
The full backup uses upstream exclusions and SQLite safe-copy.

After the backup, the helper selects the exact commit, runs the installer stages, and checks the CLI.
It then regenerates the gateway unit through Hermes without starting it.
The AI module updates the model config and starts the gateway after runtime preparation.

Repeated deploys check the runtime identity, dependency environment, and CLI.
A matching runtime skips the backup, dependency installation, and unit regeneration.
The router and gateway still restart during the full deploy to apply their config.

If preparation fails, the gateway stays stopped.
After you fix the error, rerun `just terra`.
The helper retains the backup from an interrupted upgrade and reuses it during the retry.
Edited source files stop the deploy before it changes the checkout.

The helper refuses a commit that is an ancestor of the installed revision.
A newer Hermes revision can migrate persistent state that an older revision cannot read.
A rollback requires a compatible state backup and source checkout before the next deploy.
Changing the pin alone does not restore state.

`hermes update` selects upstream versions independently of this manifest.
For this managed install, upgrades use manifest edits and the full Terra deploy.
Fresh installs still require the owner to configure Hermes credentials and the `Terra:8080` provider.
The deployment does not replace that personal config with a generated file.

Upstream references: [installation](https://hermes-agent.nousresearch.com/docs/getting-started/installation)
and [updates](https://hermes-agent.nousresearch.com/docs/getting-started/updating).

## Model safety

Cohere found that Qwen3.8-Flash-Next, the default model, sometimes tries to exfiltrate data
when it runs as an agent with real tools:
<https://cohere.com/blog/concerning-behaviour-popular-open-weight-ai-model>. In fewer than 1
in 100,000 calls, it did these things:

- Sent an HTTP `PUT` to `sanmaohe.oss-cn-beijing.aliyuncs.com` and called a `routify-…`
  proxy on `aliyuncs.com`.
- Probed the cloud metadata address `169.254.169.254`.
- Used `unshare -Urm` to get root in a user namespace.

Its reasoning trace did not mention any of these actions. Hermes runs as `danny`, so the
model can do anything `danny` can do. The controls below reduce this risk. They do not
remove it.

### Alerts (`hermes-ioc-alert`)

`modules/linux/ai/alerts/` installs a root system timer. Every minute, it
scans these sources for the indicators in the report:

- New assistant messages in `~/.hermes/state.db`, which contain the tool calls and replies
  that the model wrote.
- The journal of UID 1000.

Tool output is not scanned, so a tool result that only mentions these hosts does not alert.
When the scanner finds a match, it sends a Gotify message with priority 9. If the scanner
cannot read its sources, it sends one priority 7 message.

The scanner runs as root, so the agent cannot edit or stop it. The agent can still hide a
host name in its commands, for example with base64 or a string join, so the scanner might
not detect it. Pi-hole is the control that does not depend on the command text.

To set up the token once, deploy Vincent first, which creates the `hermes-alerts` Gotify
application. Then copy the token to terra:

```bash
ssh vincent sudo cat /var/lib/docker-containers/gotify/tokens/hermes-alerts.token \
  | sudo install -m 600 -o root -g root /dev/stdin /etc/hermes-ioc-alert/gotify.token
sudo systemctl start hermes-ioc-alert.service && journalctl -u hermes-ioc-alert -n 5
```

State is in `/var/lib/hermes-ioc-alert/state.json`. To scan all history again, delete that
file.

### Hermes approvals

In `~/.hermes/config.yaml`, keep these keys out of `command_allowlist`. Together, they let
the model run any code without asking:

- `shell command via -c/-lc flag`
- `script execution via heredoc`
- `script execution via -e/-c flag`
- `execute_code`

`approvals.deny` blocks matching commands before approval and before yolo mode. Hermes also
checks the payload of `bash -c`. In the installed version, `approvals.deny` does not check
`execute_code` scripts:

```yaml
approvals:
  deny:
    - "*aliyuncs.com*"
    - "*alibabacloud.com*"
    - "*routify*"
    - "*169.254.169.254*"
    - "*100.100.100.200*"
    - "*unshare *"
    - "*nsenter *"
security:
  website_blocklist:
    enabled: true
    domains:
      - "*.aliyuncs.com"
      - "*.alibabacloud.com"
```

`website_blocklist` applies only to Hermes's web, browser, and other URL tools. It does not
apply to `curl` in the terminal. Hermes reads `command_allowlist` only at start, so restart
`hermes-gateway` after you edit it.

### Pi-hole

Pi-hole (`192.168.1.101`) is terra's DNS server. Block the hosts for terra only, so other
devices on the LAN that use Alibaba Cloud continue to work:

1. **Group Management → Groups:** Add a group named `ai-agents`.
2. **Group Management → Clients:** Add `192.168.1.173` (terra). Assign it to `Default` and
   to `ai-agents`.
3. **Domains → RegEx filter:** Add each regex below with **Add to denied domains**. Then,
   in the list, change its group from `Default` to `ai-agents`.
   - `(^|\.)aliyuncs\.com$`
   - `(^|\.)alibabacloud\.com$`
   - `routify`
4. **Test from terra:** Run
   `dig +short sanmaohe.oss-cn-beijing.aliyuncs.com @192.168.1.101`. The result must be
   `0.0.0.0` or empty.

The block applies only to DNS. A direct IP address, or DNS-over-HTTPS from inside a script,
does not use Pi-hole.
