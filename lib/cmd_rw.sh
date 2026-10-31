# lib/cmd_rw.sh - mount the filesystem read/write
# Reference: https://sites.google.com/site/cr48ite/getting-technical/remove-rootfs-verification-make-read-write
# shellcheck shell=bash

cmd_usage() {
  cat <<EOF
Usage: ${CBS_CMD_NAME} [options]

Remount the root filesystem read/write and allow executables on the
stateful partition and the user home:
  ${CBS_SUDO} mount -o remount,rw ${CBS_ROOTFS_MOUNT}
  ${CBS_SUDO} mount -o remount,exec ${CBS_STATEFUL}
  ${CBS_SUDO} mount -i -o remount,exec ${CBS_USER_HOME}

Remounting / read/write requires rootfs verification to be removed first
(see: rootfs).
EOF
  cbs_usage_footer
}

cbs_main() {
  while [[ $# -gt 0 ]]; do
    if cbs_global_flag "$1"; then
      shift
      continue
    fi
    cbs_usage_error "Unknown option: $1"
  done

  cbs_require_chromeos
  confirm "Are you sure you want to mount the filesystem read/write?" || exit 1

  log "Setting the filesystem to mount read/write..."
  if cbs_sudo mount -o remount,rw "${CBS_ROOTFS_MOUNT}" &&
    cbs_sudo mount -o remount,exec "${CBS_STATEFUL}" &&
    cbs_sudo mount -i -o remount,exec "${CBS_USER_HOME}"; then
    log "You should now have full read/write access."
  else
    die "There were no filesystem changes."
  fi
}
