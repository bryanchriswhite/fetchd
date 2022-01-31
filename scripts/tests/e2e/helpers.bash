#!/usr/bin/env bash
set -eEo pipefail

FETCH_ADDR_REGEX="^fetch[0-9a-z]{39}"
# TODO: doesn't work if bats binary is the entrypoint
if [ -n "$BATS_TEST_FILENAME" ]; then
  TESTS_DIR="$(dirname "$(realpath "$BATS_TEST_FILENAME")")"
else
  TESTS_DIR="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"
fi

# Defaults
SEND_AMOUNT="${SEND_AMOUNT-1000000000}"
SEND_DENOM="${SEND_DENOM-"atestfet"}"
MIGRATED_AMOUNT="${MIGRATED_AMOUNT-1000}"
FROM_ADDR="${FROM_ADDR-""}"
CHAIN_ID="${CHAIN_ID-"localnet"}"
STAKED_EXPORT_CSV_PATH="${STAKED_EXPORT_CSV_PATH-"$TESTS_DIR/staked_export.csv"}"
# Time in seconds to wait after submitting a tx before querying.
TX_DELAY_SEC="${TX_DELAY_SEC-"7"}"
TX_FLAGS="-y --gas auto --from $FROM_ADDR --chain-id $CHAIN_ID"

FETCHD_ROOT="$TESTS_DIR/../../.."
FETCHHUB_ROOT="$FETCHD_ROOT/../genesis-fetchhub"
CONTRACT_RECONCILIATION_ROOT="$(realpath "$FETCHD_ROOT/../contract-reconciliation")"
RECONCILIATION_PATCH_PATH="$TESTS_DIR/contract-reconciliation.patch"

missing_sibling_repo() {
  URL="$1"
  NAME=$(basename "$URL")
  echo -e "\"$NAME\" repository not found.\n\
  Ensure it is cloned as a sibling to the fetchd repository root directory.\n\
  ($URL)"
  exit 1
}

#account_key_exists() {
#  local ACCOUNT_NAME="${1-}"
#  local RESULT
#  KEYS_LIST_OUTPUT="$(fetchd keys list --output json 2>&1)"
#
#  echo "$KEYS_LIST_OUTPUT" >3
#
#  if [[ "$(echo "$KEYS_LIST_OUTPUT" | head -n 1)" =~ "item could not be found in the keyring$" ]]; then
#    echo "false"
#    return
#  fi
#
#  RESULT="$(jq -r ". | map(select(.name == \"$ACCOUNT_NAME))[0].name")"
#  if [ "$RESULT" = "$ACCOUNT_NAME" ]; then
#    echo "true"
#    return
#  fi
#
#  echo "false"
#}

build_contract() {
  echo "CONTRACT_RECONCILIATION_ROOT: $CONTRACT_RECONCILIATION_ROOT" 1>&3
  cd "$CONTRACT_RECONCILIATION_ROOT"

  # Disable signature verification in reconciliation registration
  git stash 1>&3
  git apply "$RECONCILIATION_PATCH_PATH" 1>&3

  # Build reconciliation contract
  cargo wasm 1>&3

  # Optimize reconciliation contract binary
  docker run --rm -v "$CONTRACT_RECONCILIATION_ROOT":/code \
    -v "$TESTS_DIR/target":/code/target \
    -v "$TESTS_DIR/artifacts":/code/artifacts \
    --mount type=volume,source=registry_cache,target=/usr/local/cargo/registry \
    cosmwasm/rust-optimizer:0.12.4 1>&3
}

deploy_contract() {
  echo "Deploying reconciliation contract..." >&3

  cd "$CONTRACT_RECONCILIATION_ROOT"

  local RECONCILIATION_LABEL="$1"
  shift
  local PAUSED="${1-"false"}"
  shift
  if [ $# -gt 0 ]; then
    local TX_FLAGS="$*"
  fi

  # Store reconciliation contract
  local STORE_TX_HASH
  echo "fetchd tx wasm store \"$TESTS_DIR/artifacts/reconciliation.wasm\" --output json $TX_FLAGS" >&3
  STORE_TX_HASH="$(fetchd tx wasm store "$TESTS_DIR/artifacts/reconciliation.wasm" --output json $TX_FLAGS | jq -r ".txhash")"
  sleep "$TX_DELAY_SEC"

  # Lookup contract address
  local RECONCILIATION_CODE
  RECONCILIATION_CODE="$(fetchd query tx "$STORE_TX_HASH" --output json | jq -r '.logs[0].events[-1].attributes[-1].value')"

  # Instantiate reconciliation contract un-paused
  fetchd tx wasm instantiate "$RECONCILIATION_CODE" "{\"paused\": $PAUSED}" --label "$RECONCILIATION_LABEL" $TX_FLAGS &>/dev/null
  sleep "$TX_DELAY_SEC"

  # Lookup contract address
  fetchd query wasm list-contract-by-code "$RECONCILIATION_CODE" --output json | jq -r ".contracts[0]"
}

new_fetch_addr() {
  local TEST_ACCT_NAME="${1-"reconciliation_migration_test_account"}"
  # Return account address
  fetchd keys add "$TEST_ACCT_NAME" --output json | jq -r ".address"
}

send_coins() {
  local FROM_ADDR="${1-}"
  shift
  local TO_ADDR="${1-}"
  shift
  if [ $# -gt 0 ]; then
    local TX_FLAGS="$*"
  fi

  echo "Sending coins from $FROM_ADDR to $TO_ADDR..." >&3

  fetchd tx bank send "$FROM_ADDR" "$TO_ADDR" "${SEND_AMOUNT}${SEND_DENOM}" $TX_FLAGS 1>/dev/null
  sleep $TX_DELAY_SEC
}

register() {
  local RECONCILIATION_CONTRACT="${1-}"
  shift
  local NEW_FETCH_ADDR="${1-}"
  shift
  local OLD_FETCH_ADDR="${1-}"
  shift
  local TX_FLAGS="$*"

  echo "Registering with reconciliation contract..." >&3

  # Generate ethereum address
  ETH_ADDR="0x$(hexdump -n 20 -e '1/8 "%x"' /dev/random)"

  # Register with reconciliation contract
  REGISTRATION_DATA="{\"register\":{
    \"eth_address\": \"$ETH_ADDR\",
    \"native_address\": \"$NEW_FETCH_ADDR\",
    \"signature\": \"0x0123456789\"
  }}"

  fetchd tx wasm execute "$RECONCILIATION_CONTRACT" "$REGISTRATION_DATA" $TX_FLAGS 1>/dev/null

  echo "Adding old address $OLD_FETCH_ADDR row to staked export CSV..." >&3

  # Add entry to staked export with matching eth address
  echo "$ETH_ADDR,,$OLD_FETCH_ADDR,$MIGRATED_AMOUNT,0,0" >> "$STAKED_EXPORT_CSV_PATH"
  sleep $TX_DELAY_SEC
}

contract_set_paused() {
  echo "Pausing reconciliation contract..." >&3
  local RECONCILIATION_CONTRACT="${1-}"
  shift
  local PAUSED="${1-}"
  shift
  local TX_FLAGS="$*"

  PAUSE_DATA="{\"set_paused\":{
    \"paused\": $PAUSED
  }}"

  fetchd tx wasm execute "$RECONCILIATION_CONTRACT" "$PAUSE_DATA" $TX_FLAGS
  sleep $TX_DELAY_SEC
}

# TODO: move sibling repo checks into test-only code
trap "missing_sibling_repo https://github.com/fetchai/contract-reconciliation" ERR
stat "$CONTRACT_RECONCILIATION_ROOT" 1>/dev/null

trap "missing_sibling_repo https://github.com/fetchai/genesis-fetchhub" ERR
stat "$FETCHHUB_ROOT" 1>/dev/null

trap - ERR
