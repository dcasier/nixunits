#!/bin/bash
set -e

. _NIXUNITS_PATH_SED_/bin/common.sh

usage() {
  echo "Usage : nixunits delete <container id> [options]"
  echo "Available options:"
  echo "  -f          force ?"
  echo "  -r          recursive ?"
  echo "  -h, --help"
  echo

  test -n "$1" && exit "$1"
  exit 0
}

[[ "$1" =~ ^(-h|--help)$ ]] && usage 0
test $# -eq 0 && usage 1
ID=$1
shift

FORCE=false
RECURSIVE=false

uid_del() {
  if grep -q "^$ID " "$UID_INV"; then
    sed -i "s/^$ID /__FREE__ /" "$UID_INV"
  fi
}

while getopts "fhr" opt; do
  case $opt in
    f)
      FORCE=true;;
    r)
      RECURSIVE=$OPTARG;;
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

_NIXUNITS_PATH_SED_/bin/disable.sh "$ID"
systemctl stop "nixunits@$ID.service"

lock_acquire
if $RECURSIVE
then
  # set -ex
  rm -fr "$CONTAINER_DIR"
  uid_del
else
  # set -ex
  find "$CONTAINER_DIR" -maxdepth 1 -type f,l | while read -r file
  do
    rm "$file"
  done
  if [ "$(find "$CONTAINER_DIR" |wc -l)" = 2 ];then
    rmdir "$(unit_root "$ID")"
    rmdir "$CONTAINER_DIR"
    uid_del
  fi
fi
lock_release
