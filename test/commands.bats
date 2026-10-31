#!/usr/bin/env bats
# Entry points: powerwash, rootfs, rw (and the shared option handling).

load test_helper

setup() { setup_sandbox; }

# ------------------------------------------------------------ shared ------
@test "every command answers --help without needing Chrome OS" {
  unset CBS_ASSUME_CHROMEOS
  for cmd in chromebrew powerwash rootfs rw; do
    run "${REPO_ROOT}/bin/${cmd}" --help
    [ "$status" -eq 0 ]
    assert_output_contains "Usage: ${cmd}"
    assert_output_contains "--dry-run"
  done
}

@test "every command answers --version" {
  for cmd in chromebrew powerwash rootfs rw; do
    run "${REPO_ROOT}/bin/${cmd}" --version
    [ "$status" -eq 0 ]
    [ "$output" = "${cmd} $(cat "${REPO_ROOT}/VERSION")" ]
  done
}

@test "unknown options exit 2 with usage" {
  run "${REPO_ROOT}/bin/rw" --bogus
  [ "$status" -eq 2 ]
  assert_output_contains "Unknown option: --bogus"
  assert_output_contains "Usage: rw"
}

@test "commands refuse to run off Chrome OS" {
  unset CBS_ASSUME_CHROMEOS
  for cmd in powerwash rootfs rw; do
    run "${REPO_ROOT}/bin/${cmd}" --yes
    [ "$status" -eq 1 ]
    assert_output_contains "only runs on Chrome OS"
  done
  run "${REPO_ROOT}/bin/chromebrew" --update --yes
  [ "$status" -eq 1 ]
  assert_output_contains "only runs on Chrome OS"
  [ -z "$(calls)" ]
}

@test "commands run when /etc/lsb-release names Chrome OS" {
  unset CBS_ASSUME_CHROMEOS
  write_lsb_release
  run "${REPO_ROOT}/bin/rw" --yes
  [ "$status" -eq 0 ]
  assert_called "mount -o remount,rw"
}

@test "confirmation refuses on non-tty stdin without --yes" {
  for cmd in powerwash rootfs rw; do
    run "${REPO_ROOT}/bin/${cmd}" </dev/null
    [ "$status" -eq 1 ]
    assert_output_contains "stdin is not a terminal"
  done
  [ -z "$(calls)" ]
  [ ! -e "${SANDBOX}/mnt/stateful_partition/.update_available" ]
}

@test "confirmation accepts a real y and rejects anything else on a tty" {
  command -v script >/dev/null || skip "script(1) not available"
  # script(1) gives the command a pty and forwards our stdin into it
  run bash -c "(printf n; sleep 1) | script -qec '${REPO_ROOT}/bin/rw' /dev/null"
  assert_output_contains "Aborted"
  assert_not_called "mount"
  run bash -c "(printf y; sleep 1) | script -qec '${REPO_ROOT}/bin/rw' /dev/null"
  assert_called "mount -o remount,rw"
}

@test "--dry-run prints commands and changes nothing" {
  run "${REPO_ROOT}/bin/powerwash" --dry-run --yes
  [ "$status" -eq 0 ]
  assert_output_contains "[dry-run] echo clobber | sudo tee ${SANDBOX}/mnt/stateful_partition/.update_available"
  assert_output_contains "[dry-run] sudo reboot"
  [ ! -e "${SANDBOX}/mnt/stateful_partition/.update_available" ]
  [ -z "$(calls)" ]
}

# --------------------------------------------------------- powerwash ------
@test "powerwash writes clobber and reboots" {
  run "${REPO_ROOT}/bin/powerwash" -y
  [ "$status" -eq 0 ]
  [ "$(cat "${SANDBOX}/mnt/stateful_partition/.update_available")" = "clobber" ]
  assert_called "sudo tee ${SANDBOX}/mnt/stateful_partition/.update_available"
  assert_called "sudo reboot"
}

@test "powerwash --no-reboot only schedules" {
  run "${REPO_ROOT}/bin/powerwash" --yes --no-reboot
  [ "$status" -eq 0 ]
  [ -e "${SANDBOX}/mnt/stateful_partition/.update_available" ]
  assert_not_called "reboot"
}

@test "powerwash does not reboot when the marker cannot be written" {
  export STUB_EXIT_sudo=1
  run "${REPO_ROOT}/bin/powerwash" --yes
  [ "$status" -eq 1 ]
  assert_output_contains "not rebooting"
  assert_not_called "sudo reboot"
}

# ------------------------------------------------------------ rootfs ------
@test "rootfs runs make_dev_ssd.sh and reboots on success" {
  run "${REPO_ROOT}/bin/rootfs" --yes
  [ "$status" -eq 0 ]
  assert_called "sudo ${SANDBOX}/usr/share/vboot/bin/make_dev_ssd.sh --remove_rootfs_verification"
  assert_called "make_dev_ssd.sh --remove_rootfs_verification"
  assert_called "sudo reboot"
}

@test "rootfs does not reboot when make_dev_ssd.sh fails" {
  export STUB_EXIT_make_dev_ssd_sh=3
  run "${REPO_ROOT}/bin/rootfs" --yes
  [ "$status" -eq 1 ]
  assert_output_contains "make_dev_ssd.sh failed; not rebooting"
  assert_called "make_dev_ssd.sh --remove_rootfs_verification"
  assert_not_called "reboot"
}

@test "rootfs --no-reboot and extra args after --" {
  run "${REPO_ROOT}/bin/rootfs" --yes --no-reboot -- --partitions 2
  [ "$status" -eq 0 ]
  assert_called "make_dev_ssd.sh --remove_rootfs_verification --partitions 2"
  assert_not_called "reboot"
}

@test "rootfs dry-run" {
  run "${REPO_ROOT}/bin/rootfs" -n -y -- --partitions 4
  [ "$status" -eq 0 ]
  assert_output_contains "[dry-run] sudo ${SANDBOX}/usr/share/vboot/bin/make_dev_ssd.sh --remove_rootfs_verification --partitions 4"
  assert_output_contains "[dry-run] sudo reboot"
  [ -z "$(calls)" ]
}

# ---------------------------------------------------------------- rw ------
@test "rw remounts root, stateful and the user home" {
  run "${REPO_ROOT}/bin/rw" --yes
  [ "$status" -eq 0 ]
  assert_called "sudo mount -o remount,rw ${SANDBOX}"
  assert_called "sudo mount -o remount,exec ${SANDBOX}/mnt/stateful_partition"
  assert_called "sudo mount -i -o remount,exec ${SANDBOX}/home/chronos/user"
  assert_output_contains "full read/write access"
}

@test "rw stops at the first failing mount" {
  export STUB_EXIT_mount=32
  run "${REPO_ROOT}/bin/rw" --yes
  [ "$status" -eq 1 ]
  assert_output_contains "There were no filesystem changes"
  [ "$(grep -c '^mount' "${STUB_LOG}")" -eq 1 ]
}

@test "rw dry-run" {
  run "${REPO_ROOT}/bin/rw" --dry-run --yes
  [ "$status" -eq 0 ]
  assert_output_contains "[dry-run] sudo mount -o remount,rw ${SANDBOX}"
  [ -z "$(calls)" ]
}
