#!/bin/bash
set -e

. _NIXUNITS_PATH_SED_/bin/common.sh

usage() {
  echo "Usage : nixunits status <container id> [options]"
  echo "Available options:"
  echo "  -h, --help"
  test -n "$1" && exit "$1"
  exit 0
}

test $# -eq 0 && usage 1
id=$1
[[ "$1" =~ ^(-h|--help)$ ]] && usage 0
shift

while getopts "h" opt; do
  case $opt in
    h) usage;;
    *) usage 1;;
  esac
done

container_env "$id"

STARTED=false

IN_NIXOS=$(in_nixos "$id" && echo "true" || echo "false")

STARTED_INFO=$(machinectl -o json | _JQ_SED_ ".[] | select(.machine == \"$id\")" || true)
if [ -n "$STARTED_INFO" ]; then
  STARTED=true
  OS=$(echo "$STARTED_INFO" | _JQ_SED_ -r .os)
  VERSION=$(echo "$STARTED_INFO" | _JQ_SED_ -r .version)
  mapfile -t ADDRESSES < <(echo "$STARTED_INFO" | _JQ_SED_ -r '.addresses[]?' || true)
fi

NIX_FILE=""
PARAMS_FILE=""
if [ -d "$CONTAINER_OK" ]; then
  NIX_FILE="$CONTAINER_NIX"
  PARAMS_FILE="$CONTAINER_ARGS"
  STATUS="configured"
  [ "$STARTED" = true ] && STATUS="started"
fi

NEED_SWITCH=false
if [ -f "$C_FUTUR_OK" ]; then
  NEED_SWITCH=true
  NIX_FILE="$CONTAINER_NIX"
  PARAMS_FILE="$CONTAINER_ARGS"
  STATUS="created"
fi

if [ -z "$NIX_FILE" ] || [ -z "$PARAMS_FILE" ]; then
  STATUS="initial"
fi

analyze() {
  NEED_BUILD_CONTAINER=true
  NEED_UPDATE=true
  FLAKE_REV=$(nix flake metadata "_NIXUNITS_PATH_SED_" --json | jq -r '.revision // .fingerprint // "dirty"')

  NIX_HASH=$(sha1sum "$NIX_FILE" | cut -d' ' -f1)
  PARAMS_HASH=$(sha1sum "$PARAMS_FILE" | cut -d' ' -f1)

  STORE_HASH=$(echo "${SYSTEM}-${NIX_HASH}-${FLAKE_REV}" | sha1sum | cut -d' ' -f1)
  GCROOT_PATH="/var/lib/nixunits/gcroots/$STORE_HASH"

  if [ -e "$GCROOT_PATH" ] && [ -e "$(readlink -f "$GCROOT_PATH")" ]
  then
    NEED_UPDATE=false
    UNIT_HASH=$(echo -n "${STORE_HASH}-${PARAMS_HASH}" | sha1sum | cut -d' ' -f1)
    if [ -f "$CONTAINER_META" ] && [ "$(cat "$CONTAINER_META")" = "$UNIT_HASH" ]; then
      NEED_BUILD_CONTAINER=false
    fi
  fi
}

printf '{\n'
printf '  "id": "%s",\n' "$id"
printf '  "started": "%s",\n' "$STARTED"
printf '  "status": "%s",\n' "$STATUS"
printf '  "in_nixos": "%s",\n' "$IN_NIXOS"

if [ "$STARTED" = true ];then
  printf '  "os": "%s",\n' "$OS"
  printf '  "version": "%s",\n' "$VERSION"
  printf '  "addresses": ['
  first=true
  for a in "${ADDRESSES[@]}"; do
    $first || printf ', '
    printf '"%s"' "$a"
    first=false
  done
  printf ']\n'
fi

if [ "$IN_NIXOS" = false ] && [ "$STATUS" != "initial" ]; then
  analyze
  if [ "$NEED_UPDATE" = true ] || [ "$NEED_BUILD_CONTAINER" = true ]; then
    STATUS="created"
  fi
  printf '  "store_hash": "%s",\n' "$STORE_HASH"
  printf '  "unit_hash": "%s",\n' "$UNIT_HASH"
  printf '  "need_update": %s,\n' "$NEED_UPDATE"
  printf '  "need_build_container": %s,\n' "$NEED_BUILD_CONTAINER"
  printf '  "need_switch": %s,\n' "$NEED_SWITCH"
fi
printf '}\n'