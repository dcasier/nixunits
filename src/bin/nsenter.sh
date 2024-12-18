#!/bin/sh
set -e

PID=$(machinectl show "$1" --no-pager |grep Leader |cut -d'=' -f2)
shift

if test -z "$*"
then
  nsenter --target "$PID" --mount --uts --ipc --net --pid --user
else
  nsenter --target "$PID" --mount --uts --ipc --net --pid --user "$@"
fi