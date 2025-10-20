_VAR="/var/lib/nixunits/containers"

if [ -n "${1-}" ]; then
  NAME="$1"
fi

unit_dir() { echo "$_VAR/$NAME"; }

unit_conf() { echo "$(unit_dir "$NAME")/unit.conf"; }
unit_nix() { echo "$(unit_dir "$NAME")/unit.nix"; }
unit_root() { echo "$(unit_dir "$NAME")/root/"; }

in_nixos() {
   test "$(dirname "$(readlink "$(unit_conf "$NAME")")")" = "/etc/nixunits"
}

in_nixos_failed() {
  if [ -d "$(unit_dir "$NAME")" ]
  then
    if in_nixos "$NAME"
    then
      echo "Error: Container declared by NixOS (use -f [force])"
      exit 1
    fi
  fi
}

ip6_crc32() { echo "$(_ip6_crc32 "$NAME"):2"; }

ip6_crc32_host() { echo "$(_ip6_crc32 "$NAME"):1"; }

log() { echo "$(unit_dir "$NAME")/unit.log"; }

pid_leader() {
  machinectl show "$NAME" --no-pager |grep Leader |cut -d'=' -f2
}

# shellcheck disable=SC2046
shell_args() {
  echo --target $(pid_leader "$NAME") --mount --uts --ipc --net --pid --user;
}

shell_exist() {
  pgrep -f "nsenter $(shell_args "$NAME")" >/dev/null
}

_ip6_crc32() {
  _crc32=$(echo -n "$NAME" | gzip -c | tail -c8 | head -c4 | hexdump -e '"%01x"')
  echo "fc00::${_crc32:0:4}:${_crc32:4:8}"
}