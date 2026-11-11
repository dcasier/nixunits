#!/bin/bash
set -euo pipefail

. _NIXUNITS_PATH_SED_/bin/common.sh

usage() {
  echo "Usage : nixunits disable <container id> [options]"
  echo "Disable the start at boot. The network trigger is kept: a container"
  echo "still running must get its network when it restarts."
  echo "Available options:"
  echo "  -a  also remove the network trigger (container deletion)"
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
id_check "$id"

ALL=false
while getopts "ah" opt; do
  case $opt in
    a)
      ALL=true;;
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
if [ "$ALL" = true ]; then
  # machine-<id>.scope (systemd <= 258) or <id>.scope (systemd >= 259)
  for _scope in "machine-${id}.scope" "${id}.scope"; do
    test -f "${SYSTEMD_PATH}/${_scope}.wants/$_unit_net" && rm "${SYSTEMD_PATH}/${_scope}.wants/$_unit_net" || true
    test -d "${SYSTEMD_PATH}/${_scope}.wants" && rmdir "${SYSTEMD_PATH}/${_scope}.wants" || true
  done
fi
systemctl daemon-reload

