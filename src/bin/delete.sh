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
  exit 0
}

id=$1
test -z "$id" && usage 1
shift

FORCE=false
RECURSIVE=false
GC=false

# Analyse des options
while getopts "fghr" opt; do
  case $opt in
    f) FORCE=true;;
    r) RECURSIVE=$OPTARG;;
    g) GC=$OPTARG;;
    h)
      usage
      ;;
    \?)
      echo "Invalid option : -$OPTARG" >&2
      usage
      ;;
  esac
done

[ -z "$id" ] && echo "Container id missed" && exit 1

OUT_VAR=$(out_var "$id")

if ! $FORCE
then
  in_nixos_failed "$id"
  read -n 1 -p "Delete $OUT_VAR ? [y/N] : " AGREE
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
  rm -fr "$OUT_VAR"
else
  # set -ex
  find "$OUT_VAR" -maxdepth 1 -type f,l | while read -r file
  do
    rm "$file"
  done
  test "$(find "$OUT_VAR" |wc -l)" = 1 && rmdir "$OUT_VAR"
fi

if $GC
then
  nix-store --gc
fi
