#!/bin/bash
set -e

. _NIXUNITS_PATH_SED_/bin/common.sh

usage() {
  echo "Usage : nixunits status <container id> [options]"
  echo "Available options:"
  echo "  -j JSON parameters file (for comparison)"
  echo "  -d details"
  echo "  -o <output [json/plain]>"
  echo "  -h, --help"
  echo

  test -n "$1" && exit "$1"
  exit 0
}

id=$1
test -z "$id" && usage 1
test "$id" = "h" && usage 0
test "$id" = "-h" && usage 0
test "$id" = "help" && usage 0
test "$id" = "--help" && usage 0
shift

DETAILS=false
OUTPUT="plain"

while getopts "dj:o:h:" opt; do
  case $opt in
    d)
      DETAILS=true;;
    j)
      PARAMETERS_FILE=$OPTARG;;
    o)
      if [ "$OPTARG" != "plain" ] && [ "$OPTARG" != "json" ]; then
        echo "Invalid output format : $OPTARG"
        usage 1
      fi
      OUTPUT=$OPTARG;;
    h)
      usage;;
    \?)
      echo "Invalid option : -$OPTARG" >&2
      usage 1;;
  esac
done

CONF_EXIST=false
NIX_SAME=unknown
DATA_EXIST=false
DECLARED_IN_NIXOS=false
STATUS=$(test -f "$(unit_conf "$id")" && echo "created" || echo "initial")

if [ "$DETAILS" == "true" ]
then
  STARTED_INFO=$(machinectl -o json | _JQ_SED_ ".[] | select(.machine == \"$id\")")
  if [ "$STARTED_INFO" != "" ]
  then
    STATUS="started"
    OS=$(echo "$STARTED_INFO" | _JQ_SED_ -r .os)
    VERSION=$(echo "$STARTED_INFO" | _JQ_SED_ -r .version)
    ADDRESSES=$(echo "$STARTED_INFO" | _JQ_SED_ -r .addresses)
  fi
else
  sub_state=$(machinectl show "$id" |grep ^State | cut -d'=' -f2)
  if [ "$sub_state" == "running" ]; then
    STATUS="started"
  fi
fi
_unit_conf=$(unit_conf "$id")

if [ "$STATUS" != "initial" ]
then
  if [ -f "$_unit_conf" ]
  then
    CONF_EXIST="true"
    DECLARED_IN_NIXOS=$(in_nixos "$id" && echo "true" || echo "false")
    if [ "$PARAMETERS_FILE" != "" ]
    then
      NIX_SAME=false
      diff "PARAMETERS_FILE" "$(unit_parameters "$ID")" >/dev/null && NIX_SAME=true
    fi
  else
    CONF_EXIST="false"
    STATUS="created"
  fi
  DATA_EXIST=$(test -d "$(unit_root "$id")" && echo "true" || echo "false")
fi

if [ "$OUTPUT" = "plain" ]
then
  echo "Container $id :"
  echo "  status : $STATUS"
  if [ "$STATUS" != "initial" ]
  then
    echo "  declared in nixos configuration : $DECLARED_IN_NIXOS"
    echo "  config exist : $CONF_EXIST"
    echo "  data exist : $DATA_EXIST"
    if [ "$DETAILS" == "true" ] && [ "$STATUS" == "started" ]
    then
      echo "  os : $OS"
      echo "  version : $VERSION"
      echo "  addresses:"
      for a in $ADDRESSES
      do
        echo "   * $a"
      done
    fi
  fi
else
  echo "{
  \"id\": \"$id\",
  \"os\": \"$OS\",
  \"status\": \"$STATUS\",
  \"version\": \"$VERSION\",
  \"data_exist\": $DATA_EXIST,
  \"config_exist\": $CONF_EXIST,
  \"nix_same\": $NIX_SAME,
  \"declared_in_nixos\": $DECLARED_IN_NIXOS,
  \"addresses\": [$(for a in $ADDRESSES;do echo -n \""$a"\"; echo -n ","; done | sed 's/,$//')]
}"
fi
