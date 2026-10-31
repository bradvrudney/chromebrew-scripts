#!/usr/bin/env bash
# install.sh - install, update or uninstall chromebrew-scripts.
#
# Installs the toolkit to PREFIX/share/chromebrew-scripts and symlinks the
# commands into PREFIX/bin (default PREFIX: /usr/local).
#
# Environment:
#   PREFIX            install prefix (also --prefix)
#   CBS_REPO          GitHub repo for --update (default bradvrudney/chromebrew-scripts)
#   CBS_REF           git ref for --update (default master)
#   CBS_TARBALL_URL   full tarball URL for --update (overrides CBS_REPO/CBS_REF)
#   CBS_SUDO          privilege escalation command when PREFIX is not writable
#                     (default sudo; set to an empty string to never escalate)
#   CBS_CURL_TIMEOUT  seconds allowed for the --update download (default 300)
set -Eeuo pipefail

NAME="chromebrew-scripts"
COMMANDS=(chromebrew powerwash rootfs rw)
PREFIX="${PREFIX:-/usr/local}"
CBS_REPO="${CBS_REPO:-bradvrudney/chromebrew-scripts}"
CBS_REF="${CBS_REF:-master}"
CBS_TARBALL_URL="${CBS_TARBALL_URL:-https://github.com/${CBS_REPO}/archive/${CBS_REF}.tar.gz}"
CBS_SUDO="${CBS_SUDO-sudo}"
CBS_CURL_TIMEOUT="${CBS_CURL_TIMEOUT:-300}"
SRC_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ACTION="install"

usage() {
  cat <<EOF
Usage: install.sh [--prefix DIR] [--uninstall | --update] [-h]

  (default)        install ${NAME} to DIR/share/${NAME} and symlink
                   ${COMMANDS[*]} into DIR/bin
      --prefix DIR install prefix (default: ${PREFIX})
      --uninstall  remove the symlinks and DIR/share/${NAME}
      --update     download ${CBS_TARBALL_URL}
                   and reinstall from it (CBS_REPO / CBS_REF / CBS_TARBALL_URL)
  -h, --help       show this help
EOF
}

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

# priv CMD... - run CMD, through CBS_SUDO when PREFIX is not writable by us
priv() {
  local probe="${PREFIX}"
  while [[ ! -e "${probe}" ]]; do probe="$(dirname "${probe}")"; done
  if [[ -w "${probe}" || -z "${CBS_SUDO}" ]]; then
    "$@"
  else
    "${CBS_SUDO}" "$@"
  fi
}

do_install() {
  local share="${PREFIX}/share/${NAME}" cmd
  [[ -d "${SRC_DIR}/bin" && -d "${SRC_DIR}/lib" ]] ||
    die "${SRC_DIR} does not look like a ${NAME} checkout (no bin/ and lib/)."
  priv mkdir -p "${share}" "${PREFIX}/bin"
  priv rm -rf "${share}/bin" "${share}/lib"
  priv cp -R "${SRC_DIR}/bin" "${SRC_DIR}/lib" "${share}/"
  local f
  for f in VERSION LICENSE README.md install.sh; do
    [[ -f "${SRC_DIR}/${f}" ]] && priv cp "${SRC_DIR}/${f}" "${share}/${f}"
  done
  priv chmod 755 "${share}"/bin/* "${share}/install.sh"
  for cmd in "${COMMANDS[@]}"; do
    priv ln -sfn "../share/${NAME}/bin/${cmd}" "${PREFIX}/bin/${cmd}"
  done
  printf '%s %s installed to %s\n' "${NAME}" "$(cat "${share}/VERSION" 2>/dev/null || echo dev)" "${share}"
  printf 'Commands linked in %s: %s\n' "${PREFIX}/bin" "${COMMANDS[*]}"
}

do_uninstall() {
  local share="${PREFIX}/share/${NAME}" cmd link target
  for cmd in "${COMMANDS[@]}"; do
    link="${PREFIX}/bin/${cmd}"
    [[ -L "${link}" ]] || continue
    target="$(readlink -f -- "${link}" 2>/dev/null || true)"
    case "${target}" in
      "${share}"/*|"$(readlink -f -- "${share}" 2>/dev/null || echo "${share}")"/*) priv rm -f "${link}" ;;
      *) printf 'Leaving %s alone (not ours)\n' "${link}" ;;
    esac
  done
  priv rm -rf "${share}"
  printf '%s removed from %s\n' "${NAME}" "${PREFIX}"
}

do_update() {
  local tmp src
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/${NAME}-update.XXXXXX")"
  # shellcheck disable=SC2064
  trap "rm -rf '${tmp}'" EXIT
  printf 'Downloading %s\n' "${CBS_TARBALL_URL}"
  curl --fail --location --silent --show-error --max-time "${CBS_CURL_TIMEOUT}" \
    -o "${tmp}/src.tar.gz" "${CBS_TARBALL_URL}" || die "Download failed."
  mkdir -p "${tmp}/src"
  tar -xzf "${tmp}/src.tar.gz" -C "${tmp}/src" || die "Could not extract the tarball."
  src="$(find "${tmp}/src" -mindepth 1 -maxdepth 1 -type d | head -n1)"
  [[ -n "${src}" && -f "${src}/install.sh" ]] || die "The tarball has no install.sh."
  env PREFIX="${PREFIX}" CBS_SUDO="${CBS_SUDO}" bash "${src}/install.sh" --prefix "${PREFIX}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    --prefix)
      [[ $# -ge 2 ]] || die "--prefix needs a directory"
      PREFIX="$2"
      shift
      ;;
    --prefix=*) PREFIX="${1#--prefix=}" ;;
    --uninstall) ACTION="uninstall" ;;
    --update) ACTION="update" ;;
    *)
      usage >&2
      die "Unknown option: $1"
      ;;
  esac
  shift
done

"do_${ACTION}"
