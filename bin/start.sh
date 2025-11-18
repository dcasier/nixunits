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

container_env "$id"
_unit="nixunits@${id}.service"
# _unit_net="nixunits-network@${id}.service"

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

switch() {
  echo "Switch"
  mkdir -p "$CONTAINER_OLD"
  if [ -f "$CONTAINER_OK" ]; then
    mv "$CONTAINER_OK" "${CONTAINER_OK}_bkp"
  fi
  test -d "$CONTAINER_ROOT/nix" && mv "$CONTAINER_ROOT/nix" "$CONTAINER_OLD/"
  test -f "$CONTAINER_DIR/unit.conf" && rm "$CONTAINER_DIR/unit.conf"

  install -o "$CONTAINER_RID" -g "$CONTAINER_RID" -m 2750 -d "$CONTAINER_ROOT"
  install -o "$CONTAINER_RID" -g "$CONTAINER_RID" -d "$CONTAINER_ROOT/usr"

  rm -f "$C_FUTUR_OK"
  mv "$C_FUTUR/nix" "$CONTAINER_ROOT"
  mv "$C_FUTUR/unit.conf" "$CONTAINER_DIR/unit.conf"
  mv "$C_FUTUR_ARGS" "$CONTAINER_ARGS"
  mv "$C_FUTUR_NIX" "$CONTAINER_OK"
}

S=$(_NIXUNITS_PATH_SED_/bin/status.sh "$id")
started=$(echo "$S" | jq -r .started)

if [[ "$started" = true ]] && [ "$RESTART" != true ];then
    SWITCH=false
elif [ "$(echo "$S" | jq -r .need_switch)" != "true" ]; then
    SWITCH=false
fi

if [ ! -f "$CONTAINER_OK" ] && [ "$SWITCH" = false ]; then
  echo "Container $id not ready"
  exit 1
fi

_NIXUNITS_PATH_SED_/bin/enable.sh "$id"

if [[ "$started" == "true" ]] && [ "$RESTART" = true ]; then
  systemctl stop "$_unit"
fi

if [ "$SWITCH" = true ] ; then
  lock_acquire "$CONTAINER_LOCK"
  trap 'lock_release "$CONTAINER_LOCK"' EXIT
  switch
  lock_release "$CONTAINER_LOCK"
  trap - EXIT
fi

if [[ "$started" != true ]] || [ "$RESTART" = true ]
then
  systemctl start "$_unit"
  systemctl status "$_unit" --no-pager
fi
