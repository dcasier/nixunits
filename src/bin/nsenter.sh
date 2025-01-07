#!/bin/sh
set -e

. NIXUNITS/bin/common.sh

shift

echo >&2 " - - - WARNING - - - "
echo >&2 "Remember to exit the shell before stopping container"
echo >&2 " - - - WARNING - - - "

_args=$(shell_args "$1")

if test -z "$*"
then
  # shellcheck disable=SC2086
  nsenter $_args
else
  # shellcheck disable=SC2086
  nsenter $_args "$@"
fi