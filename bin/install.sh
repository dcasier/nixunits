#!/bin/bash
set -euo pipefail

. _NIXUNITS_PATH_SED_/bin/common.sh

usage() {
  echo "Usage : nixunits build [options]"
  echo "Available options:"
  echo "  -d  debug (show-trace)"

  test -n "$1" && exit "$1"
  exit 0
}

DEBUG=false
ARGS=()
while getopts "d" opt; do
  case $opt in
    d)
      DEBUG=true
      ARGS=("--show-trace")
      ;;
    \?)
      echo "Invalid option : -$OPTARG" >&2
      usage 1;;
  esac
done
shift "$((OPTIND-1))"

if [ $# -ne 0 ]; then
  echo "Invalid parameters '$1'." >&2
  usage 1
fi

echo "Build sys"


STORE_DEFAULT="/var/lib/nixunits/store/default"

ARGS+=(--impure --no-link)

mkdir -p "$STORE_DEFAULT/root" /var/lib/nixunits/containers /var/lib/nixunits/etc/systemd


MK_SYS="(builtins.getFlake \"path:_NIXUNITS_PATH_SED_\").lib.x86_64-linux.mkSys"

cmd=(nix build "${ARGS[@]}" --no-link --print-out-paths --store "$STORE_DEFAULT/root" --expr "($MK_SYS)")

if [ "${DEBUG:-false}" = true ]; then
  echo "${cmd[@]}"
fi
RESULT_PATH="$("${cmd[@]}")"

SYSTEM_PATH=$(readlink "$STORE_DEFAULT/$RESULT_PATH/etc/systemd/system/")
SERVICE_PATH=$(readlink "$STORE_DEFAULT/$SYSTEM_PATH/nixunits@.service")

ln -sfn "$SERVICE_PATH" /etc/systemd/system/nixunits@.service

systemctl daemon-reload
echo "[nixunits] Done"
