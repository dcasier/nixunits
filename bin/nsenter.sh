#!/bin/bash
set -e

. _NIXUNITS_PATH_SED_/bin/common.sh

ID="$1"
shift

NET=false

while getopts "nh" opt; do
  case $opt in
    n)
      NET=true;;
    h)
      usage;;
    \?)
      echo "Invalid option : -$OPTARG" >&2
      usage 1;;
  esac
done

if [ "${NET:-false}" = true ]
then
  _args=$(shell_netns "$ID")
else
  _args=$(shell_args "$ID")
fi

if test -z "$*"
then
  echo >&2 "                     - - - WARNING - - -"
  echo >&2 " - - - Remember to exit shell before stopping container - - - "
  echo >&2 "                     - - - WARNING - - - "
  # shellcheck disable=SC2086
  nsenter $_args
else
  # shellcheck disable=SC2086
  nsenter $_args "$@"
fi