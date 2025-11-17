#!/bin/bash
set -euo pipefail

. _NIXUNITS_PATH_SED_/bin/common.sh

usage() {
  echo "Usage : nixunits start <container id> [options]"
  echo "Available options:"
  echo "  -r  restart ?"
  echo "  -s  switch ?"
  echo "  -h  help"
  echo

  test -n "$1" && exit "$1"
  exit 0
}

[[ "$1" =~ ^(-h|--help)$ ]] && usage 0
test $# -eq 0 && usage 1
id=$1
shift
echo "Start $id"

CONTAINER_DIR=$(unit_dir "$id")
if [[ "$CONTAINER_DIR" != *var*nixunits* ]]; then
    echo "INTERNAL ERROR : invalid value for CONTAINER_DIR ${CONTAINER_DIR}" >&2
    exit 1
fi

ROOT="$CONTAINER_DIR/root"
TMP_DIR="$CONTAINER_DIR/tmp"
ROOT_FUTUR="$TMP_DIR/root_futur"
ROOT_OLD="$TMP_DIR/root_old"
UID_ROOT=$(uid_root "$id")

RESTART=false
SWITCH=false

while getopts "rsh" opt; do
  case $opt in
    r) RESTART=true;;
    s) SWITCH=true;;
    h) usage;;
    *) usage 1;;
  esac
done

_NIXUNITS_PATH_SED_/bin/enable.sh "$id"

cleanup() {
  lock_release
}

switch() {
  echo "Switch"
  mkdir -p "$ROOT/usr" "$ROOT_OLD"
  chown "$UID_ROOT":"$UID_ROOT" "$ROOT"
  chown "$UID_ROOT":"$UID_ROOT" "$ROOT/usr"
  test -d "$ROOT/nix" && mv "$ROOT/nix" "$ROOT_OLD/"
  mv "$ROOT_FUTUR/nix" "$ROOT/"
  test -f "$CONTAINER_DIR/unit.conf" && rm "$CONTAINER_DIR/unit.conf"
  mv "$ROOT_FUTUR/unit.conf" "$CONTAINER_DIR/unit.conf"
  cp "$ROOT_FUTUR/parameters.json" "$(unit_parameters "$id")"
  rm "$ROOT_FUTUR/.complete"
}

_unit="nixunits@${id}.service"
_unit_net="nixunits-network@${id}.service"

STARTED=$(systemctl show "$_unit" --no-pager |grep ^SubState=running >/dev/null && echo true || echo false)

if [ "$STARTED" = true ] && [ "$RESTART" = true ]; then
  systemctl stop "$_unit"
fi

if [ "$STARTED" != true ] || [ "$RESTART" = true ];then
  if [ "$SWITCH" = true ] && [ -f "$ROOT_FUTUR/.complete" ]; then
    lock_acquire
    switch
    trap cleanup EXIT
  fi
fi

if [ "$STARTED" != true ] || [ "$RESTART" = true ]
then
  systemctl start "$_unit"
  systemctl status "$_unit" --no-pager
fi
