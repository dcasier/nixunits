#!/bin/bash
set -e

. _NIXUNITS_PATH_SED_/bin/common.sh

usage() {
  echo "Usage : nixunits nsenter|shell <container id> [options] [command...]"
  echo "Available options:"
  echo "  -n  enter the network namespace only"
  echo "  -q  quiet"
  echo "  -h  help"
  echo

  test -n "$1" && exit "$1"
  exit 0
}

id="$1"
shift
id_check "$id"

NET=false
QUIET=false

while getopts "qnh" opt; do
  case $opt in
    n)
      NET=true;;
    q)
      QUIET=true;;
    h)
      usage;;
    \?)
      echo "Invalid option : -$OPTARG" >&2
      usage 1;;
  esac
done
shift $((OPTIND - 1))

if [ "${NET:-false}" = true ]
then
  _args=$(shell_netns "$id")
else
  _args=$(shell_args "$id")
fi

test $QUIET == "false" && echo "[ Container ($(pid_leader "$id")) ]" >&2
if test -z "$*"
then
  # shellcheck disable=SC2086
  nsenter $_args
else
  # shellcheck disable=SC2086
  nsenter $_args "$@"
fi