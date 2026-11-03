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
id_check "$id"


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

STARTED_INFO=$(machinectl -o json | _JQ_SED_ -c --arg id "$id" '.[] | select(.machine == $id)' || true)
if [ -n "$STARTED_INFO" ]; then
  STARTED=true
else
  STARTED_INFO='{}'
fi

STATUS="initial"
if [ -f "$CONTAINER_OK" ]; then
  STATUS="configured"
  [ "$STARTED" = true ] && STATUS="started"
fi

NEED_SWITCH=false
NEED_STORE_BUILD=false
NEED_CONTAINER_BUILD=false

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
    FUT_HASH=$(hash_with "$NIX_FILE" "$ENV_HASH")
    ORI_HASH=$(hash_with "$NIX_ORI" "$ENV_HASH")
    NEED_STORE_BUILD=$([ "$FUT_HASH" != "$ORI_HASH" ] && echo true || echo false)
    if [ "$NEED_STORE_BUILD" = "true" ]; then
      NEED_CONTAINER_BUILD="true"
    elif [ -f "$PARAMS_FILE" ] && [ -f "$ARGS_ORI" ]; then
      FUT_HASH=$(hash_with "$PARAMS_FILE" "$FUT_HASH")
      ORI_HASH=$(hash_with "$ARGS_ORI" "$ORI_HASH")
      NEED_CONTAINER_BUILD=$([ "$FUT_HASH" != "$ORI_HASH" ] && echo true || echo false)
    fi
  fi
fi

_JQ_SED_ -n \
  --arg id "$id" \
  --arg status "$STATUS" \
  --argjson started "$STARTED" \
  --argjson in_nixos "$IN_NIXOS" \
  --argjson need_container_build "$NEED_CONTAINER_BUILD" \
  --argjson need_store_build "$NEED_STORE_BUILD" \
  --argjson need_switch "$NEED_SWITCH" \
  --argjson info "$STARTED_INFO" \
  '{
    id: $id,
    started: $started,
    status: $status,
    in_nixos: $in_nixos,
    need_container_build: $need_container_build,
    need_store_build: $need_store_build,
    need_switch: $need_switch
  } + (if $started then {
    os: ($info.os // ""),
    version: ($info.version // ""),
    addresses: ([($info.addresses // "") | splits("\\s+")] | map(select(length > 0)))
  } else {} end)'