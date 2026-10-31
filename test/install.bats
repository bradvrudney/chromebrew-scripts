#!/usr/bin/env bats
# install.sh: install, uninstall and self-update into a temporary prefix

load test_helper

setup() {
  setup_sandbox
  PREFIX_DIR="${BATS_TEST_TMPDIR}/prefix"
}

@test "install.sh --help" {
  run bash "${REPO_ROOT}/install.sh" --help
  [ "$status" -eq 0 ]
  assert_output_contains "--uninstall"
  assert_output_contains "--update"
}

@test "install.sh installs into a prefix and the symlinked commands work" {
  run bash "${REPO_ROOT}/install.sh" --prefix "${PREFIX_DIR}"
  [ "$status" -eq 0 ]
  [ -f "${PREFIX_DIR}/share/chromebrew-scripts/lib/common.sh" ]
  [ -f "${PREFIX_DIR}/share/chromebrew-scripts/VERSION" ]
  [ -x "${PREFIX_DIR}/share/chromebrew-scripts/install.sh" ]
  for cmd in chromebrew powerwash rootfs rw; do
    [ -L "${PREFIX_DIR}/bin/${cmd}" ]
    run "${PREFIX_DIR}/bin/${cmd}" --version
    [ "$status" -eq 0 ]
    [ "$output" = "${cmd} $(cat "${REPO_ROOT}/VERSION")" ]
  done
  run "${PREFIX_DIR}/bin/powerwash" --dry-run --yes
  [ "$status" -eq 0 ]
  assert_output_contains "[dry-run] sudo reboot"
  assert_not_called "sudo"
}

@test "install.sh --uninstall removes its links and share dir only" {
  bash "${REPO_ROOT}/install.sh" --prefix "${PREFIX_DIR}" >/dev/null
  touch "${PREFIX_DIR}/bin/other"
  run bash "${REPO_ROOT}/install.sh" --prefix "${PREFIX_DIR}" --uninstall
  [ "$status" -eq 0 ]
  [ ! -e "${PREFIX_DIR}/share/chromebrew-scripts" ]
  [ ! -e "${PREFIX_DIR}/bin/chromebrew" ]
  [ -e "${PREFIX_DIR}/bin/other" ]
}

@test "install.sh --update fetches the tarball for CBS_REPO/CBS_REF and reinstalls" {
  bash "${REPO_ROOT}/install.sh" --prefix "${PREFIX_DIR}" >/dev/null
  rm "${PREFIX_DIR}/bin/rw"
  CBS_REPO=uberhacker/chromebrew-scripts CBS_REF=main \
    run bash "${PREFIX_DIR}/share/chromebrew-scripts/install.sh" --prefix "${PREFIX_DIR}" --update
  [ "$status" -eq 0 ]
  assert_called "https://github.com/uberhacker/chromebrew-scripts/archive/main.tar.gz"
  [ -L "${PREFIX_DIR}/bin/rw" ]
  run "${PREFIX_DIR}/bin/rw" --version
  [ "$status" -eq 0 ]
}
