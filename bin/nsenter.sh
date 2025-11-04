#!/bin/bash
set -e

. _NIXUNITS_PATH_SED_/bin/common.sh

ID="$1"
shift

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
  _args=$(shell_netns "$ID")
else
  _args=$(shell_args "$ID")
fi

test $QUIET != "false" && echo "[ Container ($(pid_leader "$ID")) ]" >&2
if test -z "$*"
then
  # shellcheck disable=SC2086
  nsenter $_args
else
  # shellcheck disable=SC2086
  nsenter $_args "$@"
fi