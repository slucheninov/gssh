#!/usr/bin/env bats

load test_helper/setup

@test "--refresh creates cache file" {
  run_gssh --refresh
  [ "$status" -eq 0 ]
  [ -f "${GSSH_CACHE_FILE}" ]
}

@test "-r creates cache file" {
  run_gssh -r
  [ "$status" -eq 0 ]
  [ -f "${GSSH_CACHE_FILE}" ]
}

@test "-r reloads projects from the env file in the current shell" {
  export GSSH_MOCK_DATA_DIR="${TEST_TEMP_DIR}/mock_data"
  mkdir -p "$GSSH_MOCK_DATA_DIR"
  printf 'old-vm us-central1-a\n' > "${GSSH_MOCK_DATA_DIR}/__old-project"
  printf 'new-vm us-central1-b\n' > "${GSSH_MOCK_DATA_DIR}/__new-project"
  printf 'GSSH_PROJECTS="new-project"\n' > "$GSSH_ENV_FILE"

  export GSSH_PROJECTS="old-project"
  run_gssh -r

  [ "$status" -eq 0 ]
  [[ "$(<"$GSSH_CACHE_FILE")" == *$'new-vm\tnew-project\tus-central1-b'* ]]
  [[ "$(<"$GSSH_CACHE_FILE")" != *"old-vm"* ]]
}

@test "--refresh reports VM count" {
  run_gssh --refresh
  [ "$status" -eq 0 ]
  [[ "${output}" == *"cache refreshed"* ]]
  [[ "${output}" == *"VMs"* ]]
}

@test "--list shows cached VMs" {
  run_gssh --list
  [ "$status" -eq 0 ]
  [[ "${output}" == *"vm-web-01"* ]]
  [[ "${output}" == *"vm-api-01"* ]]
}

@test "-l shows cached VMs" {
  run_gssh -l
  [ "$status" -eq 0 ]
  [[ "${output}" == *"vm-web-01"* ]]
}

@test "exclude prefixes filters VMs" {
  export GSSH_EXCLUDE_PREFIXES="vm-db"
  run_gssh --refresh
  run_gssh --list
  [ "$status" -eq 0 ]
  [[ "${output}" != *"vm-db-01"* ]]
  [[ "${output}" == *"vm-web-01"* ]]
}

@test "exclude prefixes are treated as literal strings" {
  export GSSH_EXCLUDE_PREFIXES="vm."
  run_gssh --refresh
  run_gssh --list
  [ "$status" -eq 0 ]
  [[ "${output}" != *"vm.db-01"* ]]
  [[ "${output}" == *"vm-web-01"* ]]
}

@test "--refresh keeps existing cache when gcloud fails" {
  run_gssh --refresh
  [ "$status" -eq 0 ]
  export GSSH_MOCK_FAIL_LIST=1
  run_gssh --refresh
  [ "$status" -eq 1 ]
  run_gssh --list
  [ "$status" -eq 0 ]
  [[ "${output}" == *"vm-web-01"* ]]
}

@test "--account refresh uses account-specific cache file" {
  run_gssh --account user@test.com --refresh
  [ "$status" -eq 0 ]
  [ -f "${TEST_TEMP_DIR}/cache/user_test_com_vms" ]
}

@test "multi-account refresh creates per-account cache files" {
  export GSSH_ACCOUNTS="user1@test.com user2@test.com"
  export GSSH_PROJECTS="project-a project-b"
  export GSSH_MOCK_DATA_DIR="${TEST_TEMP_DIR}/mock_data"
  export GSSH_MOCK_AUTHED_ACCOUNTS=$'user1@test.com\nuser2@test.com'
  mkdir -p "$GSSH_MOCK_DATA_DIR"

  printf 'vm-web-01 us-central1-a\nvm-api-01 us-central1-a\n' > "${GSSH_MOCK_DATA_DIR}/user1@test.com__project-a"
  printf 'vm-db-01 us-central1-b\n' > "${GSSH_MOCK_DATA_DIR}/user2@test.com__project-b"

  run_gssh --refresh
  [ "$status" -eq 0 ]
  [ -f "${TEST_TEMP_DIR}/cache/user1_test_com_vms" ]
  [ -f "${TEST_TEMP_DIR}/cache/user2_test_com_vms" ]
  [[ "${output}" == *"3 VMs across 2 accounts"* ]]
}

@test "multi-account --list shows VMs from all accounts" {
  export GSSH_ACCOUNTS="user1@test.com user2@test.com"
  export GSSH_PROJECTS="project-a project-b"
  export GSSH_MOCK_DATA_DIR="${TEST_TEMP_DIR}/mock_data"
  export GSSH_MOCK_AUTHED_ACCOUNTS=$'user1@test.com\nuser2@test.com'
  mkdir -p "$GSSH_MOCK_DATA_DIR"

  printf 'vm-web-01 us-central1-a\n' > "${GSSH_MOCK_DATA_DIR}/user1@test.com__project-a"
  printf 'vm-db-01 us-central1-b\n' > "${GSSH_MOCK_DATA_DIR}/user2@test.com__project-b"

  run_gssh --list
  [ "$status" -eq 0 ]
  [[ "${output}" == *"vm-web-01"* ]]
  [[ "${output}" == *"vm-db-01"* ]]
}

@test "multi-account cache does not include warnings" {
  export GSSH_ACCOUNTS="user1@test.com user2@test.com"
  export GSSH_PROJECTS="project-a project-b"
  export GSSH_MOCK_DATA_DIR="${TEST_TEMP_DIR}/mock_data"
  export GSSH_MOCK_AUTHED_ACCOUNTS=$'user1@test.com\nuser2@test.com'
  mkdir -p "$GSSH_MOCK_DATA_DIR"

  printf 'vm-web-01 us-central1-a\n' > "${GSSH_MOCK_DATA_DIR}/user1@test.com__project-a"
  printf 'vm-db-01 us-central1-b\n' > "${GSSH_MOCK_DATA_DIR}/user2@test.com__project-b"

  run_gssh --list
  [ "$status" -eq 0 ]
  [[ "${output}" != *"WARNING"* ]]
  [[ "${output}" != *"ERROR"* ]]
  [[ "${output}" != *"permission denied"* ]]
}

@test "multi-account SSH auto-detects account from cache" {
  export GSSH_ACCOUNTS="user1@test.com user2@test.com"
  export GSSH_PROJECTS="project-a project-b"
  export GSSH_MOCK_DATA_DIR="${TEST_TEMP_DIR}/mock_data"
  export GSSH_MOCK_AUTHED_ACCOUNTS=$'user1@test.com\nuser2@test.com'
  mkdir -p "$GSSH_MOCK_DATA_DIR"

  printf 'vm-web-01 us-central1-a\n' > "${GSSH_MOCK_DATA_DIR}/user1@test.com__project-a"
  printf 'vm-db-01 us-central1-b\n' > "${GSSH_MOCK_DATA_DIR}/user2@test.com__project-b"

  run_gssh --dry-run vm-db-01
  [ "$status" -eq 0 ]
  [[ "${output}" == *"--account=user2@test.com"* ]]
  [[ "${output}" == *"--project=project-b"* ]]
}

@test "error when account is not authenticated" {
  export GSSH_ACCOUNTS="user@test.com unauthed@test.com"
  export GSSH_MOCK_AUTHED_ACCOUNTS="user@test.com"

  run_gssh --list
  [ "$status" -eq 1 ]
  [[ "${output}" == *"not authenticated"* ]]
  [[ "${output}" == *"unauthed@test.com"* ]]
  [[ "${output}" == *"gcloud auth login"* ]]
}

@test "error when explicit --account is not authenticated" {
  export GSSH_MOCK_AUTHED_ACCOUNTS="other@test.com"

  run_gssh --account bad@test.com --list
  [ "$status" -eq 1 ]
  [[ "${output}" == *"not authenticated"* ]]
  [[ "${output}" == *"bad@test.com"* ]]
}

@test "no error when all accounts are authenticated" {
  export GSSH_ACCOUNTS="user@test.com"
  export GSSH_MOCK_AUTHED_ACCOUNTS="user@test.com"

  run_gssh --list
  [ "$status" -eq 0 ]
}

@test "fresh cache with warning rows is automatically rebuilt" {
  mkdir -p "$(dirname "$GSSH_CACHE_FILE")"
  printf 'valid-vm\ttest-project-1\tus-central1-a\nWARNING:\ttest-project-1\tSome\n-\ttest-project-1\tRequired\n' > "$GSSH_CACHE_FILE"
  run_gssh --list
  [ "$status" -eq 0 ]
  [[ "$output" == *"vm-web-01"* ]]
  [[ "$(cat "$GSSH_CACHE_FILE")" != *"WARNING"* ]]
}

@test "stdout diagnostics are never written as VM rows" {
  export GSSH_MOCK_DATA_DIR="${TEST_TEMP_DIR}/mock_data"
  mkdir -p "$GSSH_MOCK_DATA_DIR"
  printf 'WARNING: Some requests failed\n- Required permission\ncoredns-01 us-central1-a\n' > "$GSSH_MOCK_DATA_DIR/__test-project-1"
  run_gssh --refresh
  [ "$status" -eq 0 ]
  [ "$(cat "$GSSH_CACHE_FILE")" = $'coredns-01\ttest-project-1\tus-central1-a' ]
}

@test "list reports failure when no cache can be fetched" {
  export GSSH_MOCK_FAIL_LIST=1
  run_gssh --list
  [ "$status" -eq 1 ]
  [[ "$output" == *"failed to list VMs"* ]]
}

@test "multi-account refresh does not report success when all requests fail" {
  export GSSH_ACCOUNTS="user1@test.com user2@test.com"
  export GSSH_MOCK_AUTHED_ACCOUNTS=$'user1@test.com\nuser2@test.com'
  export GSSH_MOCK_FAIL_LIST=1
  run_gssh --refresh
  [ "$status" -eq 1 ]
  [[ "$output" == *"cache refresh failed for 2 account(s)"* ]]
  [[ "$output" != *"cache refreshed ("* ]]
}

@test "completion refresh never starts a terminal spinner" {
  run zsh -c '
    source "$GSSH_ROOT/gssh.zsh"
    GSSH_COMPLETING=true
    _gssh_spinner $$ should-not-be-printed
  '
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
