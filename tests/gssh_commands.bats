#!/usr/bin/env bats

load test_helper/setup

@test "ssh connects with all arguments" {
  run_gssh test-vm test-project-1 us-central1-a
  [ "$status" -eq 0 ]
  [[ "${output}" == *"MOCK_SSH"* ]]
  [[ "${output}" == *"test-vm"* ]]
}

@test "ssh enables gcloud Python site packages for IAP acceleration" {
  run_gssh test-vm test-project-1 us-central1-a
  [ "$status" -eq 0 ]
  [[ "${output}" == *"site packages: 1"* ]]
}

@test "extra args passed after --" {
  run_gssh test-vm test-project-1 us-central1-a -- -L 3306:localhost:3306
  [ "$status" -eq 0 ]
  [[ "${output}" == *"-L"* ]]
  [[ "${output}" == *"3306:localhost:3306"* ]]
}

@test "-c runs a remote command" {
  run_gssh test-vm -c "uptime -a"
  [ "$status" -eq 0 ]
  [[ "${output}" == *"--command=uptime -a"* ]]
}

@test "--command preserves shell metacharacters as one gcloud argument" {
  run_gssh test-vm test-project-1 us-central1-a --command "echo 'hello world' && uptime -a"
  [ "$status" -eq 0 ]
  [[ "${output}" == *"--command=echo 'hello world' && uptime -a"* ]]
}

@test "--account flag passes account to gcloud" {
  run_gssh -a user@test.com test-vm test-project-1 us-central1-a
  [ "$status" -eq 0 ]
  [[ "${output}" == *"account: user@test.com"* ]]
  [[ "${output}" == *"MOCK_SSH"* ]]
  [[ "${output}" == *"--account=user@test.com"* ]]
}

@test "connecting message includes vm, project, zone" {
  run_gssh test-vm my-project us-central1-a
  [ "$status" -eq 0 ]
  [[ "${output}" == *"connecting to test-vm"* ]]
  [[ "${output}" == *"project: my-project"* ]]
  [[ "${output}" == *"zone: us-central1-a"* ]]
}
