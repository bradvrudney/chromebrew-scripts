# lib/common.sh - shared helpers for chromebrew-scripts
#
# Sourced by every command module. Expects CBS_LIB_DIR to point at this
# directory (the bin/ entry points set it after resolving their real path).
#
# Environment knobs (all optional):
#   CBS_ROOT              prefix prepended to every filesystem root below
#   CBS_LSB_RELEASE       path of /etc/lsb-release
#   CBS_STATEFUL          path of /mnt/stateful_partition
#   CBS_PREFIX            Chromebrew prefix (CREW_PREFIX), default /usr/local
#   CBS_VBOOT_BIN         directory holding make_dev_ssd.sh
#   CBS_HOME              home directory whose .bashrc Chromebrew edits
#   CBS_USER_HOME         /home/chronos/user mount point
#   CBS_ROOTFS_MOUNT      mount point of the root filesystem
#   CBS_ASSUME_CHROMEOS   1 = skip the ChromeOS detection
#   CBS_SUDO              privilege-escalation command (default: sudo)
#   CBS_YES / CBS_DRY_RUN set by --yes / --dry-run
#   NO_COLOR              disable colored output
# shellcheck shell=bash

if [[ -n "${CBS_COMMON_LOADED:-}" ]]; then
  return 0
fi
CBS_COMMON_LOADED=1

CBS_LIB_DIR="${CBS_LIB_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)}"
CBS_ROOT_DIR="${CBS_ROOT_DIR:-$(cd "${CBS_LIB_DIR}/.." && pwd -P)}"
CBS_CMD_NAME="${CBS_CMD_NAME:-$(basename "$0")}"

if [[ -r "${CBS_ROOT_DIR}/VERSION" ]]; then
  read -r CBS_VERSION < "${CBS_ROOT_DIR}/VERSION"
else
  CBS_VERSION="dev"
fi

# ---------------------------------------------------------------- roots ----
CBS_ROOT="${CBS_ROOT:-}"
CBS_LSB_RELEASE="${CBS_LSB_RELEASE:-${CBS_ROOT}/etc/lsb-release}"
CBS_STATEFUL="${CBS_STATEFUL:-${CBS_ROOT}/mnt/stateful_partition}"
CBS_PREFIX="${CBS_PREFIX:-${CBS_ROOT}/usr/local}"
CBS_VBOOT_BIN="${CBS_VBOOT_BIN:-${CBS_ROOT}/usr/share/vboot/bin}"
CBS_HOME="${CBS_HOME:-${HOME:-/home/chronos/user}}"
CBS_USER_HOME="${CBS_USER_HOME:-${CBS_ROOT}/home/chronos/user}"
CBS_ROOTFS_MOUNT="${CBS_ROOTFS_MOUNT:-${CBS_ROOT:-/}}"
CBS_SUDO="${CBS_SUDO:-sudo}"
CBS_YES="${CBS_YES:-0}"
CBS_DRY_RUN="${CBS_DRY_RUN:-0}"

# --------------------------------------------------------------- output ----
if [[ -n "${NO_COLOR:-}" || ! -t 2 ]]; then
  C_RED='' C_YEL='' C_GRN='' C_BLU='' C_RST=''
else
  C_RED=$'\e[1;31m' C_YEL=$'\e[1;33m' C_GRN=$'\e[1;32m' C_BLU=$'\e[1;34m' C_RST=$'\e[0m'
fi

log()  { printf '%s%s%s\n' "${C_GRN}" "$*" "${C_RST}" >&2; }
warn() { printf '%sWARNING: %s%s\n' "${C_YEL}" "$*" "${C_RST}" >&2; }
# die [CODE] MESSAGE... - print an error and exit (default code 1)
die() {
  local code=1
  if [[ $# -gt 1 && "$1" =~ ^[0-9]+$ ]]; then
    code="$1"
    shift
  fi
  printf '%sERROR: %s%s\n' "${C_RED}" "$*" "${C_RST}" >&2
  exit "${code}"
}

# cbs_quote ARGS... - print a command line, quoting only what needs it
cbs_quote() {
  local arg out=''
  for arg in "$@"; do
    if [[ "${arg}" =~ ^[A-Za-z0-9_./=:,+@%-]+$ ]]; then
      out+="${arg} "
    else
      out+="$(printf '%q' "${arg}") "
    fi
  done
  printf '%s' "${out% }"
}

# ------------------------------------------------------------- dry-run -----
cbs_dry_run() { [[ "${CBS_DRY_RUN}" == 1 ]]; }

# dry_print TEXT - what --dry-run prints instead of executing
dry_print() { printf '%s[dry-run]%s %s\n' "${C_BLU}" "${C_RST}" "$*"; }

# run CMD ARGS... - execute, or print the command when --dry-run is active
run() {
  if cbs_dry_run; then
    dry_print "$(cbs_quote "$@")"
    return 0
  fi
  "$@"
}

# run_pipe DESCRIPTION FUNC ARGS... - like run, for shell pipelines wrapped
# in a function. DESCRIPTION is what --dry-run prints.
run_pipe() {
  local desc="$1"
  shift
  if cbs_dry_run; then
    dry_print "${desc}"
    return 0
  fi
  "$@"
}

# cbs_sudo ARGS... - run a command through CBS_SUDO (honors --dry-run)
cbs_sudo() { run "${CBS_SUDO}" "$@"; }

# cbs_timeout SECONDS CMD ARGS... - run with a bounded wall-clock time
cbs_timeout() {
  local secs="$1"
  shift
  if command -v timeout >/dev/null 2>&1; then
    run timeout "${secs}" "$@"
  else
    run "$@"
  fi
}

# cbs_yes_pipe CMD ARGS... - feed an endless stream of "y" to CMD and return
# CMD's exit status (yes dying of SIGPIPE must not trip pipefail).
cbs_yes_pipe() {
  local status=0
  { yes 2>/dev/null || true; } | "$@" || status=$?
  return "${status}"
}

# ------------------------------------------------------------- confirm -----
# confirm QUESTION - ask "WARNING!  QUESTION [y/N]: ". Returns 0 only for a
# real y/Y. With --yes it is answered automatically; without --yes and
# without a terminal on stdin it refuses rather than guessing.
confirm() {
  local question="$1" reply=''
  if [[ "${CBS_YES}" == 1 ]]; then
    log "Confirmed by --yes: ${question}"
    return 0
  fi
  if [[ ! -t 0 ]]; then
    die "Refusing to continue: stdin is not a terminal and --yes was not given (${question})"
  fi
  printf '%sWARNING!  %s [y/N]: %s' "${C_YEL}" "${question}" "${C_RST}" >&2
  read -r -n1 reply || true
  printf '\n' >&2
  case "${reply}" in
    y|Y) return 0 ;;
    *)
      log "Aborted."
      return 1
      ;;
  esac
}

# ------------------------------------------------------------ ChromeOS -----
cbs_is_chromeos() {
  if [[ "${CBS_ASSUME_CHROMEOS:-0}" == 1 ]]; then
    return 0
  fi
  [[ -r "${CBS_LSB_RELEASE}" ]] && grep -q '^CHROMEOS_RELEASE_NAME=' "${CBS_LSB_RELEASE}"
}

cbs_require_chromeos() {
  cbs_is_chromeos || die "This command only runs on Chrome OS / Chromium OS" \
    "(no CHROMEOS_RELEASE_NAME in ${CBS_LSB_RELEASE}). Set CBS_ASSUME_CHROMEOS=1 to override."
}

cbs_require_not_root() {
  if [[ "${EUID}" -eq 0 ]]; then
    die "$1"
  fi
}

# ------------------------------------------------------------- options -----
# cbs_global_flag FLAG - handle -h/--help, -y/--yes, -n/--dry-run, --version.
# Returns 0 when FLAG was consumed, 1 otherwise. Modules define cmd_usage.
cbs_global_flag() {
  case "$1" in
    -h|--help)
      cmd_usage
      exit 0
      ;;
    -y|--yes) CBS_YES=1 ;;
    -n|--dry-run) CBS_DRY_RUN=1 ;;
    --version)
      printf '%s %s\n' "${CBS_CMD_NAME}" "${CBS_VERSION}"
      exit 0
      ;;
    *) return 1 ;;
  esac
}

# cbs_usage_footer - the flags every command shares
cbs_usage_footer() {
  cat <<EOF
Common options:
  -h, --help       show this help and exit
  -y, --yes        answer yes to the confirmation (required when stdin is not a terminal)
  -n, --dry-run    print the commands that would run instead of running them
      --version    print the version and exit

Environment:
  CBS_ASSUME_CHROMEOS=1  skip the Chrome OS detection (testing only)
  CBS_ROOT=DIR           relocate every filesystem root under DIR (testing only)
  NO_COLOR=1             disable colored output
EOF
}

cbs_usage_error() {
  printf '%s\n' "$*" >&2
  cmd_usage >&2
  exit 2
}
