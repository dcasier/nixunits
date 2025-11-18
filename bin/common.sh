PATH="__AWK_BIN_SED__:__FIND_BIN_SED__:__GREP_BIN_SED__:__INOTIFY_BIN_SED__:__PSTREE_BIN_SED__:__SYSTEMD_BIN_SED__:/run/current-system/sw/bin/:$PATH"
export PATH

PATH_NIXUNITS="/var/lib/nixunits"
GCROOTS_CONTAINERS="$PATH_NIXUNITS/gcroots"
LOCKFILE="${PATH_NIXUNITS}/.lock"
PATH_CONTAINERS="$PATH_NIXUNITS/containers"
STORE_CONTAINERS="$PATH_NIXUNITS/store/default/root"
SYSTEM=$(nix eval --impure --expr 'builtins.currentSystem' --raw)
UID_INV="$PATH_NIXUNITS/uidmap"
export GCROOTS_CONTAINERS LOCKFILE PATH_NIXUNITS STORE_CONTAINERS SYSTEM UID_INV

container_env() {
  CONTAINER_DIR=$(unit_dir "$1")
  C_TMP="$CONTAINER_DIR/tmp"
  C_FUTUR="$C_TMP/root_futur"
  C_FUTUR_ARGS="$C_FUTUR/parameters.json"
  C_FUTUR_OK="$C_FUTUR/.complete"
  C_FUTUR_NIX="$C_FUTUR/configuration.nix"
  CONTAINER_ARGS="$CONTAINER_DIR/parameters.json"
  CONTAINER_LOCK="$CONTAINER_DIR/.lock"
  CONTAINER_META="$CONTAINER_DIR/.unit_hash"
  CONTAINER_NIX="$CONTAINER_DIR/configuration.nix"
  CONTAINER_OLD="$C_TMP/root_old"
  CONTAINER_OK="$CONTAINER_DIR/.complete"
  CONTAINER_ROOT="$CONTAINER_DIR/root"
  export CONTAINER_ARGS C_BUILD_OK CONTAINER_DIR CONTAINER_OK \
        C_FUTUR C_FUTUR_OK C_FUTUR_ARGS \
        C_FUTUR_NIX CONTAINER_LOCK \
        CONTAINER_META CONTAINER_ROOT C_TMP \
        CONTAINER_OLD CONTAINER_NIX
}

hash_ctx() {
  NIXPKGS_REV="$(
    nix flake metadata "_NIXUNITS_PATH_SED_" --json \
    | jq -r '.locks.nodes.nixpkgs.locked.rev'
  )"
  echo "${SYSTEM}-${NIXPKGS_REV}"
}

hash_with() {
  hash_=$(sha1sum "$1" | cut -d' ' -f1)
  echo "${2}-${hash_}" | sha1sum | cut -d' ' -f1
}

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
      echo "Error: Container declared by NixOS"
      exit 1
    fi
  fi
}

ip6_crc32() { echo "$(_ip6_crc32 "$1"):2"; }

ip6_crc32_host() { echo "$(_ip6_crc32 "$1"):1"; }


is_url() {
    case "$1" in
        http://*|https://*) return 0;;
        *) return 1;;
    esac
}

lock_acquire() {
    local lock_path="${1:-$LOCKFILE}"

    while ! ln -s "$$" "$lock_path" 2>/dev/null; do
        pid=$(readlink "$lock_path" 2>/dev/null)
        if [ -n "$pid" ] && ! kill -0 "$pid" 2>/dev/null; then
            rm -f "$lock_path"
            continue
        fi
        sleep 0.1
    done
    echo "Lock acquired: $lock_path by $$"
}

lock_release() {
    local lock_path="${1:-$LOCKFILE}"
    pid=$(readlink "$lock_path" 2>/dev/null)
    [ "$pid" = "$$" ] && rm -f "$lock_path"
    echo "Lock lock_release: $lock_path by $$"
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

unit_dir() { echo "$PATH_CONTAINERS/$1"; }
uid_root() {
  skip="$(awk -v id="$1" '$1==id {print $2}' "$UID_INV")"
  [ "$skip" != "" ] && echo $(( $skip * 65536))
}

unit_conf() { echo "$(unit_dir "$1")/unit.conf"; }
unit_root() { echo "$(unit_dir "$1")/root/"; }

_ip6_crc32() {
  _crc32=$(echo -n "$1" | gzip -c | tail -c8 | head -c4 | hexdump -e '"%01x"')
  echo "fc00::${_crc32:0:4}:${_crc32:4:8}"
}