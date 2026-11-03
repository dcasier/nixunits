#!/bin/bash
set -euo pipefail

. _NIXUNITS_PATH_SED_/bin/common.sh

usage() {
  echo "Usage : nixunits gc [options]"
  echo "Remove the store roots no container uses any more, then garbage"
  echo "collect the containers store ($STORE_CONTAINERS)."
  echo "Available options:"
  echo "  -n  dry run (only list the roots to remove)"
  echo "  -h  help"
  echo

  test -n "${1:-}" && exit "$1"
  exit 0
}

DRY_RUN=false
while getopts "nh" opt; do
  case $opt in
    n) DRY_RUN=true;;
    h) usage 0;;
    *) usage 1;;
  esac
done

lock_acquire
trap lock_release EXIT

# Roots in use: the last built (store) and the running one (store.current)
declare -A keep=()
for link in "$PATH_CONTAINERS"/*/store "$PATH_CONTAINERS"/*/store.current; do
  [ -L "$link" ] || continue
  keep["$(readlink "$link")"]=1
done

for root in "$GCROOTS_CONTAINERS"/*; do
  [ -L "$root" ] || continue
  if [ -z "${keep[$root]+x}" ]; then
    echo "Remove root $root"
    [ "$DRY_RUN" = true ] || rm "$root"
  fi
done

if [ "$DRY_RUN" = false ]; then
  nix-store --store "$STORE_CONTAINERS" --gc
fi
