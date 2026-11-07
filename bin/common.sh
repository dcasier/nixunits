PATH="__AWK_BIN_SED__:__FIND_BIN_SED__:__GREP_BIN_SED__:__INOTIFY_BIN_SED__:__PSTREE_BIN_SED__:__SYSTEMD_BIN_SED__:/run/current-system/sw/bin/:/nix/var/nix/profiles/per-user/root/profile/bin:$PATH"
# which nix >/dev/null || PATH="/nix/var/nix/profiles/per-user/root/profile/bin:$PATH"

export PATH

PATH_NIXUNITS="/var/lib/nixunits"
GCROOTS_CONTAINERS="$PATH_NIXUNITS/gcroots"
LOCKFILE="${PATH_NIXUNITS}/.lock"
PATH_CONTAINERS="$PATH_NIXUNITS/containers"
STORE_CONTAINERS="$PATH_NIXUNITS/store/default/root"
# Substituted when the package is built (see nixunits.nix)
SYSTEM="_SYSTEM_SED_"
UID_INV="$PATH_NIXUNITS/uidmap"
NIXPKGS_REV="_NIXPKGS_REV_SED_"
NIXUNITS_VERSION="_NIXUNITS_VERSION_SED_"
NIXUNITS_REV="_NIXUNITS_REV_SED_"
# Hash of the nixunits sources that generate the container (see nixunits.nix)
NIXUNITS_GEN_HASH="_NIXUNITS_GEN_HASH_SED_"

# Global modules (/var/lib/nixunits/modules/*.nix) are imported by every
# container: they must invalidate the build like the config file does
modules_hash() {
  local dir="$PATH_NIXUNITS/modules"
  [ -d "$dir" ] || { echo "none"; return 0; }
  find "$dir" -maxdepth 1 -type f -name '*.nix' -print0 \
    | sort -z | xargs -0 -r sha1sum | sha1sum | cut -d' ' -f1
}
ENV_HASH="${SYSTEM}-${NIXPKGS_REV}-$(modules_hash)"
export ENV_HASH GCROOTS_CONTAINERS LOCKFILE PATH_NIXUNITS STORE_CONTAINERS SYSTEM UID_INV

# Container IDs end up in filesystem paths, Nix expressions and unit names:
# no '/', quote or shell metacharacter, no leading '.' (., ..) or '-' (option)
ID_REGEX='^[A-Za-z0-9_][A-Za-z0-9._-]*$'

id_check() {
  if [[ ! "$1" =~ $ID_REGEX ]]; then
    echo "Error: invalid container id '$1' (allowed: A-Z a-z 0-9 _ . -, not starting with '.' or '-')" >&2
    exit 1
  fi
}

container_env() {
  id_check "$1"
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

hash_with() {
  hash_=$(sha1sum "$1" | cut -d' ' -f1)
  echo "${2}-${hash_}" | sha1sum | cut -d' ' -f1
}

host_exec() {
  log_msg "[    Host   ] exec $1"
  /bin/sh -c "$1"
}

INTERFACE_FIELDS=(
  ETH_TYPE
  HOST_IP4
  HOST_IP6
  IP4
  IP6
  MV
  MV_IP4
  MV_IP6
  MV_VRID
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
        sleep 0.5
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

pid_tree() {  # $1 and all its descendants
  local p
  echo "$1"
  for p in $(ps --ppid "$1" -o pid=); do
    pid_tree "$p"
  done
}

pid_in_ns_not_in_container() {
  PID_SYSTEMD=${1//[[:space:]]/}   # callers pass `ps -o pid h` output, space-padded
  ALL=$(pid_with_same_ns_find "$PID_SYSTEMD" pid)
  TREE=$(pid_tree "$PID_SYSTEMD")

  # shellcheck disable=SC2086
  comm -13 \
    <(printf "%s\n" $TREE | sort) \
    <(printf "%s\n" $ALL | sort)
}

# Processes running in the container (PID namespace) without descending from
# its init: `nixunits shell`, `nixunits nsenter ...` and the like
external_jobs() {
  local leader supervisor p
  leader=$(pid_leader "$1" 2>/dev/null) || return 0
  [ -n "$leader" ] || return 0
  supervisor=$(ps -o ppid= -p "$leader" 2>/dev/null | tr -d ' ')   # nspawn
  {
    pid_in_ns_not_in_container "$leader"
    # Entered only the network namespace (nsenter --net): outside the PID
    # namespace, it survives the container. Skipped when the container
    # shares the host network namespace (every host process would match).
    if [ "$(readlink "/proc/$leader/ns/net")" != "$(readlink /proc/$$/ns/net)" ]; then
      comm -13 <(pid_with_same_ns_find "$leader" pid | sort) \
               <(pid_with_same_ns_find "$leader" net | sort)
    fi
  } 2>/dev/null | sort -u | while read -r p; do
    [ "$p" = "$supervisor" ] && continue
    ps -o pid=,args= -p "$p" 2>/dev/null || true
  done
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

unit_dir() { id_check "$1"; echo "$PATH_CONTAINERS/$1"; }
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