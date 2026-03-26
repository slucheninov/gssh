#!/usr/bin/env bats

load test_helper/setup

@test "--help prints usage" {
  run_gssh --help
  [ "$status" -eq 0 ]
  [[ "${output}" == *"Usage: gssh"* ]]
}

@test "-h prints usage" {
  run_gssh -h
  [ "$status" -eq 0 ]
  [[ "${output}" == *"Usage: gssh"* ]]
}

@test "--version prints version" {
  run_gssh --version
  [ "$status" -eq 0 ]
  [[ "${output}" == *"gssh"* ]]
}

@test "-V prints version" {
  run_gssh -V
  [ "$status" -eq 0 ]
  [[ "${output}" == *"gssh"* ]]
}

@test "unknown flag returns error" {
  run_gssh --nonexistent
  [ "$status" -eq 1 ]
  [[ "${output}" == *"unknown option"* ]]
}

@test "unknown short flag returns error" {
  run_gssh -x
  [ "$status" -eq 1 ]
  [[ "${output}" == *"unknown option"* ]]
}

@test "no arguments prints usage hint" {
  run_gssh
  [ "$status" -eq 1 ]
  [[ "${output}" == *"Usage:"* ]]
}

@test "--dry-run shows gcloud command" {
  run_gssh --dry-run my-vm test-project-1 us-central1-a
  [ "$status" -eq 0 ]
  [[ "${output}" == *"gcloud compute ssh"* ]]
  [[ "${output}" == *"my-vm"* ]]
  [[ "${output}" == *"--tunnel-through-iap"* ]]
}

@test "-d shows gcloud command" {
  run_gssh -d my-vm test-project-1 us-central1-a
  [ "$status" -eq 0 ]
  [[ "${output}" == *"gcloud compute ssh"* ]]
}

@test "--dry-run includes account flag" {
  export GSSH_ACCOUNTS="user@test.com"
  run_gssh --dry-run -a user@test.com my-vm test-project-1 us-central1-a
  [ "$status" -eq 0 ]
  [[ "${output}" == *"--account=user@test.com"* ]]
}

@test "--dry-run includes extra args after --" {
  run_gssh --dry-run my-vm test-project-1 us-central1-a -- -L 3306:localhost:3306
  [ "$status" -eq 0 ]
  [[ "${output}" == *"-L"* ]]
  [[ "${output}" == *"3306:localhost:3306"* ]]
}
