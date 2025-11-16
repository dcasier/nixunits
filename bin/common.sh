PATH="__AWK_BIN_SED__:__FIND_BIN_SED__:__GREP_BIN_SED__:__INOTIFY_BIN_SED__:__PSTREE_BIN_SED__:__SYSTEMD_BIN_SED__:/run/current-system/sw/bin/:$PATH"
export PATH

PATH_CTX="/var/lib/nixunits"
PATH_CONTAINER="/var/lib/nixunits/containers"
LOCKFILE="${PATH_CTX}/.lock"
UID_INV="$PATH_CTX/uidmap"
export PATH_CTX LOCKFILE UID_INV

unit_dir() { echo "$PATH_CONTAINER/$1"; }
uid_root() {
  echo $(($(awk -v id="$1" '$1==id {print $2}' "$UID_INV") * 65536))
}

unit_conf() { echo "$(unit_dir "$1")/unit.conf"; }
unit_parameters() { echo "$(unit_dir "$1")/parameters.json"; }
unit_root() { echo "$(unit_dir "$1")/root/"; }

host_exec() {
  log_msg "[    Host   ] exec $1"
  /bin/sh -c "$1"
}

INTERFACE_FIELDS=(
  HOST_IP4
  HOST_IP6
  IP4
  IP6
  OVS_BRIDGE
  OVS_VLAN
)

interface_env() {
  export INTERFACE="$1"
  echo "Load interface - $INTERFACE -" >&2
  local var src
  for var in "${INTERFACE_FIELDS[@]}"; do
    src="NIXUNITS__ETH__${INTERFACE}__${var}"
    export "${var}=${!src}"
  done
}

interface_exists() {
  ip link show "$1" &>/dev/null || return 1
}

interfaces_list() {
  local var ifname
  for var in "${!NIXUNITS__ETH__@}"; do
    ifname="${var#NIXUNITS__ETH__}"
    echo "${ifname%%__*}"
  done | sort -u
}

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

lock_acquire() {
    while ! mkdir "$LOCKFILE" 2>/dev/null; do
        sleep 0.1
    done
}

lock_release() {
    rmdir "$LOCKFILE"
}

log() { echo "$(unit_dir "$1")/unit.log"; }

log_msg() {
  echo "$1" >&2
}

log_block_msg() {
  log_msg "########################################"
  log_msg "# $1"
  log_msg "########################################"
}

ovs_port_exists() {
    local iface=$1
    local fix=${2:-false}
    local ifindex

    ifindex=$(ovs-vsctl --if-exists get Interface "$iface" ifindex)

    if [ "${ifindex:-0}" -eq 0 ] && [ "$fix" = "true" ]; then
      ovs-vsctl set Interface "$iface" type=dummy
      ovs-vsctl set Interface "$iface" type=internal

      for _ in 1 2 3 4 5; do
        ifindex=$(ovs-vsctl --if-exists get Interface "$iface" ifindex)
        [ "${ifindex:-0}" -ne 0 ] && break
        sleep 0.1
      done
    fi

    [ -n "$ifindex" ]
}

ovs_port_del() {
  ovs-vsctl --if-exists del-port "$OVS_BRIDGE" "$1"
}

ovs_port_add() {
  if [[ -n "$OVS_VLAN" ]]; then
    ovs-vsctl add-port "$OVS_BRIDGE" "$1" tag="$OVS_VLAN" -- set interface "$1" type=internal
  else
    ovs-vsctl add-port "$OVS_BRIDGE" "$1" -- set interface "$1" type=internal
  fi
}

pid_in_ns_not_in_container() {
  PID_SYSTEMD=$1
  ALL=$(pid_with_same_ns_find "$PID_SYSTEMD" pid)
  # TREE=$(pstree -Tp "$PID_SYSTEMD" | grep -o '([0-9]\+)' | tr -d '()')
  TREE=$(pstree "$PID_SYSTEMD" | grep -o ' [0-9]\+ ' )

  # shellcheck disable=SC2086
  comm -13 \
    <(printf "%s\n" $TREE | sort -n) \
    <(printf "%s\n" $ALL | sort -n)
}

pid_with_same_ns_find() {
  PID=$1
  TYPE=$2
  find /proc -maxdepth 3 -type l -path "/proc/*/ns/$TYPE" \
    -lname "$TYPE:\[$(lsns -p "$PID" -t "$TYPE" -n \
    |awk '{print $1}')\]" |cut -d'/' -f3
}

pid_leader() {
  # machinectl show "$1" --no-pager |grep ^Leader= |cut -d'=' -f2

  machinectl show "$1" -p Leader --value
}

# shellcheck disable=SC2046
shell_args() {
  echo --target $(pid_leader "$1") --mount --uts --ipc --net --pid --user;
}

shell_exist() {
  pgrep -f "nsenter $(shell_args "$1")" >/dev/null
}

shell_netns() {
  echo --target "$(pid_leader "$1")" --net;
}

_ip6_crc32() {
  _crc32=$(echo -n "$1" | gzip -c | tail -c8 | head -c4 | hexdump -e '"%01x"')
  echo "fc00::${_crc32:0:4}:${_crc32:4:8}"
}