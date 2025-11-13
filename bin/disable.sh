#!/bin/bash
set -euo pipefail

. _NIXUNITS_PATH_SED_/bin/common.sh

usage() {
  echo "Usage : nixunits disable <container id> [options]"
  echo "Available options:"
  echo "  -h  help"
  echo

  test -n "$1" && exit "$1"
  exit 0
}

id=$1
test -z "$id" && usage 1
test "$id" = "h" && usage 0
test "$id" = "-h" && usage 0
test "$id" = "help" && usage 0
test "$id" = "--help" && usage 0
shift

while getopts "h" opt; do
  case $opt in
    h)
      usage;;
    \?)
      echo "Invalid option : -$OPTARG" >&2
      usage 1;;
  esac
done

_unit="nixunits@${id}.service"
_unit_net="nixunits-network@${id}.service"

if grep -q '^ID=nixos' /etc/os-release; then
  SYSTEMD_PATH="/run/systemd/system"
else
  SYSTEMD_PATH="/etc/systemd/system"
fi

test -f "${SYSTEMD_PATH}/multi-user.target.wants/$_unit" && rm "${SYSTEMD_PATH}/multi-user.target.wants/$_unit" || true
test -f "${SYSTEMD_PATH}/machine-${ID}.scope.wants/$_unit_net" && rm "${SYSTEMD_PATH}/machine-${ID}.scope.wants/$_unit_net" || true
test -d "${SYSTEMD_PATH}/machine-${ID}.scope.wants" && rmdir "${SYSTEMD_PATH}/machine-${ID}.scope.wants" || true
systemctl daemon-reload

