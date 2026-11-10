#!/bin/bash
set -euo pipefail

. _NIXUNITS_PATH_SED_/bin/common.sh

usage() {
  echo "Usage : nixunits start <container id> [options]"
  echo "Available options:"
  echo "  -f  restart even if processes run in the container from outside"
  echo "      (nixunits shell, nsenter ...)"
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
id_check "$id"
echo "Start $id"

container_env "$id"
_unit="nixunits@${id}.service"
# _unit_net="nixunits-network@${id}.service"

FORCE_STOP=false
RESTART=false
SWITCH=false
CONTAINER_RID="$(uid_root "$id")"

while getopts "frsh" opt; do
  case $opt in
    f) FORCE_STOP=true;;
    r) RESTART=true;;
    s) SWITCH=true;;
    h) usage;;
    *) usage 1;;
  esac
done

switch() {
  echo "Switch"

  # The container root is writable by the container: never follow a
  # symlink planted there (install -d would chown its host target).
  local d
  for d in "$CONTAINER_ROOT" "$CONTAINER_ROOT/usr"; do
    if [ -L "$d" ]; then
      echo "ERROR: $d is a symlink, refusing to switch" >&2
      exit 1
    fi
  done

  # Slow part first, while the current root is still untouched
  chown -R "${CONTAINER_RID}:${CONTAINER_RID}" "$C_FUTUR/nix"
  install -o "$CONTAINER_RID" -g "$CONTAINER_RID" -d "$CONTAINER_ROOT"
  install -o "$CONTAINER_RID" -g "$CONTAINER_RID" -d "$CONTAINER_ROOT/usr"

  mkdir -p "$CONTAINER_OLD"
  rm -fr "$CONTAINER_OLD/nix"
  local had_old=false
  if [ -e "$CONTAINER_ROOT/nix" ] || [ -L "$CONTAINER_ROOT/nix" ]; then
    mv "$CONTAINER_ROOT/nix" "$CONTAINER_OLD/nix"
    had_old=true
  fi
  if ! mv "$C_FUTUR/nix" "$CONTAINER_ROOT/nix"; then
    echo "ERROR: switch failed, restoring the previous root" >&2
    if [ "$had_old" = true ]; then
      mv "$CONTAINER_OLD/nix" "$CONTAINER_ROOT/nix"
    fi
    exit 1
  fi

  if [ -f "$CONTAINER_OK" ]; then
    mv "$CONTAINER_OK" "${CONTAINER_OK}_bkp"
  fi
  mv -f "$C_FUTUR/unit.conf" "$CONTAINER_DIR/unit.conf"
  mv "$C_FUTUR_ARGS" "$CONTAINER_ARGS"
  rm -f "$C_FUTUR_OK"
  # configuration.nix is what build/status compare against
  mv "$C_FUTUR_NIX" "$CONTAINER_NIX"
  cp "$CONTAINER_NIX" "$CONTAINER_OK"
  # store root of the root now in use, kept by `nixunits gc`
  if [ -L "$CONTAINER_DIR/store" ]; then
    ln -Tfs "$(readlink "$CONTAINER_DIR/store")" "$CONTAINER_DIR/store.current"
  fi
}

S=$(_NIXUNITS_PATH_SED_/bin/status.sh "$id")
started=$(echo "$S" | jq -r .started)

if [[ "$started" = true ]] && [ "$RESTART" != true ];then
    SWITCH=false
elif [ "$(echo "$S" | jq -r .need_switch)" != "true" ]; then
    SWITCH=false
fi

if [[ "$started" == "true" ]] && [ "$RESTART" = true ] && [ "$FORCE_STOP" != true ]; then
  jobs=$(external_jobs "$id")
  if [ -n "$jobs" ]; then
    echo "ERROR: processes run in $id from outside, not restarting (-f to force):" >&2
    echo "$jobs" >&2
    exit 1
  fi
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
  net_check "$id"
  systemctl start "$_unit"
fi
