#!/usr/bin/env bash
set -ueEo pipefail

source "./helpers.bash"
BATS_PATH="$TESTS_DIR/node_modules/.bin/bats"

FETCHHUB_2_DATA="$FETCHHUB_ROOT/archive/fetchhub-2/data"
GENESIS_IN_PATH="$FETCHHUB_2_DATA/genesis.json"
GENESIS_OUT_PATH="$TESTS_DIR/genesis_out.json"

# Defaults
DEBUGGING="false"
RECONCILIATION_CONTRACT="${RECONCILIATION_CONTRACT-""}"
FROM_ADDR="${1-""}"
SKIP_BUILD="false"
SKIP_DEPLOY="false"
SKIP_REGISTRATION="false"
FILTER=""
X_FLAG=""

# Option parsing
PARAMS=""
while (( "$#" )); do
  case "$1" in
    -d|--debug)
      DEBUGGING="true"
      shift
    ;;
    -f|--filter)
      if [ -n "$2" ] && [ ${2:0:1} != "-" ]; then
        FILTER="$2"
        shift 2
      else
        echo "Error: Argument for $1 is missing" >&2
        exit 1
      fi
    ;;
    -r|--reconciliation-address)
      if [ -n "$2" ] && [ ${2:0:1} != "-" ]; then
        RECONCILIATION_CONTRACT="$2"
        SKIP_BUILD="true"
        shift 2
      else
        echo "Error: Argument for $1 is missing" >&2
        exit 1
      fi
    ;;
    -sb|--skip-build)
      SKIP_BUILD="true"
      shift
    ;;
    -sr|--skip-registration)
      SKIP_REGISTRATION="true"
      SKIP_BUILD="true"
      shift
    ;;
    -x)
      X_FLAG="-x"
      set -x
      shift
    ;;
    -*|--*=) # unsupported flags
      echo "Error: Unsupported flag $1" >&2
      exit 1
      ;;
    *) # preserve positional arguments
      PARAMS="$PARAMS $1"
      shift
      ;;
  esac
done

RECONCILIATION_CONTRACT="${RECONCILIATION_CONTRACT-""}"

if [[ ! "$FROM_ADDR" =~ $FETCH_ADDR_REGEX ]]; then
  echo "usage: run_test.sh FROM_ADDR [OPTION, ...]
  Where FROM_ADDR is the fetch address of the fetchd client key that will fund all test transactions.
  If a filter flag is provided, it will be passed on to bats (see: https://bats-core.readthedocs.io/en/stable/usage.html?highlight=--filter).

  OPTIONS:
    -f|--filter SUBSTRING           Only run test functions whose names include SUBSTRING.
    -r|--reconciliation-addr ADDR   Specifies the address of the reconciliation contract to query (implies -sb).
    -sb|--skip-build                Skip building the reconciliation contract (use existing build).
    -sr|--skip-registration         Skip registering accounts with the reconciliation contract (implies -sb).
    -d|--debug                      Prints reconciliation contract for re-use with -r. Useful while debugging.
    -x                              Set -x bash option and pass on to bats."

  exit 1
fi

DEBUG_ARG=""
if [[ "$DEBUGGING" == "true" ]]; then
  DEBUG_ARG="-d"
  go build -o "$FETCHD_ROOT/_fetchd" "$FETCHD_ROOT/cmd/fetchd"
fi

for TEST in ./*.bats
do
  echo "Running tests in $TEST"
  SKIP_BUILD="$SKIP_BUILD" \
  SKIP_DEPLOY="$SKIP_DEPLOY" \
  SKIP_REGISTRATION="$SKIP_REGISTRATION" \
  DEBUGGING="$DEBUGGING" \
  RECONCILIATION_CONTRACT="$RECONCILIATION_CONTRACT" \
  TX_DELAY_SEC="$TX_DELAY_SEC" \
  CHAIN_ID="$CHAIN_ID" \
  FROM_ADDR="$FROM_ADDR" \
  GENESIS_IN_PATH="$GENESIS_IN_PATH" \
  GENESIS_OUT_PATH="$GENESIS_OUT_PATH" \
  $BATS_PATH "$TEST" -f "$FILTER" "$X_FLAG"
done