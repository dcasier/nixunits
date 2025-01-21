#!/bin/bash
set -e

. NIXUNITS/bin/common.sh

ID="$1"
shift

_args=$(shell_args "$ID")

if test -z "$*"
then
  echo >&2 " - - - WARNING  Remember to exit the shell before stopping container WARNING - - - "
  # shellcheck disable=SC2086
  nsenter $_args
else
  # shellcheck disable=SC2086
  nsenter $_args "$@"
fi