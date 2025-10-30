#!/bin/bash
set -euo pipefail

. _NIXUNITS_PATH_SED_/bin/common.sh

usage() {
  echo "Usage : nixunits build [options]"
  echo "Available options:"
  echo "  -d  debug (show-trace)"
  echo "  -e  enable service"
  echo "  -n  Nix config file"
  echo "  -j  JSON parameters file"
  echo "  -h  help"
  echo "  -r  restart ?"
  echo "  -s  start ?"
  echo

  test -n "$1" && exit "$1"
  exit 0
}

test -z "$1" && usage 1
test "$1" = "-h" && usage 0
test "$1" = "--help" && usage 0

ENABLE=false
START=false
RESTART=false
DEBUG=false
ARGS=()
while getopts "den:j:hsr" opt; do
  case $opt in
    d)
      DEBUG=true
      ARGS=("--show-trace")
      ;;
    e)
      ENABLE=true;;
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
shift "$((OPTIND-1))"

if [ $# -ne 0 ]; then
  echo "Invalid parameters '$1'." >&2
  usage 1
fi

ID=$(_JQ_SED_ -r '.id' "$PARAMETERS_FILE")

echo "Build container $ID"

in_nixos_failed "$ID"

STORE_DEFAULT="/var/lib/nixunits/store/default"
CONTAINER_DIR=$(unit_dir "$ID")

ARGS+=(--impure --no-link)

mkdir -p "$STORE_DEFAULT/root" "$CONTAINER_DIR/merged" "$CONTAINER_DIR/root/usr" "$CONTAINER_DIR/work"
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


DB="$CONTAINER_DIR/root/nix/var/nix/db/"

cleanup() {
  umount "$CONTAINER_DIR/merged"
  test -d "${DB}/*" && rm "${DB}/*" || true
}

test -d "${DB}/*" && rm "${DB}/*" || true

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

_unit="nixunits@${ID}.service"
_unit_net="nixunits-network@${ID}.service"

if [ "$ENABLE" = true ];then
  set -x
  if grep -q '^ID=nixos' /etc/os-release; then
    SYSTEMD_PATH="/run/systemd/system"
    echo "WARNING: NixOS env, temporary manual activation"
  else
    SYSTEMD_PATH="/etc/systemd/system"
  fi

  mkdir -p "${SYSTEMD_PATH}/machine-${ID}.scope.wants" ${SYSTEMD_PATH}/multi-user.target.wants/
  ln -fs "${SYSTEMD_PATH}/nixunits-network@.service" "${SYSTEMD_PATH}/$_unit_net"
  ln -fs "${SYSTEMD_PATH}/nixunits-network@.service" "${SYSTEMD_PATH}/machine-${ID}.scope.wants/$_unit_net"
  ln -fs "${SYSTEMD_PATH}/nixunits@.service" "${SYSTEMD_PATH}/$_unit"
  ln -fs "${SYSTEMD_PATH}/nixunits@.service" "${SYSTEMD_PATH}/multi-user.target.wants/$_unit"
  systemctl daemon-reload
fi

STARTED=$(systemctl show "$_unit" --no-pager |grep ^SubState=running >/dev/null && echo true || echo false)
if [ "$START" = true ] &&  [ "$STARTED" != true ] || [ "$RESTART" = true ]
then
  systemctl restart "$_unit"
  systemctl status  "$_unit" --no-pager
fi
