#!/usr/bin/env bats

load "node_modules/bats-support/load"
load "node_modules/bats-assert/load"

load "helpers"

DIR="$(dirname "$(realpath "$BATS_TEST_FILENAME")")"
SCRIPT_DIR="$(realpath "$DIR/../../")"

if [[ ! "$FROM_ADDR" =~ $FETCH_ADDR_REGEX ]]; then
  echo "Please specify a FROM_ADDR environment variable to specify an account to pay for test transactions."
  exit 1
fi

@test "migration aborts unless the reconciliation contract is paused" {
  RECONCILIATION_CONTRACT="$(deploy_contract "query_all_registrations_test" "false")"

  run "$SCRIPT_DIR/query_all_registrations.sh"

  assert_failure
  assert_output --partial "Aborting!: reconciliation contract \"$RECONCILIATION_CONTRACT\" is not paused"
}
