#!/bin/bash
set -e

. NIXUNITS/bin/common.sh

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

id=$1
test -z "$id" && usage 1
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

[ -z "$id" ] && echo "Container id missed" && exit 1

CONTAINER_DIR=$(unit_dir "$id")

if ! $FORCE
then
  in_nixos_failed "$id"
  read -n 1 -p "Delete $CONTAINER_DIR ? [y/N] : " AGREE
  if ! expr "$AGREE" : '[yY]' >/dev/null
  then
      exit 0
  fi
fi

echo
systemctl stop "nixunits@$id"

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
    rmdir "$(unit_root "$id")"
    rmdir "$CONTAINER_DIR"
  fi
fi

if $GC
then
  nix-store --gc
fi
