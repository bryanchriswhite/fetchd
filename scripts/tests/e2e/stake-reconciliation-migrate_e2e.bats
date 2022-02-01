#!/usr/bin/env bats

load "node_modules/bats-support/load"
load "node_modules/bats-assert/load"

load "helpers"

_fetchd="$FETCHD_ROOT/_fetchd"

CHAIN_ID="${CHAIN_ID-"localnet"}"
FROM_ADDR="${FROM_ADDR-""}"
if [[ ! "$FROM_ADDR" =~ $FETCH_ADDR_REGEX ]]; then
  echo "Please set the FROM_ADDR environment variable"
  exit 1
fi

GENESIS_TEMPLATE="$TESTS_DIR/genesis_template.json"
GENESIS_OUT_PATH="$TESTS_DIR/genesis_out.json"
STAKED_EXPORT_PATH="$TESTS_DIR/staked_export.csv"
REGISTRATIONS_PATH="$TESTS_DIR/registrations.json"

MIGRATED_AMOUNT="1000"
NEW_BALANCE_AMOUNT="10000000"
NEW_SEQ_NUM=0
OLD_SEQ_NUM=0
NEW_BALANCE_DENOM="atestfet"
OLD_BALANCE_DENOM="atestfet"
# Time in seconds to wait after submitting a tx before continuing.
TX_DELAY_SEC=7
TX_FLAGS="-y --gas auto --from $FROM_ADDR --chain-id $CHAIN_ID"

migrate_reconciliation() {
  "$FETCHD_ROOT/scripts/reconciliation/query_all_registrations.sh" "$RECONCILIATION_CONTRACT" > "$REGISTRATIONS_PATH"

  if [[ "$DEBUGGING" == "false" ]]; then
    _fetchd=$(command -v fetchd)
  fi

  echo "fetchd reconcile  $STAKED_EXPORT_CSV_PATH $REGISTRATIONS_PATH $GENESIS_TMP_PATH $GENESIS_OUT_PATH" >&3
  $_fetchd reconcile "$STAKED_EXPORT_CSV_PATH" "$REGISTRATIONS_PATH" "$GENESIS_TMP_PATH" "$GENESIS_OUT_PATH"
}

setup_file() {
  if [ ! "$SKIP_BUILD" = "true" ]; then
    echo "Skipping contract build" >&3
    build_contract
  fi
  if [ "$DEBUGGING" = "true" ]; then
    cd "$FETCHD_ROOT"
    go build -o "$FETCHD_ROOT/_fetchd" "$FETCHD_ROOT/cmd/fetchd"
  fi
}

ACCOUNT_INDEX=1
setup() {
  if [ "$RECONCILIATION_CONTRACT" = "" ]; then
    RECONCILIATION_CONTRACT="$(deploy_contract "reconciliation_test" "false" "$TX_FLAGS")"
  else
    echo "Skipping contract deployment, using: $RECONCILIATION_CONTRACT" >&3
  fi

  if [ "$DEBUGGING" = "true" ]; then
    echo "RECONCILIATION_CONTRACT address: $RECONCILIATION_CONTRACT" >&3
  fi

  TEST_NEW_ACCOUNT_NAME="test_new_account_${ACCOUNT_INDEX}"
  TEST_OLD_ACCOUNT_NAME="test_old_account_${ACCOUNT_INDEX}"
  echo "WARNING: this test will hang if a fetchd key with the name '$TEST_OLD_ACCOUNT_NAME' already exists" >&3
  echo "WARNING: this test will hang if a fetchd key with the name '$TEST_NEW_ACCOUNT_NAME' already exists" >&3
  NEW_FETCH_ADDR=$(new_fetch_addr "$TEST_NEW_ACCOUNT_NAME")
  OLD_FETCH_ADDR=$(new_fetch_addr "$TEST_OLD_ACCOUNT_NAME")
  ACCOUNT_INDEX=$((ACCOUNT_INDEX + 1))

  if [ ! "$SKIP_REGISTRATION" = "true" ]; then
    # Remove staked export CSV
    echo > "$STAKED_EXPORT_CSV_PATH"
    rm "$STAKED_EXPORT_CSV_PATH"
  fi
}

#teardown() {
#  for i in seq 0 $((ACCOUNT_INDEX - 1))
#  do
#    echo "deleting account with name 'test_account_$i'"
#    fetchd keys delete -y "test_account_$i"
#  done
#
#  rm "$GENESIS_TMP_PATH"
#}

# TODO: support parallel test execution
@test "migration aborts unless the reconciliation contract is paused" {
  run migrate_reconciliation

  assert_failure
  assert_output --partial "Aborting!: reconciliation contract \"$RECONCILIATION_CONTRACT\" is not paused"
}

@test "migration checks that the new account exists (i.e. has a balance)" {
  skip

  run migrate_reconciliation

  assert_success
  assert_output --partial "new account with address \"$NEW_FETCH_ADDR\" does not have a balance"
}

@test "migration checks that the old account has a non-zero sequence number" {
  skip
  run migrate_reconciliation

  assert_success
  assert_output --partial "\"$NEW_FETCH_ADDR\" ineligible for reason: sequence number must be 0"
}

@test "migration checks that the old account balance matches staked export amount" {
  skip

  run migrate_reconciliation

  assert_success
  assert_output --partial "\"$NEW_FETCH_ADDR\" ineligible for reason: old account balance must match staked export amount"
}

@test "migration checks that a registration exists with a matching ethereum address" {
  skip "TODO: implement me"
}

@test "migration succeeds" {
  if [ ! "$SKIP_REGISTRATION" = "true" ]; then
    register "$RECONCILIATION_CONTRACT" "$NEW_FETCH_ADDR" "$OLD_FETCH_ADDR" $TX_FLAGS

    # Pause reconciliation contract
    contract_set_paused "$RECONCILIATION_CONTRACT" "true" $TX_FLAGS
    sleep $TX_DELAY_SEC
  fi

  GENESIS_TMP_PATH=$(mktemp)
  sed "s,\$NEW_FETCH_ADDR,$NEW_FETCH_ADDR,g" "$GENESIS_TEMPLATE" | \
  sed "s,\$OLD_FETCH_ADDR,$OLD_FETCH_ADDR,g" | \
  sed "s,\$NEW_SEQ_NUM,$NEW_SEQ_NUM,g" | \
  sed "s,\$OLD_SEQ_NUM,$OLD_SEQ_NUM,g" | \
  sed "s,\$NEW_BALANCE_AMOUNT,$NEW_BALANCE_AMOUNT,g" | \
  sed "s,\$OLD_BALANCE_AMOUNT,$MIGRATED_AMOUNT,g" | \
  sed "s,\$NEW_BALANCE_DENOM,$NEW_BALANCE_DENOM,g" | \
  sed "s,\$OLD_BALANCE_DENOM,$OLD_BALANCE_DENOM,g" > "$GENESIS_TMP_PATH"

  run migrate_reconciliation
  assert_success

  echo "output: $output" >&3

  EXPECTED_GENESIS=$(sed "s,\$NEW_FETCH_ADDR,$NEW_FETCH_ADDR,g" "$GENESIS_TEMPLATE" | \
                     sed "s,\$OLD_FETCH_ADDR,$OLD_FETCH_ADDR,g" | \
                     sed "s,\$NEW_SEQ_NUM,$NEW_SEQ_NUM,g" | \
                     sed "s,\$OLD_SEQ_NUM,$OLD_SEQ_NUM,g" | \
                     sed "s,\$NEW_BALANCE_AMOUNT,$((NEW_BALANCE_AMOUNT + MIGRATED_AMOUNT)),g" | \
                     sed "s,\$OLD_BALANCE_AMOUNT,0,g" | \
                     sed "s,\$NEW_BALANCE_DENOM,$NEW_BALANCE_DENOM,g" | \
                     sed "s,\$OLD_BALANCE_DENOM,$OLD_BALANCE_DENOM,g")

  # Auth accounts match
  local ACCOUNTS_FILTER=".app_state.auth.accounts"
  assert_equal "$(jq "$ACCOUNTS_FILTER" "$GENESIS_OUT_PATH")" "$(jq "$ACCOUNTS_FILTER" <(echo "$EXPECTED_GENESIS"))"

  # Bank balances match
  local BALANCES_FILTER=".app_state.bank.balances"
  assert_equal "$(jq "$BALANCES_FILTER" "$GENESIS_OUT_PATH")" "$(jq "$BALANCES_FILTER" <(echo "$EXPECTED_GENESIS"))"
  # TODO: make assertion(s) about a diff (?)
}
