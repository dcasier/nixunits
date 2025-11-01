#!/bin/bash
set -e

. _NIXUNITS_PATH_SED_/bin/common.sh

usage() {
  echo "Usage : nixunits delete <container id> [options]"
  echo "Available options:"
  echo "  -f          force ?"
  echo "  -g          garbage collector ?"
  echo "  -r          recursive ?"
  echo "  -h, --help"
  echo

  test -n "$1" && exit "$1"
  exit 0
}

ID=$1

if [ "$ID" = "-h" ] || [ "$ID" = "--help" ]; then
  usage
fi

test -z "$ID" && usage 1
shift

FORCE=false
RECURSIVE=false
GC=false

while getopts "fghr" opt; do
  case $opt in
    f)
      FORCE=true;;
    r)
      RECURSIVE=$OPTARG;;
    g)
      GC=$OPTARG;;
    h)
      usage;;
    \?)
      echo "Invalid option : -$OPTARG" >&2
      usage 1;;
  esac
done

[ -z "$ID" ] && echo "Container id missed" && exit 1

CONTAINER_DIR=$(unit_dir "$ID")

if ! $FORCE
then
  in_nixos_failed "$ID"
  read -rn 1 -p "Delete $CONTAINER_DIR ? [y/N] : " AGREE
  if ! expr "$AGREE" : '[yY]' >/dev/null
  then
      exit 0
  fi
fi

echo
_unit="nixunits@$ID.service"
_unit_net="nixunits-network@$ID.service"

if grep -q '^ID=nixos' /etc/os-release; then
  SYSTEMD_PATH="/run/systemd/system"
else
  SYSTEMD_PATH="/etc/systemd/system"
fi

test -f "${SYSTEMD_PATH}/multi-user.target.wants/$_unit" && rm "${SYSTEMD_PATH}/multi-user.target.wants/$_unit" || true
test -f "${SYSTEMD_PATH}/machine-${ID}.scope.wants/$_unit_net" && rm "${SYSTEMD_PATH}/machine-${ID}.scope.wants/$_unit_net" || true
test -d "${SYSTEMD_PATH}/machine-${ID}.scope.wants" && rmdir "${SYSTEMD_PATH}/machine-${ID}.scope.wants" || true

systemctl stop "$_unit"

if $RECURSIVE
then
  # set -ex
  rm -fr "$CONTAINER_DIR"
else
  # set -ex
  find "$CONTAINER_DIR" -maxdepth 1 -type f,l | while read -r file
  do
    rm "$file"
  done
  if [ "$(find "$CONTAINER_DIR" |wc -l)" = 2 ];then
    rmdir "$(unit_root "$ID")"
    rmdir "$CONTAINER_DIR"
  fi
fi

if $GC
then
  nix-store --gc
fi
