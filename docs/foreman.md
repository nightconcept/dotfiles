# foreman

foreman is a lease daemon for terra's GPU, CPUs and RAM. It runs as the user service
`foreman.service`. The module is `modules/linux/programs/foreman/module.py`. The source is
`~/git/foreman` (`forge.solivan.dev/danny/foreman`), pinned by `FOREMAN_COMMIT` in the module.

## Windows

The seed config is `modules/linux/programs/foreman/config.toml`. Deploy writes it to
`~/.config/foreman/config.toml` only when that file is missing. After that, the foreman CLI
owns the file, and a deploy never overwrites it.

| Window | Time | Use |
|---|---|---|
| strata | 06:30 to 00:00 | llama-swap and Strata run. The window reserves 4 cores and 40 GB RAM. No VRAM leases. |
| training | 00:00 to 06:30 | llama-swap is stopped. VRAM leases are allowed. |

foreman stops `llama-swap.service` at 00:00 and starts it at 06:30. It also checks on every
tick, so a reboot during the night does not leave llama-swap running.

## Change the config

Use the CLI. It validates the change and the daemon reloads it.

```bash
foreman config show
foreman config set window.training.end 07:00
foreman config set floor.ram_gb 8
foreman config window add day --start 09:00 --end 17:00 --cores 4
foreman config window rm day
```

Run `foreman` for a status table, or `foreman status --json` for agents.

## Run a job with a lease

```bash
foreman run --vram 20G --cores 8 --ram 16 --reason "vesper train" --until 06:00 -- cmd args
```

If the request does not fit, foreman prints the reason and the next time it could fit, and
exits with code 75. A job that runs past its end time, or uses more than it leased, is killed
unless you pass `--allow-over`. Training jobs must checkpoint.

## Root-owned files

The module installs two files with sudo:

- `/etc/polkit-1/rules.d/50-foreman-llama-swap.rules` lets danny start and stop
  `llama-swap.service` only. The rule tests both the unit and the verb.
- `/etc/systemd/system/user@.service.d/foreman-delegate.conf` sets
  `Delegate=cpu cpuset io memory pids`, so a job scope can be pinned to CPUs.

Check the rule with:

```bash
pkcheck --action-id org.freedesktop.systemd1.manage-units --process $$ -u \
  --detail unit llama-swap.service --detail verb stop
```

## Reboot note

The `Delegate=` drop-in takes effect only after `user@1000.service` restarts. That restart
kills every user unit, including hermes and vesper. Reboot terra once after the first deploy,
at a time you choose. Until then `AllowedCPUs` is ignored, and foreman logs a warning that
cpuset is missing. The file `/sys/fs/cgroup/user.slice/user-1000.slice/user@1000.service/cgroup.controllers`
must list `cpuset` after the reboot.

## Deploys at night

While the training window is open, `llama_swap.py` does not restart llama-swap, and
`hermes.py` skips the check that llama-swap serves the model. Both read
`foreman status --json` (`gpu_leases: true`). Before foreman is installed, they behave as before.
