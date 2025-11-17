#!/bin/bash
set -euo pipefail

. _NIXUNITS_PATH_SED_/bin/common.sh

usage() {
  echo "Usage : nixunits build [options]"
  echo "Available options:"
  echo "  -d  debug (show-trace)"
  echo "  -n  Nix config file"
  echo "  -j  JSON parameters file"
  echo "  -h  help"
  echo "  -r  restart ?"
  echo "  -s  start ?"
  echo

  test -n "$1" && exit $1
  exit 0
}

test $# -eq 0 && usage 1
[[ "$1" =~ ^(-h|--help)$ ]] && usage 0

DEBUG=false
ARGS=(--impure)
STARTS_ARGS=()

while getopts "den:j:hsr" opt; do
  case $opt in
    d) DEBUG=true; ARGS+=("--show-trace");;
    r) STARTS_ARGS+=(-s -r);;
    s) STARTS_ARGS+=(-s);;
    n) NIX_FILE=$OPTARG;;
    j) PARAMETERS_FILE=$OPTARG;;
    h) usage;;
    *) usage 1;;
  esac
done
shift "$((OPTIND-1))"

if [ -z "${NIX_FILE:-}" ] || [ -z "${PARAMETERS_FILE:-}" ]; then
    echo "Args missing" >&2
    usage 1
fi

id=$(_JQ_SED_ -r '.id' "$PARAMETERS_FILE")

in_nixos_failed "$id"

GCROOTS="/var/lib/nixunits/gcroots"
STORE_DEFAULT="$PATH_CTX/store/default/root"
CONTAINER_DIR=$(unit_dir "$id")
mkdir -p "$CONTAINER_DIR"
chmod 2750 "$CONTAINER_DIR"

TMP_DIR="$CONTAINER_DIR/tmp"
ROOT_FUTUR="$TMP_DIR/root_futur"
MK_CONTAINER="(builtins.getFlake \"path:_NIXUNITS_PATH_SED_\").lib.x86_64-linux.mkContainer"

if [[ "$CONTAINER_DIR" != *var*nixunits* ]]; then
    echo "INTERNAL ERROR : invalid value for CONTAINER_DIR ${CONTAINER_DIR}" >&2
    exit 1
fi

cleanup() {
  umount "$TMP_DIR/merged" 2>/dev/null || true
  umount -l "$TMP_DIR/merged" 2>/dev/null || true
  lock_release
}

uid_root() {
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

prepare() {
  rm -rf "$TMP_DIR"
  mkdir -p "$ROOT_FUTUR" "$TMP_DIR/work" "$TMP_DIR/merged" "$TMP_DIR/logs" $GCROOTS

}

build_store() {
  echo "Build store for $id"
  local props='{\"id\": \"dummy\"}'
  local cmd=(nix build "${ARGS[@]}" --out-link "$GCROOTS/$id"\
               --store "$STORE_DEFAULT" \
               --expr  "($MK_CONTAINER {configFile = $NIX_FILE; propertiesJSON = \"$props\";})")

  [ "$DEBUG" = true ] && echo "${cmd[@]}"
  "${cmd[@]}"
}

build_container() {
  echo "Build container $id"
  mount -t overlay overlay -o "lowerdir=$STORE_DEFAULT,upperdir=$ROOT_FUTUR,workdir=$TMP_DIR/work" "$TMP_DIR/merged"
  mkdir -p "$TMP_DIR/merged/nix/var/nix"
  mount -t tmpfs tmpfs "$TMP_DIR/merged/nix/var/nix"
  rsync -a --exclude=temproots "$STORE_DEFAULT/nix/var/nix/" "$TMP_DIR/merged/nix/var/nix/"

  local props="builtins.readFile $PARAMETERS_FILE"
  local cmd=(nix build --no-link --print-out-paths "${ARGS[@]}" \
               --store "$TMP_DIR/merged" \
               --expr  "($MK_CONTAINER {configFile = $NIX_FILE; propertiesJSON = $props;})")

  [ "$DEBUG" = true ] && echo "${cmd[@]}"
  RESULT_PATH="$("${cmd[@]}")"


  conf_path="$ROOT_FUTUR/$RESULT_PATH/etc/nixunits/$id.conf"
  conf_target=$(readlink -f "$conf_path") || {
    echo "INTERNAL ERROR : Failed get $conf_path" >&2
    exit 1
  }
  ln -fs "$CONTAINER_DIR/root$conf_target" "$ROOT_FUTUR/unit.conf"
  cp "$PARAMETERS_FILE" "$ROOT_FUTUR/parameters.json"
}

lock_acquire
uid_root
prepare
build_store
trap cleanup EXIT
build_container
cleanup
trap - EXIT
touch "$ROOT_FUTUR/.complete"

if [ ${#STARTS_ARGS[@]} -gt 0 ]; then
  _NIXUNITS_PATH_SED_/bin/start.sh "$id" "${STARTS_ARGS[@]}"
fi