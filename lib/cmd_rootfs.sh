# lib/cmd_rootfs.sh - remove rootfs verification
# References:
# https://www.chromium.org/chromium-os/poking-around-your-chrome-os-device#TOC-Making-changes-to-the-filesystem
# https://sites.google.com/site/cr48ite/getting-technical/remove-rootfs-verification-make-read-write
# shellcheck shell=bash

cmd_usage() {
  cat <<EOF
Usage: ${CBS_CMD_NAME} [options] [-- make_dev_ssd.sh args...]

Remove rootfs verification with
  ${CBS_SUDO} ${CBS_VBOOT_BIN}/make_dev_ssd.sh --remove_rootfs_verification
and reboot. The reboot only happens when make_dev_ssd.sh succeeded.

Anything after "--" is passed to make_dev_ssd.sh; recent Chrome OS versions
ask for the kernel partition, e.g.: ${CBS_CMD_NAME} -- --partitions 2

Options:
      --no-reboot  do not reboot afterwards
EOF
  cbs_usage_footer
}

cbs_main() {
  local reboot=1
  local -a extra=()
  while [[ $# -gt 0 ]]; do
    if cbs_global_flag "$1"; then
      shift
      continue
    fi
    case "$1" in
      --no-reboot) reboot=0 ;;
      --)
        shift
        extra=("$@")
        break
        ;;
      *) cbs_usage_error "Unknown option: $1" ;;
    esac
    shift
  done

  cbs_require_chromeos
  confirm "Are you sure you want to remove rootfs verification?" || exit 1

  if ! cbs_sudo "${CBS_VBOOT_BIN}/make_dev_ssd.sh" --remove_rootfs_verification "${extra[@]}"; then
    die "make_dev_ssd.sh failed; not rebooting."
  fi

  if [[ "${reboot}" == 1 ]]; then
    cbs_sudo reboot
  else
    log "Rootfs verification removed; reboot to apply it."
  fi
}
