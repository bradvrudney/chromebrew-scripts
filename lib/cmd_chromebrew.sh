# lib/cmd_chromebrew.sh - install, remove, update or inspect Chromebrew
# References:
#   https://github.com/chromebrew/chromebrew
#   https://github.com/chromebrew/chromebrew/wiki/How-to-remove-chromebrew
# shellcheck shell=bash

CBS_CREW_INSTALLER_URL="${CBS_CREW_INSTALLER_URL:-https://raw.githubusercontent.com/chromebrew/chromebrew/master/install.sh}"
CBS_CREW_TIMEOUT="${CBS_CREW_TIMEOUT:-3600}"
CBS_CURL_TIMEOUT="${CBS_CURL_TIMEOUT:-300}"

cmd_usage() {
  cat <<EOF
Usage: ${CBS_CMD_NAME} ACTION [options]

Actions (exactly one):
  -i, --install    download the Chromebrew installer and run it (yes | bash install.sh)
  -r, --remove     uninstall Chromebrew: clears ${CBS_PREFIX}/* (everything under
                   the Chromebrew prefix except this toolkit) and strips the
                   Chromebrew lines from ${CBS_HOME}/.bashrc after backing it up
  -u, --update     crew update, then yes | crew upgrade
  -s, --status     show whether crew is installed, its version and the prefix

Options:
EOF
  cbs_usage_footer
  cat <<EOF

More environment:
  CBS_CREW_INSTALLER_URL  installer to download (default: ${CBS_CREW_INSTALLER_URL})
  CBS_CREW_TIMEOUT        seconds allowed per crew command (default: ${CBS_CREW_TIMEOUT})
  CBS_CURL_TIMEOUT        seconds allowed for the installer download (default: ${CBS_CURL_TIMEOUT})
  CBS_PREFIX              Chromebrew prefix to clear on --remove (default: ${CBS_PREFIX})
  CREW_FORCE_INSTALL=1    passed through to the Chromebrew installer
EOF
}

# _crew_bin - print the path of crew, or fail when it is not installed
_crew_bin() {
  if command -v crew 2>/dev/null; then
    return 0
  fi
  if [[ -x "${CBS_PREFIX}/bin/crew" ]]; then
    printf '%s\n' "${CBS_PREFIX}/bin/crew"
    return 0
  fi
  return 1
}

_timeout_prefix() {
  if command -v timeout >/dev/null 2>&1; then
    printf 'timeout %s' "${CBS_CREW_TIMEOUT}"
  fi
}

_cb_install() {
  if _crew_bin >/dev/null; then
    die "chromebrew is currently installed."
  fi
  cbs_require_not_root "Chromebrew must not be installed as root. Run '${CBS_CMD_NAME} --install' as the chronos user."

  local tmp installer
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/chromebrew-scripts.XXXXXX")"
  # shellcheck disable=SC2064
  trap "rm -rf '${tmp}'" EXIT
  installer="${tmp}/install.sh"

  log "Downloading ${CBS_CREW_INSTALLER_URL}"
  run curl --fail --location --silent --show-error --max-time "${CBS_CURL_TIMEOUT}" \
    -o "${installer}" "${CBS_CREW_INSTALLER_URL}" || die "Could not download the Chromebrew installer."

  local -a to
  read -r -a to <<<"$(_timeout_prefix)"
  log "Running the Chromebrew installer (answering yes to its prompts)"
  run_pipe "yes | $(cbs_quote "${to[@]}" bash "${installer}")" \
    cbs_yes_pipe "${to[@]}" bash "${installer}" || die "The Chromebrew installer failed."
  log "Chromebrew installed. Run: source ${CBS_HOME}/.bashrc"
}

_cb_update() {
  _crew_bin >/dev/null || die "chromebrew is not installed.  To install, execute '${CBS_CMD_NAME} -i | --install'."
  local -a to
  read -r -a to <<<"$(_timeout_prefix)"
  run "${to[@]}" crew update || die "crew update failed."
  run_pipe "yes | $(cbs_quote "${to[@]}" crew upgrade)" \
    cbs_yes_pipe "${to[@]}" crew upgrade || die "crew upgrade failed."
}

# _cb_is_toolkit_path PATH - PATH (symlinks resolved) is this toolkit or inside it
_cb_is_toolkit_path() {
  local real
  real="$(readlink -f -- "$1" 2>/dev/null)" || return 1
  [[ "${real}" == "${CBS_ROOT_DIR}" || "${real}" == "${CBS_ROOT_DIR}"/* ]]
}

# _cb_shelters_toolkit DIR - DIR is a real directory holding toolkit paths
_cb_shelters_toolkit() {
  local dir="$1" real child
  [[ -d "${dir}" && ! -L "${dir}" ]] || return 1
  real="$(cd -P "${dir}" && pwd)"
  [[ "${CBS_ROOT_DIR}" == "${real}"/* ]] && return 0
  for child in "${dir}"/*; do
    [[ -e "${child}" || -L "${child}" ]] || continue
    _cb_is_toolkit_path "${child}" && return 0
  done
  return 1
}

# _cb_clear_dir DIR - remove DIR/* except this toolkit and symlinks into it
_cb_clear_dir() {
  local entry
  for entry in "$1"/*; do
    [[ -e "${entry}" || -L "${entry}" ]] || continue
    if _cb_is_toolkit_path "${entry}"; then
      log "Keeping ${entry}"
    elif _cb_shelters_toolkit "${entry}"; then
      _cb_clear_dir "${entry}"
    else
      cbs_sudo rm -rf "${entry}"
    fi
  done
}

_cb_strip_bashrc() {
  local rc="${CBS_HOME}/.bashrc" backup
  if [[ ! -f "${rc}" ]]; then
    log "No ${rc}; nothing to strip."
    return 0
  fi
  backup="${rc}.chromebrew-scripts.$(date +%Y%m%d-%H%M%S).bak"
  run cp -p "${rc}" "${backup}" || die "Could not back up ${rc}; leaving it untouched."
  cbs_dry_run || log "Backed up ${rc} to ${backup}"
  run sed -i -e '/source.*profile/d' -e '/# DO NOT DELETE THIS LINE/d' \
    -e '/# See .*profile for further details/d' "${rc}" ||
    die "Could not edit ${rc}; the backup is at ${backup}."
}

_cb_remove() {
  if ! _crew_bin >/dev/null; then
    warn "crew was not found; clearing whatever is left under ${CBS_PREFIX} anyway."
  fi
  local real_prefix
  real_prefix="$(readlink -f -- "${CBS_PREFIX}" 2>/dev/null)" || real_prefix=''
  case "${real_prefix}" in
    ''|/|/home|/home/*|/mnt|/mnt/stateful_partition|/usr|/etc|/root|/opt)
      die "Refusing to clear '${CBS_PREFIX}': not a safe Chromebrew prefix." ;;
  esac
  [[ "${CBS_PREFIX}" == /* && -d "${CBS_PREFIX}" ]] ||
    die "Refusing to clear '${CBS_PREFIX}': not an existing absolute directory."
  confirm "Are you sure you want to uninstall Chromebrew? This clears ${CBS_PREFIX}/*" || exit 1
  _cb_strip_bashrc
  log "Clearing ${CBS_PREFIX}/* (keeping chromebrew-scripts at ${CBS_ROOT_DIR})"
  _cb_clear_dir "${CBS_PREFIX}"
  cbs_dry_run || log "Chromebrew removed. Open a new shell to pick up the changed ${CBS_HOME}/.bashrc."
}

_cb_status() {
  local crew version='unknown' detected='no'
  cbs_is_chromeos && detected='yes'
  printf 'chromebrew-scripts:  %s (%s)\n' "${CBS_VERSION}" "${CBS_ROOT_DIR}"
  printf 'Chrome OS detected:  %s\n' "${detected}"
  printf 'Chromebrew prefix:   %s\n' "${CBS_PREFIX}"
  if crew="$(_crew_bin)"; then
    local -a to
    read -r -a to <<<"$(_timeout_prefix)"
    version="$("${to[@]}" "${crew}" version 2>/dev/null | head -n1)" || version='unknown'
    printf 'crew:                %s\n' "${crew}"
    printf 'crew version:        %s\n' "${version:-unknown}"
  else
    printf 'crew:                not installed\n'
  fi
}

cbs_main() {
  local action=''
  while [[ $# -gt 0 ]]; do
    if cbs_global_flag "$1"; then
      shift
      continue
    fi
    case "$1" in
      -i|--install) action="${action:+${action} }install" ;;
      -r|--remove) action="${action:+${action} }remove" ;;
      -u|--update) action="${action:+${action} }update" ;;
      -s|--status) action="${action:+${action} }status" ;;
      *) cbs_usage_error "Unknown option: $1" ;;
    esac
    shift
  done

  case "${action}" in
    '') cbs_usage_error "Usage: ${CBS_CMD_NAME} -i | --install | -r | --remove | -u | --update | -s | --status" ;;
    *' '*) cbs_usage_error "Choose exactly one action (got: ${action})" ;;
  esac

  if [[ "${action}" != status ]]; then
    cbs_require_chromeos
  fi
  "_cb_${action}"
}
