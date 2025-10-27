#!/bin/bash
set -e

. _NIXUNITS_PATH_SED_/bin/common.sh

ID="$1"
shift

_args=$(shell_args "$ID")

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