_VAR="/var/lib/nixunits/containers"

unit_dir() { echo "$_VAR/$1"; }

unit_conf() { echo "$(unit_dir "$1")/unit.conf"; }
unit_nix() { echo "$(unit_dir "$1")/unit.nix"; }
unit_root() { echo "$(unit_dir "$1")/root/"; }

in_nixos() {
   test "$(dirname "$(readlink "$(unit_conf "$1")")")" = "/etc/nixunits"
}

in_nixos_failed() {
  if [ -d "$(unit_dir "$1")" ]
  then
    if in_nixos "$1"
    then
      echo "Error: Container declared by NixOS (use -f [force])"
      exit 1
    fi
  fi
}

ip6_crc32() { echo "$(_ip6_crc32 "$1"):2"; }

ip6_crc32_host() { echo "$(_ip6_crc32 "$1"):1"; }

log() { echo "$(unit_dir "$1")/unit.log"; }

pid_leader() {
  machinectl show "$1" --no-pager |grep Leader |cut -d'=' -f2
}

# shellcheck disable=SC2046
shell_args() {
  echo --target $(pid_leader "$1") --mount --uts --ipc --net --pid --user;
}

shell_exist() {
  pgrep -f "nsenter $(shell_args "$1")" >/dev/null
}

_ip6_crc32() {
  _crc32=$(echo -n "$1" | gzip -c | tail -c8 | head -c4 | hexdump -e '"%01x"')
  echo "fc00::${_crc32:0:4}:${_crc32:4:8}"
}