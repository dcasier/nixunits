#!/bin/bash
set -euo pipefail

. _NIXUNITS_PATH_SED_/bin/common.sh

usage() {
  echo "Usage : nixunits build -i <ID> OR -j <parameters file> [options]"
  echo "Available options:"
  echo "  -d  debug (show-trace)"
  echo "  -f  force (build)"
  echo "  -i  container ID"
  echo "  -j  JSON parameters file"
  echo "  -n  Nix config file"
  echo "  -h  help"
  echo "  -r  restart ?"
  echo "  -s  start ?"
  echo

  test -n "$1" && exit "$1"
  exit 0
}

test $# -eq 0 && usage 1
[[ "$1" =~ ^(-h|--help)$ ]] && usage 0

ARGS=(--impure)
DEBUG=false
FORCE=false
id=""
NIX_FILE=""
PARAMS_FILE=""
STARTS_ARGS=()

while getopts "dfi:j:n:hsr" opt; do
  case $opt in
    d) DEBUG=true; ARGS+=("--show-trace");;
    f) FORCE=true;;
    i) id=$OPTARG;;
    j) PARAMS_FILE=$OPTARG;;
    n) NIX_FILE=$OPTARG;;
    r) STARTS_ARGS+=(-s -r);;
    s) STARTS_ARGS+=(-s);;
    h) usage;;
    *) usage 1;;
  esac
done
shift "$((OPTIND-1))"

if [ -n "$PARAMS_FILE" ]; then
  if is_url "$PARAMS_FILE"; then
    id="$(curl --fail -sL "$PARAMS_FILE" | _JQ_SED_ -r '.id')"
  else
    id=$(_JQ_SED_ -r '.id' "$PARAMS_FILE")
  fi
fi

in_nixos_failed "$id"
container_env "$id"

if [[ "$CONTAINER_DIR" != *var*nixunits* ]]; then
    echo "INTERNAL ERROR : invalid value for CONTAINER_DIR ${CONTAINER_DIR}" >&2
    exit 1
fi

mkdir -p "$CONTAINER_DIR" "$C_FUTUR"
chmod 2750 "$CONTAINER_DIR"

if [ -n "$PARAMS_FILE" ]; then
  if is_url "$PARAMS_FILE"; then
    curl --fail -L "$PARAMS_FILE" -o "$C_FUTUR_ARGS"
  else
    cp "$PARAMS_FILE" "$C_FUTUR_ARGS"
  fi
elif [ ! -f "$C_FUTUR_ARGS" ] && [ -f "$CONTAINER_ARGS" ]; then
  cp "$CONTAINER_ARGS" "$C_FUTUR_ARGS"
fi

if [ -n "$NIX_FILE" ]; then
  if is_url "$NIX_FILE"; then
    curl --fail -sL "$NIX_FILE" -o "$C_FUTUR_NIX"
  else
    cp "$NIX_FILE" "$C_FUTUR_NIX"
  fi
elif [ ! -f "$C_FUTUR_NIX" ] && [ -f "$CONTAINER_NIX" ]; then
  cp "$CONTAINER_NIX" "$C_FUTUR_NIX"
fi

if [ ! -f "$C_FUTUR_NIX" ] || [ ! -f "$C_FUTUR_ARGS" ]; then
    usage 1
fi

STORE_HASH=$(hash_with "$C_FUTUR_NIX" "$ENV_HASH")
GCROOT_PATH="$GCROOTS_CONTAINERS/$STORE_HASH"
UNIT_HASH=$(hash_with "$C_FUTUR_ARGS" "$STORE_HASH")

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
  local props='{\"id\": \"dummy\"}'
  local cmd=(nix build "${ARGS[@]}" --out-link "$GCROOT_PATH" --store "$STORE_CONTAINERS" \
               --expr  "($MK_CONTAINER {configFile = $C_FUTUR_NIX; propertiesJSON = \"$props\";})")

  echo "Build store for $id"
  [ "$DEBUG" = true ] && echo "${cmd[@]}"
  "${cmd[@]}"

  mkdir -p "$GCROOTS_CONTAINERS"
  ln -Tfs "$GCROOT_PATH" "$CONTAINER_DIR/store"
}

build_container() {
  if [ -f "$C_FUTUR_OK" ]; then
    mv "$C_FUTUR_OK" "${C_FUTUR_OK}_bkp"
  fi
  rm -rf "$C_FUTUR/nix"
  mkdir -p "$C_TMP/work" "$C_TMP/merged" "$C_TMP/logs"

  mount_o="lowerdir=$STORE_CONTAINERS,upperdir=$C_FUTUR,workdir=$C_TMP/work"
  [ "$DEBUG" = true ] && echo "mount -t overlay overlay -o $mount_o $C_TMP/merged"
  mount -t overlay overlay -o "$mount_o" "$C_TMP/merged"
  mkdir -p "$C_TMP/merged/nix/var/nix"
  mount -t tmpfs tmpfs "$C_TMP/merged/nix/var/nix"
  rsync -a --exclude=temproots "$STORE_CONTAINERS/nix/var/nix/" "$C_TMP/merged/nix/var/nix/"

  local props="builtins.readFile $PARAMS_FILE"
  local cmd=(nix build --no-link --print-out-paths "${ARGS[@]}" --store "$C_TMP/merged" \
               --expr  "($MK_CONTAINER {configFile = $C_FUTUR_NIX; propertiesJSON = $props;})")

  echo "Build container $id"
  [ "$DEBUG" = true ] && echo "${cmd[@]}"
  RESULT_PATH="$("${cmd[@]}")"

  conf_path="$C_FUTUR/$RESULT_PATH/etc/nixunits/$id.conf"
  conf_target=$(readlink -f "$conf_path") || {
    echo "INTERNAL ERROR : Failed get $conf_path" >&2
    exit 1
  }
  ln -fs "$CONTAINER_DIR/root$conf_target" "$C_FUTUR/unit.conf"
  cp "$PARAMS_FILE" "$C_FUTUR_ARGS"
  echo "$UNIT_HASH" > "$CONTAINER_META"
  cp "$C_FUTUR_NIX" "$C_FUTUR_OK"
}

S=$(_NIXUNITS_PATH_SED_/bin/status.sh "$id")
status=$(echo "$S" | jq -r .status)

[ "$status" = "initial" ] && FORCE=true

if [ "$FORCE" = true ] || [ ! -L "$GCROOT_PATH" ];then
  lock_acquire
  trap lock_release EXIT
  uid_alloc
  build_store
  lock_release
else
  echo "Store unchanged"
fi
if [ "$FORCE" = true ] || [ ! -f "$CONTAINER_META" ] || [ ! "$(cat "$CONTAINER_META")" = "$UNIT_HASH" ];then
  lock_acquire "$CONTAINER_LOCK"
  trap cleanup EXIT
  build_container
  cleanup
else
  echo "Build unchanged"
fi
trap - EXIT

if [ ${#STARTS_ARGS[@]} -gt 0 ]; then
  _NIXUNITS_PATH_SED_/bin/start.sh "$id" "${STARTS_ARGS[@]}"
fi