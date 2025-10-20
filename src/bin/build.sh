#!/bin/bash
set -e

. NIXUNITS/bin/common.sh

usage() {
  echo "Usage : nixunits build <container id> [options]"
  echo "Available options:"
  echo "  -a  <json list> capabilities allowed"
  echo "  -bw  <json list> bind"
  echo "  -cc <service config content>"
  echo "  -cf <service file>"
  echo "  -p <JSON properties>"
  echo "  -i  <interface>"
  echo "  -ni  <netns uuid>"
  echo "  -np  <netns path>"
  echo "  -4  <IPv4>"
  echo "  -H4 <host IPv4>"
  echo "  -R4 <IPv4 route>"
  echo "  -6  [IPv6] "
  echo "  -H6 <host IPv6>"
  echo "  -R6 <IPv6 route>"
  echo "  -f  force ?"
  echo "  -h, --help"
  echo "  -r  restart ?"
  echo "  -s  start ?"
  echo
  echo "Examples:"
  echo
  echo " nixunits build my_wordpress -cc - -6 '2001:bc8:a:b:c:d:e:1/64' -i link1 -R6 'fe80::1' <<EOF
{ lib, pkgs, ... }: {
  services = {
    mysql.enable = true;
    wordpress.sites.\"localhost\" = {};
  };
}
EOF"
  echo
  echo " nixunits build my_pg1 -cc \"\$CONTENT\" -6 'fc00::a:2' -H6 'fc00::a:1'"
  echo " nixunits build my_pg2 -cf ./my_wordpress.nix -4 192.168.1.1 -R4 192.168.1.254"
  echo
  echo "Auto generated IPv6, from name (private network only):"
  echo " nixunits build my_nc -cf ./my_wordpress.nix -6"
  echo
  echo " nixunits build mysql -cf ./my_wordpress.nix -6 -s -a '[\"CAP_DAC_OVERRIDE\"]'"

  test -n "$1" && exit "$1"
  exit 0
}

id=$1
test -z "$id" && usage 1
test "$id" = "-h" && usage 0
test "$id" = "--help" && usage 0
shift

FORCE=false
START=false
RESTART=false

# shellcheck disable=SC2213
while getopts "4:6a:b:c:p:f:i:n:H:R:hsr" opt; do
  case $opt in
    4)
      ip4=$OPTARG;;
    6)
      # shellcheck disable=SC2124
      next_arg="${@:$OPTIND:1}"
      if [[ -n $next_arg && $next_arg != -* ]] ; then
        ip6=$next_arg
        OPTIND=$((OPTIND + 1))
      else
        ip6=$(ip6_crc32 "$id")
        hostIp6=$(ip6_crc32_host "$id")
      fi;;
    a)
      CAPS=$OPTARG;;
    b)
      bind=$OPTARG;;
    c)
      case $OPTARG in
        c) serviceContent="${!OPTIND}"; OPTIND=$((OPTIND + 1))
          test "$serviceContent" == "-" && serviceContent=$(cat);;
        f) serviceFile="${!OPTIND}"; OPTIND=$((OPTIND + 1));;
        *) echo "Invalid option for -s. Use c or f."; usage 1;;
      esac
      ;;
    p)
      properties=$OPTARG;;
    i)
      interface=$OPTARG;;
    n)
      case $OPTARG in
        i) netns_uuid="${!OPTIND}"; OPTIND=$((OPTIND + 1));;
        p) netns_path="${!OPTIND}"; OPTIND=$((OPTIND + 1));;
        *) echo "Invalid option for -n"; usage 1;;
      esac
      ;;
    r)
      RESTART=true;;
    s)
      START=true;;
    H)
      case $OPTARG in
        4) hostIp4="${!OPTIND}"; OPTIND=$((OPTIND + 1));;
        6) hostIp6="${!OPTIND}"; OPTIND=$((OPTIND + 1));;
        *) echo "Invalid option for -H. Use 4 or 6."; usage 1;;
      esac
      ;;
    R)
      case $OPTARG in
        4) ip4route="${!OPTIND}"; OPTIND=$((OPTIND + 1));;
        6) ip6route="${!OPTIND}"; OPTIND=$((OPTIND + 1));;
        *) echo "Invalid option for -R. Use 4 or 6."; usage 1;;
      esac
      ;;
    f)
      FORCE=true;;
    h)
      usage;;
    \?)
      echo "Invalid option : -$OPTARG" >&2
      usage 1;;
  esac
done

test "$FORCE" != "true" && in_nixos_failed "$id"

CONTAINER_DIR=$(unit_dir "$id")

mkdir -p "$CONTAINER_DIR/root/usr"
chmod 2750 "$CONTAINER_DIR"

_args=(--argstr id "$id")
if [ -n "$serviceFile" ] || [ -n "$serviceContent" ]
then
  _unix_nix="$(unit_nix "$id")"
  if [ -n "$serviceFile" ]
  then
    install "$serviceFile" "$_unix_nix"
  else
    echo "$serviceContent" > "$_unix_nix"
  fi
fi

[ -n "$CAPS" ]        && _args+=(--argstr caps_allow "$CAPS")
[ -n "$hostIp4" ]     && _args+=(--argstr hostIp4 "$hostIp4")
[ -n "$hostIp6" ]     && _args+=(--argstr hostIp6 "$hostIp6")
[ -n "$interface" ]   && _args+=(--argstr interface "$interface")
[ -n "$ip4" ]         && _args+=(--argstr ip4 "$ip4")
[ -n "$ip6" ]         && _args+=(--argstr ip6 "$ip6")
[ -n "$ip4route" ]    && _args+=(--argstr ip4route "$ip4route")
[ -n "$ip6route" ]    && _args+=(--argstr ip6route "$ip6route")
[ -n "$properties" ]  && _args+=(--argstr properties "$properties")
[ -n "$bind" ]        && _args+=(--argstr bind "$bind")

if [ -n "$netns_path" ]; then
  if [ -n "$hostIp4" ] || [ -n "$hostIp6" ] || [ -n "$interface" ] || [ -n "$ip4" ] || [ -n "$ip6" ] || [ -n "$ip4route" ] || [ -n "$ip6route" ]
  then
    echo "netns option cannot be used together with other network-related options"
    usage 1
  fi
  _args+=(--argstr netns_path "$netns_path")
fi

_args+=(--out-link "$CONTAINER_DIR/result")

echo "Container : $id"
test -n "$interface" && echo "  interface: $interface"
test -n "$ip4"       && echo "  ip4: $ip4"
test -n "$ip4route"  && echo "  ip4route: $ip4route"
test -n "$hostIp4"   && echo "  hostIp4: $hostIp4"
test -n "$ip6"       && echo "  ip6: $ip6"
test -n "$hostIp6"   && echo "  hostIp6: $hostIp6"
test -n "$ip6route"  && echo "  ip6route: $ip6route"
test -n "$netns_uuid"  && echo "  netns_uuid: $netns_uuid"
echo

echo "nix-build NIXUNITS/default.nix" "${_args[@]}"
# shellcheck disable=SC2086
nix-build NIXUNITS/default.nix "${_args[@]}"

_link="$CONTAINER_DIR/unit.conf"
test -L "$_link" || ln -s "$CONTAINER_DIR/result/etc/nixunits/$id.conf" "$_link"

_unit="nixunits@$id"
STARTED=$(systemctl show "$_unit" --no-pager |grep ^SubState=running >/dev/null && echo true || echo false)
if $START && ! $STARTED || $RESTART
then
  echo "systemctl restart $_unit"
  systemctl restart "$_unit"
  systemctl status  "$_unit" --no-pager
fi