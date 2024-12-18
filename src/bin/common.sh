_VAR="/var/lib/nixunits/containers"


fileConf() {
  echo "$_VAR/$1/unit.conf"
}

in_nixos() {
   test "$(dirname $(readlink $(fileConf $1)))" = "/etc/nixunits"
}

in_nixos_failed() {
  if [ -d "$(out_var $1)" ]
  then
    if in_nixos "$1"
    then
      echo "Error: Container declared by NixOS (use -f [force])"
      exit 1
    fi
  fi
}

ip6_crc32() {
  echo "$(_ip6_crc32 $1):2"
}

ip6_crc32_host() {
  echo "$(_ip6_crc32 $1):1"
}

log() {
  echo "$_VAR/$1/unit.log"
}

out_var() {
  echo "$_VAR/$1"
}

_ip6_crc32() {
  _crc32=$(echo -n "$1" | gzip -c | tail -c8 | head -c4 | hexdump -e '"%01x"')
  echo "fc00::${_crc32:0:4}:${_crc32:4:8}"
}