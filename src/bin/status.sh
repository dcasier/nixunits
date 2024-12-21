#!/bin/bash
set -e

. NIXUNITS/bin/common.sh

usage() {
  echo "Usage : nixunits status <container id> [options]"
  echo "Available options:"
  echo "  -o <output [json/plain]>"
  echo "  -h, --help"
  echo

  test -n "$1" && exit "$1"
  exit 0
}

id=$1
test -z "$id" && usage 1
shift

OUTPUT="plain"

while getopts "o:h:" opt; do
  case $opt in
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
DATA_EXIST=false
STATUS=$(test -d "$(unit_dir "$id")" && echo "created" || echo "initial")
STARTED_INFO=$(machinectl -o json | jq ".[] | select(.machine == \"$id\")")
if [ "$STARTED_INFO" != "" ]
then
  STATUS="started"
  OS=$(echo "$STARTED_INFO" | jq -r .os)
  VERSION=$(echo "$STARTED_INFO" | jq -r .version)
  ADDRESSES=$(echo "$STARTED_INFO" | jq -r .addresses)
fi

if [ "$STATUS" != "initial" ]
then
  CONF_EXIST=$(test -f "$(unit_conf "$id")" && echo "true" || echo "false")
  DATA_EXIST=$(test -d "$(unit_root "$id")" && echo "true" || echo "false")
fi

if [ "$OUTPUT" = "plain" ]
then
  echo "Container $id :"
  echo "  status : $STATUS"
  if [ "$STATUS" != "initial" ]
  then
    echo "  config exist : $CONF_EXIST"
    echo "  data exist : $DATA_EXIST"
    if [ "$STATUS" == "started" ]
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
    \"status\": \"$STATUS\",
    \"config_exist\": \"$CONF_EXIST\",
    \"data_exist\": \"$DATA_EXIST\",
    \"os\": \"$OS\",
    \"version\": \"$VERSION\",
    \"addresses\": [$(for a in $ADDRESSES;do echo -n \"$a\"; echo -n ","; done | sed 's/,$//')]
  }"
fi