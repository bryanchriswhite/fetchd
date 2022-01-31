#!/usr/bin/env bats

load "../node_modules/bats-support/load"
load "../node_modules/bats-assert/load"

load "helpers"

CHAIN_ID="${CHAIN_ID-"localnet"}"
RECONCILIATION_LABEL="${RECONCILIATION_LABEL-"reconciliation_test"}"
FROM_ADDR="${FROM_ADDR-""}"
if [[ ! "$FROM_ADDR" =~ $FETCH_ADDR_REGEX ]]; then
  echo "Please set the FROM_ADDR environment variable"
  exit 1
fi

TX_FLAGS="-y --gas auto --from $FROM_ADDR --chain-id $CHAIN_ID"
TEST_OLD_ACCOUNT_NAME="test_register"

# TODO reuse reconciliation contract that has no registrations (?)
#setup_file() {
#}

#setup() {
#  # Remove staked export CSV
#  echo > "$STAKED_EXPORT_CSV_PATH"
#  rm "$STAKED_EXPORT_CSV_PATH"
#}

#teardown_file() {
#  if [[ "$(account_key_exists "$TEST_OLD_ACCOUNT_NAME")" != "true" ]]; then
#    fetchd keys delete "$TEST_OLD_ACCOUNT_NAME"
#  fi
#}

@test "build_contract succeeds" {
  run build_contract
  assert_success
  # TODO: assert wasm files exist
}

@test "deploy_contract returns a valid contract address" {
  RECONCILIATION_CONTRACT=$(deploy_contract "$RECONCILIATION_LABEL" "true" $TX_FLAGS)

  if [[ ! $RECONCILIATION_CONTRACT =~ $FETCH_ADDR_REGEX ]]; then
    fail "contract address \"$RECONCILIATION_CONTRACT\" did not match the regular expression $FETCH_ADDR_REGEX"
  fi

  QUERIED_CONTRACT_ADDR="$(fetchd query wasm contract "$RECONCILIATION_CONTRACT" --output json | jq -r ".address")"

  assert_equal "$QUERIED_CONTRACT_ADDR" "$RECONCILIATION_CONTRACT"
}

@test "register adds a registration to the reconciliation contract and an entry in staked exports output" {
  echo "WARNING: this test will hang if a fetchd key with the name '$TEST_OLD_ACCOUNT_NAME' already exists" >&3

  RECONCILIATION_CONTRACT=$(deploy_contract "$RECONCILIATION_LABEL" $TX_FLAGS)
  OLD_FETCH_ADDR=$(new_fetch_addr "$TEST_OLD_ACCOUNT_NAME")
  register "$RECONCILIATION_CONTRACT" "$NEW_FETCH_ADDR" "$OLD_FETCH_ADDR"  $TX_FLAGS

  REGISTRATIONS_COUNT="$(fetchd query wasm contract-state smart "$RECONCILIATION_CONTRACT" '{"query_all_registrations":{}}' --output json | jq ".data.registrations|length")"

  assert_equal "$REGISTRATIONS_COUNT" 1

  ROW=$(head -n 1 "$STAKED_EXPORT_CSV_PATH")
  # "$ETH_ADDR,,$OLD_FETCH_ADDR,$MIGRATED_AMOUNT,0,0"
  assert_equal "$(echo "$ROW" | cut -d ',' -f 3)" "$OLD_FETCH_ADDR"
  assert_equal "$(echo "$ROW" | cut -d ',' -f 4)" "$MIGRATED_AMOUNT"
}

@test "contract_set_paused pauses the reconciliation contract" {
  RECONCILIATION_CONTRACT=$(deploy_contract "$RECONCILIATION_LABEL" $TX_FLAGS)
  TEST_OLD_ACCOUNT_NAME="test_contract_set_paused"
  OLD_FETCH_ADDR=$(new_fetch_addr "$TEST_OLD_ACCOUNT_NAME")

  run contract_set_paused "$RECONCILIATION_CONTRACT" "true" $TX_FLAGS

  local ACTUALLY_PAUSED="false"
  ACTUALLY_PAUSED=$(fetchd query wasm contract-state smart "$RECONCILIATION_CONTRACT" '{"query_pause_status":{}}' --output json | jq ".data.paused")

  assert_equal "$ACTUALLY_PAUSED" "true"

  # TODO: cleanup if test fails
  fetchd keys delete "$TEST_OLD_ACCOUNT_NAME" -y
}

@test "send_coins transfers coins from sender to receiver" {
  skip "TODO: implement test"
}

@test "new_fetch_addr creates a new fetchd client key" {
  echo "WARNING: this test will hang if a fetchd key with the name '$TEST_OLD_ACCOUNT_NAME' already exists" >&3

  TEST_OLD_ACCOUNT_NAME="test_new_fetch_addr"
  run new_fetch_addr "$TEST_OLD_ACCOUNT_NAME"
  assert_success

  OLD_FETCH_ADDR="$output"
  if [[ ! $OLD_FETCH_ADDR =~ $FETCH_ADDR_REGEX ]]; then
    fail "address doesn't match expected format"
  fi

  # TODO: cleanup if test fails
  fetchd keys delete "$TEST_OLD_ACCOUNT_NAME" -y
}
