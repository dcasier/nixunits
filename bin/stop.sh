#!/bin/bash
set -euo pipefail

. _NIXUNITS_PATH_SED_/bin/common.sh

usage() {
  echo "Usage : nixunits stop <container id> [options]"
  echo "Available options:"
  echo "  -f  stop even if processes run in the container from outside"
  echo "      (nixunits shell, nsenter ...)"
  echo "  -h  help"
  echo

  test -n "${1:-}" && exit "$1"
  exit 0
}

[[ "${1:-}" =~ ^(-h|--help)$ ]] && usage 0
test $# -eq 0 && usage 1
id=$1
shift
id_check "$id"

FORCE_STOP=false
while getopts "fh" opt; do
  case $opt in
    f) FORCE_STOP=true;;
    h) usage 0;;
    *) usage 1;;
  esac
done

if [ "$FORCE_STOP" != true ]; then
  jobs=$(external_jobs "$id")
  if [ -n "$jobs" ]; then
    echo "ERROR: processes run in $id from outside, not stopping (-f to force):" >&2
    echo "$jobs" >&2
    exit 1
  fi
fi

systemctl stop "nixunits@${id}.service"
