# lib/cmd_powerwash.sh - reset a Chrome OS device to factory settings
# Reference: https://neverware.zendesk.com/hc/en-us/articles/115000765287--Powerwash-via-the-cmd-line
# shellcheck shell=bash

cmd_usage() {
  cat <<EOF
Usage: ${CBS_CMD_NAME} [options]

Reset this Chrome OS device to factory settings (powerwash). Writes "clobber"
to ${CBS_STATEFUL}/.update_available and reboots; every local file and user
account is erased on the next boot.

Options:
      --no-reboot  schedule the powerwash but do not reboot
EOF
  cbs_usage_footer
}

_powerwash_write_marker() {
  echo clobber | "${CBS_SUDO}" tee "${CBS_STATEFUL}/.update_available"
}

cbs_main() {
  local reboot=1
  while [[ $# -gt 0 ]]; do
    if cbs_global_flag "$1"; then
      shift
      continue
    fi
    case "$1" in
      --no-reboot) reboot=0 ;;
      *) cbs_usage_error "Unknown option: $1" ;;
    esac
    shift
  done

  cbs_require_chromeos
  confirm "Are you sure you want to reset to factory settings?" || exit 1

  run_pipe "echo clobber | ${CBS_SUDO} tee ${CBS_STATEFUL}/.update_available" \
    _powerwash_write_marker ||
    die "Could not write ${CBS_STATEFUL}/.update_available; not rebooting."

  if [[ "${reboot}" == 1 ]]; then
    cbs_sudo reboot
  else
    log "Powerwash scheduled; reboot to apply it."
  fi
}
