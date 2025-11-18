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

if [ -d "$CONTAINER_OK" ]; then
  STATUS="configured"
  [ "$STARTED" = true ] && STATUS="started"
fi

NEED_SWITCH=false
if [ -f "$C_FUTUR_OK" ]; then
  NEED_SWITCH=true
  STATUS="created"
fi

printf '{\n'
printf '  "id": "%s",\n' "$id"
printf '  "started": "%s",\n' "$STARTED"
printf '  "status": "%s",\n' "$STATUS"
printf '  "in_nixos": "%s",\n' "$IN_NIXOS"
printf '  "need_switch": %s,\n' "$NEED_SWITCH"

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
printf '}\n'