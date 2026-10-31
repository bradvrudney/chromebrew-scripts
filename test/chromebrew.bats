#!/usr/bin/env bats
# chromebrew: install / remove / update / status

load test_helper

setup() {
  setup_sandbox
  PREFIX_DIR="${SANDBOX}/usr/local"
  # PATH without the crew stub: "crew" is present only when a test adds it
  export PATH_NO_CREW="${BATS_TEST_TMPDIR}/nocrew"
  mkdir -p "${PATH_NO_CREW}"
  for s in sudo curl reboot mount; do ln -s "${REPO_ROOT}/test/stubs/${s}" "${PATH_NO_CREW}/${s}"; done
}

without_crew() {
  export PATH="${PATH_NO_CREW}:$(printf '%s' "${PATH}" | sed "s#${REPO_ROOT}/test/stubs:##")"
}

# install the toolkit into the sandbox prefix next to a fake Chromebrew
install_toolkit_and_fake_crew() {
  bash "${REPO_ROOT}/install.sh" --prefix "${PREFIX_DIR}" >/dev/null
  mkdir -p "${PREFIX_DIR}/lib/crew" "${PREFIX_DIR}/etc/env.d" "${PREFIX_DIR}/share/doc"
  cp "${REPO_ROOT}/test/stubs/crew" "${PREFIX_DIR}/bin/crew"
  touch "${PREFIX_DIR}/lib/crew/packages.rb" "${PREFIX_DIR}/etc/env.d/01-core" "${PREFIX_DIR}/share/doc/README"
}

@test "no action prints the legacy usage line and exits 2" {
  run "${REPO_ROOT}/bin/chromebrew"
  [ "$status" -eq 2 ]
  assert_output_contains "chromebrew -i | --install | -r | --remove | -u | --update"
}

@test "two actions are rejected" {
  run "${REPO_ROOT}/bin/chromebrew" -i -u
  [ "$status" -eq 2 ]
  assert_output_contains "exactly one action"
}

@test "legacy flags -u and --update run crew update then yes | crew upgrade" {
  for flag in -u --update; do
    : > "${STUB_LOG}"
    run "${REPO_ROOT}/bin/chromebrew" "${flag}"
    [ "$status" -eq 0 ]
    [ "$(calls)" = $'crew update\ncrew upgrade' ]
  done
}

@test "update uses the crew timeout" {
  CBS_CREW_TIMEOUT=7 run "${REPO_ROOT}/bin/chromebrew" --update --dry-run
  [ "$status" -eq 0 ]
  assert_output_contains "[dry-run] timeout 7 crew update"
  assert_output_contains "[dry-run] yes | timeout 7 crew upgrade"
  [ -z "$(calls)" ]
}

@test "update fails when crew update fails and skips upgrade" {
  export STUB_EXIT_crew=1
  run "${REPO_ROOT}/bin/chromebrew" -u
  [ "$status" -eq 1 ]
  assert_output_contains "crew update failed"
  assert_not_called "crew upgrade"
}

@test "update refuses when crew is not installed" {
  without_crew
  run "${REPO_ROOT}/bin/chromebrew" -u
  [ "$status" -eq 1 ]
  assert_output_contains "chromebrew is not installed"
}

@test "install refuses when crew is already installed" {
  run "${REPO_ROOT}/bin/chromebrew" -i
  [ "$status" -eq 1 ]
  assert_output_contains "chromebrew is currently installed"
  assert_not_called "curl"
}

@test "install refuses to run as root" {
  [ "$(id -u)" -eq 0 ] || skip "not running as root"
  without_crew
  run "${REPO_ROOT}/bin/chromebrew" --install
  [ "$status" -eq 1 ]
  assert_output_contains "must not be installed as root"
  assert_not_called "curl"
}

@test "install downloads the installer with curl --fail and runs it with yes" {
  without_crew
  if [ "$(id -u)" -eq 0 ]; then
    command -v setpriv >/dev/null || skip "setpriv not available"
    chmod -R a+rwX "${BATS_TEST_TMPDIR}" "${BATS_RUN_TMPDIR}" 2>/dev/null || true
    setpriv --reuid=65534 --regid=65534 --clear-groups true 2>/dev/null || skip "cannot drop privileges"
    run setpriv --reuid=65534 --regid=65534 --clear-groups \
      env HOME="${CBS_HOME}" TMPDIR="${BATS_TEST_TMPDIR}" "${REPO_ROOT}/bin/chromebrew" --install
  else
    run "${REPO_ROOT}/bin/chromebrew" --install
  fi
  [ "$status" -eq 0 ]
  assert_called "curl --fail --location --silent --show-error --max-time 300 -o"
  assert_called "https://raw.githubusercontent.com/chromebrew/chromebrew/master/install.sh"
  assert_called "installer euid=65534 answer=y"
}

@test "install honors CBS_CREW_INSTALLER_URL and shows the plan in dry-run" {
  without_crew
  if [ "$(id -u)" -eq 0 ]; then
    command -v setpriv >/dev/null || skip "setpriv not available"
    chmod -R a+rwX "${BATS_TEST_TMPDIR}" "${BATS_RUN_TMPDIR}" 2>/dev/null || true
    setpriv --reuid=65534 --regid=65534 --clear-groups true 2>/dev/null || skip "cannot drop privileges"
    run setpriv --reuid=65534 --regid=65534 --clear-groups \
      env HOME="${CBS_HOME}" TMPDIR="${BATS_TEST_TMPDIR}" CBS_CREW_INSTALLER_URL=https://example.test/i.sh \
      "${REPO_ROOT}/bin/chromebrew" -i -n
  else
    CBS_CREW_INSTALLER_URL=https://example.test/i.sh run "${REPO_ROOT}/bin/chromebrew" -i -n
  fi
  [ "$status" -eq 0 ]
  assert_output_contains "[dry-run] curl --fail --location --silent --show-error --max-time 300 -o"
  assert_output_contains "https://example.test/i.sh"
  assert_output_contains "[dry-run] yes | timeout 3600 bash"
  [ -z "$(calls)" ]
}

@test "remove needs confirmation" {
  install_toolkit_and_fake_crew
  run "${PREFIX_DIR}/bin/chromebrew" -r </dev/null
  [ "$status" -eq 1 ]
  assert_output_contains "stdin is not a terminal"
  [ -e "${PREFIX_DIR}/lib/crew/packages.rb" ]
}

@test "remove clears the prefix but keeps the toolkit, and backs up .bashrc" {
  install_toolkit_and_fake_crew
  printf 'export FOO=bar\n# DO NOT DELETE THIS LINE\nsource /usr/local/etc/profile\n# See /usr/local/etc/profile for further details\nalias ll="ls -l"\n' \
    > "${CBS_HOME}/.bashrc"
  export CBS_PREFIX="${PREFIX_DIR}"
  run "${PREFIX_DIR}/bin/chromebrew" --remove --yes
  [ "$status" -eq 0 ]
  # Chromebrew is gone
  [ ! -e "${PREFIX_DIR}/bin/crew" ]
  [ ! -e "${PREFIX_DIR}/lib" ]
  [ ! -e "${PREFIX_DIR}/etc" ]
  [ ! -e "${PREFIX_DIR}/share/doc" ]
  assert_called "sudo rm -rf ${PREFIX_DIR}/lib"
  # the toolkit and its symlinks survive
  [ -f "${PREFIX_DIR}/share/chromebrew-scripts/lib/common.sh" ]
  for cmd in chromebrew powerwash rootfs rw; do
    [ -L "${PREFIX_DIR}/bin/${cmd}" ]
    run "${PREFIX_DIR}/bin/${cmd}" --version
    [ "$status" -eq 0 ]
  done
  # .bashrc was backed up and stripped, not truncated
  backup="$(ls "${CBS_HOME}"/.bashrc.chromebrew-scripts.*.bak)"
  [ -f "${backup}" ]
  grep -q 'DO NOT DELETE' "${backup}"
  [ "$(cat "${CBS_HOME}/.bashrc")" = $'export FOO=bar\nalias ll="ls -l"' ]
}

@test "remove refuses an unsafe prefix" {
  install_toolkit_and_fake_crew
  for bad in / /usr /home relative/path "${BATS_TEST_TMPDIR}/missing"; do
    CBS_PREFIX="${bad}" run "${PREFIX_DIR}/bin/chromebrew" --remove --yes
    [ "$status" -ne 0 ]
    assert_output_contains "Refusing to clear"
  done
  [ -e "${PREFIX_DIR}/lib/crew/packages.rb" ]
  [ -z "$(calls)" ]
}

@test "remove dry-run touches nothing" {
  install_toolkit_and_fake_crew
  printf 'source /usr/local/etc/profile\n' > "${CBS_HOME}/.bashrc"
  export CBS_PREFIX="${PREFIX_DIR}"
  run "${PREFIX_DIR}/bin/chromebrew" -r -y -n
  [ "$status" -eq 0 ]
  assert_output_contains "[dry-run] sudo rm -rf ${PREFIX_DIR}/lib"
  assert_output_contains "[dry-run] cp -p ${CBS_HOME}/.bashrc"
  [ -e "${PREFIX_DIR}/lib/crew/packages.rb" ]
  [ "$(cat "${CBS_HOME}/.bashrc")" = "source /usr/local/etc/profile" ]
  [ -z "$(calls)" ]
}

@test "status reports crew and the prefix" {
  run "${REPO_ROOT}/bin/chromebrew" --status
  [ "$status" -eq 0 ]
  assert_output_contains "crew version:        1.59.0"
  assert_output_contains "Chromebrew prefix:   ${PREFIX_DIR}"
  without_crew
  run "${REPO_ROOT}/bin/chromebrew" -s
  [ "$status" -eq 0 ]
  assert_output_contains "crew:                not installed"
}
