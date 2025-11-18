#!/bin/bash
set -e

. _NIXUNITS_PATH_SED_/bin/common.sh

usage() {
  echo "Usage : nixunits status <container id> [options]"
  echo "Available options:"
  echo "  -j  JSON parameters file"
  echo "  -n  Nix config file"
  echo "  -h, --help"
  test -n "$1" && exit "$1"
  exit 0
}

test $# -eq 0 && usage 1
id=$1
[[ "$1" =~ ^(-h|--help)$ ]] && usage 0
shift


NIX_FILE=""
PARAMS_FILE=""
while getopts "j:n:h" opt; do
  case $opt in
    j) PARAMS_FILE=$OPTARG;;
    n) NIX_FILE=$OPTARG;;
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

STATUS="initial"
if [ -f "$CONTAINER_OK" ]; then
  STATUS="configured"
  [ "$STARTED" = true ] && STATUS="started"
fi

NEED_SWITCH=false
NEED_STORE_BUILD="unknown"
NEED_CONTAINER_BUILD="unknown"

if [ -f "$C_FUTUR_OK" ]; then
  NEED_SWITCH=true
  STATUS="created"
fi

if [ -f "$NIX_FILE" ];then
  if [ -f "$C_FUTUR_OK" ]; then
    ARGS_ORI="$C_FUTUR_ARGS"
    NIX_ORI="$C_FUTUR_NIX"
  else
    ARGS_ORI="$CONTAINER_ARGS"
    NIX_ORI="$CONTAINER_NIX"
  fi
  if [ -f "$NIX_ORI" ]; then
    FUT_HASH=$(hash_with "$NIX_FILE" "$(hash_ctx)")
    ORI_HASH=$(hash_with "$NIX_ORI" "$(hash_ctx)")
    NEED_STORE_BUILD=$([ "$FUT_HASH" != "$ORI_HASH" ] && echo true | echo false)
    if [ "$NEED_STORE_BUILD" = "true" ];then
      NEED_CONTAINER_BUILD="true"
    elif [ -f "$PARAMS_FILE" ] && [ -f "$ARGS_ORI" ]; then
      FUT_HASH=$(hash_with "$PARAMS_FILE" "$FUT_HASH")
      ORI_HASH=$(hash_with "$AGRS_ORI" "$ORI_HASH")
      NEED_CONTAINER_BUILD=$([ "$FUT_HASH" != "$ORI_HASH" ] && echo true | echo false)
    fi
  fi
fi

printf '{\n'
printf '  "id": "%s",\n' "$id"
printf '  "started": "%s",\n' "$STARTED"
printf '  "status": "%s",\n' "$STATUS"
printf '  "in_nixos": "%s",\n' "$IN_NIXOS"
printf '  "need_container_build": %s' "$NEED_CONTAINER_BUILD"
printf '  "need_store_build": %s' "$NEED_STORE_BUILD"
printf '  "need_switch": %s' "$NEED_SWITCH"

if [ "$STARTED" = true ];then
  printf ',\n  "os": "%s",\n' "$OS"
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
printf '}\n'