# Contributing

## Ground rules

- `make check` (shellcheck + bats) must pass. CI runs the same thing.
- Nothing in `bin/` or `lib/` may touch the real system during tests: every
  path goes through the `CBS_*` roots in `lib/common.sh`, and every external
  program goes through `run`, `run_pipe`, `cbs_sudo` or `cbs_timeout` so that
  `--dry-run` prints it and the stubs in `test/stubs/` can log it.
- Destructive steps go behind `confirm`. Never add a reset or repair method
  that is not documented upstream (Chrome OS / Chromebrew).

## Adding a command

1. Create `lib/cmd_<name>.sh`. It must define:
   - `cmd_usage` - prints the help text; end it with `cbs_usage_footer` so the
     shared flags are documented.
   - `cbs_main "$@"` - parses options. Call `cbs_global_flag "$1"` first in the
     loop (it handles `-h/--help`, `-y/--yes`, `-n/--dry-run`, `--version`),
     reject anything unknown with `cbs_usage_error`, then call
     `cbs_require_chromeos`, `confirm "..."` for anything destructive, and do
     the work through `run`/`cbs_sudo`/`run_pipe`.
2. Copy `bin/rw` to `bin/<name>`, change `CBS_CMD_NAME` and the sourced module.
   `chmod +x` it.
3. Add the command to `COMMANDS` in `install.sh`, to `SH_FILES` in the
   `Makefile`, to `scripts/check.sh`, to the loops in
   `.github/workflows/ci.yml`, and to the README usage table.
4. Write tests (below).

Helpers available from `lib/common.sh`:

| helper | use |
| --- | --- |
| `log`, `warn`, `die [CODE] MSG` | output (colored only on a terminal, off with `NO_COLOR`) |
| `confirm QUESTION` | `[y/N]` prompt; auto-yes with `--yes`; refuses on non-tty stdin |
| `run CMD...` | run, or print under `--dry-run` |
| `run_pipe DESC FUNC...` | same for pipelines wrapped in a function |
| `cbs_sudo CMD...` | `run $CBS_SUDO CMD...` |
| `cbs_timeout SECS CMD...` | `run timeout SECS CMD...` |
| `cbs_yes_pipe CMD...` | `yes \| CMD` returning CMD's status |
| `cbs_is_chromeos`, `cbs_require_chromeos`, `cbs_require_not_root MSG` | guards |

## Writing tests

Tests live in `test/*.bats` and `load test_helper`. `setup_sandbox` gives you:

- `$SANDBOX` - a fake root; `CBS_ROOT` points at it, so `/etc/lsb-release`,
  `/mnt/stateful_partition`, `/usr/local`, `/usr/share/vboot/bin` and
  `/home/chronos/user` all live underneath. `CBS_HOME` is a scratch home.
- `CBS_ASSUME_CHROMEOS=1` and `NO_COLOR=1`. Unset the former and call
  `write_lsb_release` to test detection.
- `test/stubs` first on `PATH`: `sudo` (logs, then runs the command),
  `crew`, `curl` (writes a fake installer or a tarball of the repo), `mount`,
  `reboot`, `make_dev_ssd.sh` (copied into the sandbox vboot dir). Each
  appends `name args` to `$STUB_LOG`; set `STUB_EXIT_<name>=N`
  (`STUB_EXIT_make_dev_ssd_sh=1`) to make one fail.
- Assertions: `assert_called`, `assert_not_called`, `assert_output_contains`,
  `calls`.

A new external program needs a stub: add a symlink to `test/stubs/stub.sh`
(generic logger) or a small script, and list it in `SH_FILES`/`check.sh` if it
is a script.

Cover at least: help, every flag, the confirmation refusal without `--yes`,
`--dry-run` leaving the sandbox untouched and logging no calls, and the
failure path (the command must not continue after a failed step).

## Releasing

Bump `VERSION`, update the README's *What changed* section, tag. Users pick it
up with `install.sh --update`.
