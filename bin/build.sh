#!/bin/bash
set -euo pipefail

. _NIXUNITS_PATH_SED_/bin/common.sh

usage() {
  echo "Usage : nixunits build <container id> [options]"
  echo "Available options:"
  echo "  -d  debug (show-trace)"
  echo "  -n  Nix config file"
  echo "  -j  JSON parameters file"
  echo "  -h  help"
  echo "  -r  restart ?"
  echo "  -s  start ?"
  echo
  echo "Examples:"
  echo

  test -n "$1" && exit "$1"
  exit 0
}

test -z "$1" && usage 1
test "$1" = "-h" && usage 0
test "$1" = "--help" && usage 0

DEBUG=false
ARGS=()
while getopts "dn:j:hsr" opt; do
  case $opt in
    d)
      DEBUG=true
      ARGS=("--show-trace")
      ;;
    r)
      RESTART=true;;
    s)
      START=true;;
    n)
      NIX_FILE=$OPTARG;;
    j)
      PARAMETERS_FILE=$OPTARG;;
    h)
      usage;;
    \?)
      echo "Invalid option : -$OPTARG" >&2
      usage 1;;
  esac
done

ID=$(_JQ_SED_ -r '.id' "$PARAMETERS_FILE")

echo "Build container $ID"

in_nixos_failed "$ID"

STORE_DEFAULT="/var/lib/nixunits/store/default"
CONTAINER_DIR=$(unit_dir "$ID")

START=false
RESTART=false
ARGS+=(--impure --no-link)

mkdir -p "$CONTAINER_DIR/merged" "$CONTAINER_DIR/root/usr" "$CONTAINER_DIR/work"
chmod 2750 "$CONTAINER_DIR"
_unix_nix="$(unit_nix "$ID")"

MK_CONTAINER="(builtins.getFlake \"path:_NIXUNITS_PATH_SED_\").lib.x86_64-linux.mkContainer"

properties='{\"id\": \"dummy\"}'

cmd=(nix build "${ARGS[@]}" --store "$STORE_DEFAULT/root" \
     --expr "($MK_CONTAINER {configFile = $NIX_FILE; propertiesJSON = \"$properties\";})")

if [ "${DEBUG:-false}" = true ]; then
  echo "${cmd[@]}"
fi
"${cmd[@]}"

cleanup() {
  umount "$CONTAINER_DIR/merged"
}

mount -t overlay overlay -o "lowerdir=${STORE_DEFAULT}/root,upperdir=$CONTAINER_DIR/root,workdir=$CONTAINER_DIR/work" "$CONTAINER_DIR/merged"
trap cleanup EXIT

properties="builtins.readFile $PARAMETERS_FILE"

cmd=(nix build --print-out-paths "${ARGS[@]}" --store "$CONTAINER_DIR/merged" \
     --expr "($MK_CONTAINER {configFile = $NIX_FILE; propertiesJSON = $properties;})")

if [ "${DEBUG:-false}" = true ]; then
  echo "${cmd[@]}"
fi

RESULT_PATH="$("${cmd[@]}")"

_ln_src="${CONTAINER_DIR}/root$(readlink -f "${CONTAINER_DIR}/root${RESULT_PATH}/etc/nixunits/$ID.conf")"
_ln_dst="$CONTAINER_DIR/unit.conf"
ln -fs "$_ln_src" "$_ln_dst"

# TODO clea/rm WAL db store (sqlite)
_unit="nixunits@$ID"
STARTED=$(systemctl show "$_unit" --no-pager |grep ^SubState=running >/dev/null && echo true || echo false)
if $START && ! $STARTED || $RESTART
then
  echo "systemctl restart $_unit"
  systemctl restart "$_unit"
  systemctl status  "$_unit" --no-pager
fi
