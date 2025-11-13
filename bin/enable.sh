#!/bin/bash
set -euo pipefail

. _NIXUNITS_PATH_SED_/bin/common.sh

usage() {
  echo "Usage : nixunits enable <container id> [options]"
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

mkdir -p "${SYSTEMD_PATH}/machine-${id}.scope.wants" ${SYSTEMD_PATH}/machines.target.wants/
ln -fs "${SYSTEMD_PATH}/nixunits-network@.service" "${SYSTEMD_PATH}/machine-${id}.scope.wants/$_unit_net"
ln -fs "${SYSTEMD_PATH}/nixunits@.service" "${SYSTEMD_PATH}/multi-user.target.wants/$_unit"
systemctl daemon-reload

