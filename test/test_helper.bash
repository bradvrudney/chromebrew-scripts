# test/test_helper.bash - shared bats setup
# shellcheck shell=bash

REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
export REPO_ROOT

# setup_sandbox - a fake filesystem under $SANDBOX, stubs on PATH, a call log
setup_sandbox() {
  SANDBOX="${BATS_TEST_TMPDIR}/root"
  export SANDBOX
  mkdir -p "${SANDBOX}/etc" "${SANDBOX}/mnt/stateful_partition" "${SANDBOX}/usr/local" \
    "${SANDBOX}/usr/share/vboot/bin" "${SANDBOX}/home/chronos/user"
  export CBS_ROOT="${SANDBOX}"
  export CBS_HOME="${BATS_TEST_TMPDIR}/home"
  mkdir -p "${CBS_HOME}"
  export CBS_ASSUME_CHROMEOS=1
  export NO_COLOR=1
  export STUB_LOG="${BATS_TEST_TMPDIR}/calls.log"
  : > "${STUB_LOG}"
  export PATH="${REPO_ROOT}/test/stubs:${PATH}"
  cp -L "${REPO_ROOT}/test/stubs/make_dev_ssd.sh" "${SANDBOX}/usr/share/vboot/bin/make_dev_ssd.sh"
  unset CBS_YES CBS_DRY_RUN CBS_LSB_RELEASE CBS_STATEFUL CBS_PREFIX CBS_VBOOT_BIN
}

# write_lsb_release [NAME] - make the sandbox look like Chrome OS
write_lsb_release() {
  printf 'CHROMEOS_RELEASE_NAME=%s\nCHROMEOS_RELEASE_TRACK=stable-channel\n' "${1:-Chrome OS}" \
    > "${SANDBOX}/etc/lsb-release"
}

calls() { cat "${STUB_LOG}"; }

assert_called() {
  grep -qF -- "$1" "${STUB_LOG}" || {
    echo "expected a call matching: $1"
    echo "calls were:"
    cat "${STUB_LOG}"
    return 1
  }
}

assert_not_called() {
  if grep -qF -- "$1" "${STUB_LOG}"; then
    echo "did not expect a call matching: $1"
    echo "calls were:"
    cat "${STUB_LOG}"
    return 1
  fi
}

assert_output_contains() {
  # shellcheck disable=SC2154  # $output is set by bats' run
  [[ "${output}" == *"$1"* ]] || {
    echo "expected output to contain: $1"
    echo "output was:"
    echo "${output}"
    return 1
  }
}
