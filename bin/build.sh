#!/bin/bash
set -euo pipefail

. _NIXUNITS_PATH_SED_/bin/common.sh

usage() {
  echo "Usage : nixunits build [options]"
  echo "Available options:"
  echo "  -d  debug (show-trace)"
  echo "  -f  force (build)"
  echo "  -n  Nix config file"
  echo "  -j  JSON parameters file"
  echo "  -h  help"
  echo "  -r  restart ?"
  echo "  -s  start ?"
  echo

  test -n "$1" && exit "$1"
  exit 0
}

test $# -eq 0 && usage 1
[[ "$1" =~ ^(-h|--help)$ ]] && usage 0

DEBUG=false
FORCE=false
ARGS=(--impure)
STARTS_ARGS=()

while getopts "defn:j:hsr" opt; do
  case $opt in
    d) DEBUG=true; ARGS+=("--show-trace");;
    f) FORCE=true;;
    r) STARTS_ARGS+=(-s -r);;
    s) STARTS_ARGS+=(-s);;
    n) NIX_FILE=$OPTARG;;
    j) PARAMS_FILE=$OPTARG;;
    h) usage;;
    *) usage 1;;
  esac
done
shift "$((OPTIND-1))"

if [ -z "${NIX_FILE:-}" ] || [ -z "${PARAMS_FILE:-}" ]; then
    echo "Args missing" >&2
    usage 1
fi

id=$(_JQ_SED_ -r '.id' "$PARAMS_FILE")
in_nixos_failed "$id"
container_env "$id"

if [[ "$CONTAINER_DIR" != *var*nixunits* ]]; then
    echo "INTERNAL ERROR : invalid value for CONTAINER_DIR ${CONTAINER_DIR}" >&2
    exit 1
fi

mkdir -p "$CONTAINER_DIR"
chmod 2750 "$CONTAINER_DIR"

MK_CONTAINER="(builtins.getFlake \"path:_NIXUNITS_PATH_SED_\").lib.${SYSTEM}.mkContainer"

cleanup() {
  if mountpoint -q "$C_TMP/merged/nix/var/nix"; then
    umount "$C_TMP/merged/nix/var/nix" 2>/dev/null || umount -lf "$C_TMP/merged/nix/var/nix" 2>/dev/null
  fi
  if mountpoint -q "$C_TMP/merged"; then
    umount "$C_TMP/merged" 2>/dev/null || umount -lf "$C_TMP/merged" 2>/dev/null
  fi
  lock_release "$CONTAINER_LOCK"
}

uid_alloc() {
    if [ ! -f "$UID_INV" ];then
        # between 524288 and 1878982656
        echo "$id 1024" > "$UID_INV"
    fi

    UID_SHIFT_INDEX=$(awk -v id="$id" '$1==id {print $2}' "$UID_INV")
    if [ -z "$UID_SHIFT_INDEX" ]; then
      UID_SHIFT_INDEX=$(awk '/^__FREE__/ {print $2; exit}' "$UID_INV")
      if [ -n "$UID_SHIFT_INDEX" ]; then
          sed -i "0,/^__FREE__/s//${id} ${UID_SHIFT_INDEX}/" "$UID_INV"
      else
        last_uid=$(awk '{print $2}' "$UID_INV" | tail -1)
        UID_SHIFT_INDEX=$((last_uid + 1))
        echo "$id $UID_SHIFT_INDEX" >> "$UID_INV"
      fi
    fi
}

build_store() {
  GCROOT_PATH="$GCROOTS_CONTAINERS/$1"
  local props='{\"id\": \"dummy\"}'
  local cmd=(nix build "${ARGS[@]}" --out-link "$GCROOT_PATH" --store "$STORE_CONTAINERS" \
               --expr  "($MK_CONTAINER {configFile = $NIX_FILE; propertiesJSON = \"$props\";})")

  echo "Build store for $id"
  [ "$DEBUG" = true ] && echo "${cmd[@]}"
  "${cmd[@]}"

  mkdir -p "$GCROOTS_CONTAINERS"
  ln -Tfs "$GCROOT_PATH" "$CONTAINER_DIR/store"
}

build_container() {
  test -f "$CONTAINER_FUTUR_OK" && rm "$CONTAINER_FUTUR_OK"
  rm -rf "$C_TMP"
  mkdir -p "$CONTAINER_FUTUR" "$C_TMP/work" "$C_TMP/merged" "$C_TMP/logs"

  mount -t overlay overlay -o "lowerdir=$STORE_CONTAINERS,upperdir=$CONTAINER_FUTUR,workdir=$C_TMP/work" "$C_TMP/merged"
  mkdir -p "$C_TMP/merged/nix/var/nix"
  mount -t tmpfs tmpfs "$C_TMP/merged/nix/var/nix"
  rsync -a --exclude=temproots "$STORE_CONTAINERS/nix/var/nix/" "$C_TMP/merged/nix/var/nix/"

  local props="builtins.readFile $PARAMS_FILE"
  local cmd=(nix build --no-link --print-out-paths "${ARGS[@]}" --store "$C_TMP/merged" \
               --expr  "($MK_CONTAINER {configFile = $NIX_FILE; propertiesJSON = $props;})")

  echo "Build container $id"
  [ "$DEBUG" = true ] && echo "${cmd[@]}"
  RESULT_PATH="$("${cmd[@]}")"

  conf_path="$CONTAINER_FUTUR/$RESULT_PATH/etc/nixunits/$id.conf"
  conf_target=$(readlink -f "$conf_path") || {
    echo "INTERNAL ERROR : Failed get $conf_path" >&2
    exit 1
  }
  ln -fs "$CONTAINER_DIR/root$conf_target" "$CONTAINER_FUTUR/unit.conf"
  cp "$PARAMS_FILE" "$CONTAINER_FUTUR/parameters.json"
  echo "$1" > "$CONTAINER_META"
  touch "$CONTAINER_FUTUR_OK"
}

S=$(_NIXUNITS_PATH_SED_/bin/status.sh "$id" -j "$PARAMS_FILE" -n "$NIX_FILE")
need_update=$(echo "$S" | jq -r .need_update)
need_build_container=$(echo "$S" | jq -r .need_build_container)

if [ "$FORCE" = true ] || [ "$need_update" = true ];then
  lock_acquire
  trap lock_release EXIT
  uid_alloc
  build_store "$(echo "$S" | jq -r .store_hash)"
  lock_release
fi
if [ "$FORCE" = true ] || [ "$need_build_container" = true ];then
  lock_acquire "$CONTAINER_LOCK"
  trap cleanup EXIT
  build_container "$(echo "$S" | jq -r .unit_hash)"
  cleanup
fi
trap - EXIT

if [ ${#STARTS_ARGS[@]} -gt 0 ]; then
  _NIXUNITS_PATH_SED_/bin/start.sh "$id" "${STARTS_ARGS[@]}"
fi