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
