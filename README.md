# Chromebrew scripts

Bash utilities for Chrome OS / Chromium OS: install, remove or update
[Chromebrew](https://github.com/chromebrew/chromebrew), powerwash the device,
remove rootfs verification and remount the filesystem read/write.

This is a modular rewrite of Ed Reel's
[uberhacker/chromebrew-scripts](https://github.com/uberhacker/chromebrew-scripts).
Every command and flag from the original still works; see *What changed*.

## WARNING

If used improperly, these scripts can render your system useless. Proceed with
caution and do not execute unless you know what you're doing. Review the
*References* section to understand the impact of the changes. As true of any
open source software, nobody is responsible if you brick your system.

Use `--dry-run` first: it prints every command that would run and touches nothing.

## Installation

```
git clone https://github.com/bradvrudney/chromebrew-scripts
cd chromebrew-scripts
./install.sh                 # -> /usr/local/share/chromebrew-scripts + /usr/local/bin/{chromebrew,powerwash,rootfs,rw}
./install.sh --prefix ~/.local
./install.sh --update        # fetch the latest tarball and reinstall
./install.sh --uninstall
```

`install.sh` uses `sudo` only when the prefix is not writable. The self-update
source is configurable: `CBS_REPO=uberhacker/chromebrew-scripts CBS_REF=master ./install.sh --update`
(or set `CBS_TARBALL_URL` to any tarball).

Running the scripts straight from the checkout (`./bin/powerwash`) works too;
the entry points find `lib/` through their own real path, symlinks included.

## Usage

```
chromebrew -i | --install     download and run the Chromebrew installer (yes | bash install.sh)
chromebrew -r | --remove      remove Chromebrew: clears /usr/local/* and strips ~/.bashrc
chromebrew -u | --update      crew update; yes | crew upgrade
chromebrew -s | --status      crew present? version, prefix, Chrome OS detected?
powerwash [--no-reboot]       reset to factory settings (echo clobber > /mnt/stateful_partition/.update_available; reboot)
rootfs [--no-reboot] [-- make_dev_ssd.sh args]
                              sudo make_dev_ssd.sh --remove_rootfs_verification; reboot only if it succeeded
rw                            mount -o remount,rw / ; remount,exec /mnt/stateful_partition and /home/chronos/user
```

Every command accepts:

| flag | effect |
| --- | --- |
| `-h`, `--help` | usage |
| `-y`, `--yes` | answer the `[y/N]` confirmation; required when stdin is not a terminal |
| `-n`, `--dry-run` | print the commands instead of running them |
| `--version` | print the version |

Destructive commands (`powerwash`, `rootfs`, `rw`, `chromebrew --remove`) ask
for confirmation and accept only a real `y`/`Y`. Without a terminal on stdin
they refuse unless `--yes` is given. Recent Chrome OS builds want the kernel
partition for `make_dev_ssd.sh`: `rootfs -- --partitions 2`.

### chromebrew --remove

Follows the Chromebrew wiki: `~/.bashrc` is copied to
`~/.bashrc.chromebrew-scripts.<timestamp>.bak`, then the `source ... profile`,
`# DO NOT DELETE THIS LINE` and `# See ... profile for further details` lines
are removed, then everything under `/usr/local/*` is deleted **except** this
toolkit (`/usr/local/share/chromebrew-scripts` and the symlinks in
`/usr/local/bin` that point into it), so the commands keep working afterwards.

## Environment variables

| variable | default | purpose |
| --- | --- | --- |
| `CBS_ROOT` | (empty) | prefix for every filesystem root below (sandboxing/tests) |
| `CBS_LSB_RELEASE` | `$CBS_ROOT/etc/lsb-release` | where Chrome OS is detected (`CHROMEOS_RELEASE_NAME=`) |
| `CBS_STATEFUL` | `$CBS_ROOT/mnt/stateful_partition` | stateful partition |
| `CBS_PREFIX` | `$CBS_ROOT/usr/local` | Chromebrew prefix (`CREW_PREFIX`) |
| `CBS_VBOOT_BIN` | `$CBS_ROOT/usr/share/vboot/bin` | directory of `make_dev_ssd.sh` |
| `CBS_HOME` | `$HOME` | home whose `.bashrc` is edited |
| `CBS_USER_HOME` | `$CBS_ROOT/home/chronos/user` | user home mount |
| `CBS_ROOTFS_MOUNT` | `/` (or `$CBS_ROOT`) | root filesystem mount point |
| `CBS_ASSUME_CHROMEOS` | `0` | `1` skips the Chrome OS check (tests/CI only) |
| `CBS_SUDO` | `sudo` | privilege escalation command |
| `CBS_CREW_INSTALLER_URL` | `https://raw.githubusercontent.com/chromebrew/chromebrew/master/install.sh` | installer fetched by `chromebrew -i` |
| `CBS_CREW_TIMEOUT` | `3600` | seconds allowed per `crew` command / installer run |
| `CBS_CURL_TIMEOUT` | `300` | seconds allowed for downloads |
| `CBS_REPO`, `CBS_REF`, `CBS_TARBALL_URL` | `bradvrudney/chromebrew-scripts`, `master` | source of `install.sh --update` |
| `NO_COLOR` | unset | disable colored output (also off when stderr is not a terminal) |

Every command refuses to run on anything that is not Chrome OS unless
`CBS_ASSUME_CHROMEOS=1` is set (`--help`, `--version` and `chromebrew --status`
work anywhere).

## Layout

```
bin/        thin entry points (resolve their real path, source lib/, call cbs_main)
lib/        common.sh (output, confirm, run/dry-run, sudo, timeouts, Chrome OS detection, options)
            cmd_<command>.sh - one module per command (cmd_usage + cbs_main)
install.sh  install / --uninstall / --update
test/       bats suite, test_helper.bash and stubs/ (sudo, crew, curl, mount, reboot, make_dev_ssd.sh)
scripts/check.sh, Makefile   lint + tests
```

## Testing

```
make lint     # shellcheck -x over bin/, lib/, install.sh, scripts and stubs
make test     # bats test/
make check    # both (same as scripts/check.sh)
```

The tests never touch the real system: every path goes through `CBS_ROOT`
into a temporary sandbox, `CBS_ASSUME_CHROMEOS=1` is set, and `sudo`, `crew`,
`curl`, `mount`, `reboot` and `make_dev_ssd.sh` are stubs on `PATH` that log
their calls.

CI (`.github/workflows/ci.yml`) runs shellcheck, the bats suite, and an
install smoke test in `debian:stable-slim` and `alpine:3` containers that runs
`install.sh` into a temporary prefix and every command with `--help` and
`--dry-run --yes`. **Real Chrome OS cannot be tested in CI**: nothing there
exercises `make_dev_ssd.sh`, the powerwash marker, the remounts or the
Chromebrew installer for real. Test on a device you can afford to powerwash.

## What changed from the original scripts

- `chromebrew -i` downloads from `raw.githubusercontent.com/chromebrew/chromebrew`
  (the `git.io/vddgY` short link is dead), into a temporary directory with
  `curl --fail` and a timeout, and refuses to run as root (the installer does too).
- `chromebrew -r` no longer runs `sudo dev_install --reinstall` (gone from
  modern Chrome OS); it follows the wiki removal method described above.
- `chromebrew -u` wraps both crew commands in `timeout`.
- `powerwash` only reboots if the clobber marker was written; `rootfs` only
  reboots if `make_dev_ssd.sh` succeeded. Both have `--no-reboot`.
- `rw` exits non-zero when a remount fails (it used to print a message and exit 0).

## References

- https://github.com/chromebrew/chromebrew
- https://github.com/chromebrew/chromebrew/wiki/How-to-remove-chromebrew
- https://support.google.com/chromebook/answer/183084?hl=en
- https://neverware.zendesk.com/hc/en-us/articles/115000765287--Powerwash-via-the-cmd-line
- https://www.chromium.org/chromium-os/poking-around-your-chrome-os-device#TOC-Making-changes-to-the-filesystem
- https://sites.google.com/site/cr48ite/getting-technical/remove-rootfs-verification-make-read-write

## License

LGPL-3.0, see `LICENSE`.
