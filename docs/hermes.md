# Hermes

Hermes (`~/.hermes`) runs on terra as the user service `hermes-gateway`. It is installed and
configured outside dotfiles. `modules/linux/programs/hermes.py` only points it at llama-swap's
default model.

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

`modules/linux/services/hermes_ioc_alert/` installs a root system timer. Every minute, it
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
