# Common setup for all gssh tests

setup() {
  export TEST_TEMP_DIR="$(mktemp -d)"
  export GSSH_CACHE_FILE="${TEST_TEMP_DIR}/cache/vms"
  export GSSH_PROJECTS="test-project-1"
  export GSSH_ZONES="us-central1-a"
  export GSSH_ACCOUNTS=""
  export GSSH_EXCLUDE_PREFIXES=""
  export GSSH_CACHE_TTL=86400

  # Stub gcloud
  mkdir -p "${TEST_TEMP_DIR}/bin"
  cat > "${TEST_TEMP_DIR}/bin/gcloud" << 'STUB'
#!/usr/bin/env bash
if [[ "$*" == *"instances list"* ]]; then
  echo "vm-web-01"
  echo "vm-api-01"
  echo "vm-db-01"
  exit 0
fi
if [[ "$*" == *"compute ssh"* ]]; then
  echo "MOCK_SSH: $*"
  exit 0
fi
if [[ "$*" == *"config get-value project"* ]]; then
  echo "default-project"
  exit 0
fi
echo "gcloud mock: unhandled: $*" >&2
exit 1
STUB
  chmod +x "${TEST_TEMP_DIR}/bin/gcloud"
  export PATH="${TEST_TEMP_DIR}/bin:$PATH"

  export GSSH_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
}

teardown() {
  rm -rf "$TEST_TEMP_DIR"
}

# Helper: run gssh in zsh subshell with test env
run_gssh() {
  run zsh -c "
    export GSSH_PROJECTS='${GSSH_PROJECTS}'
    export GSSH_ZONES='${GSSH_ZONES}'
    export GSSH_ACCOUNTS='${GSSH_ACCOUNTS}'
    export GSSH_EXCLUDE_PREFIXES='${GSSH_EXCLUDE_PREFIXES}'
    export GSSH_CACHE_FILE='${GSSH_CACHE_FILE}'
    export GSSH_CACHE_TTL='${GSSH_CACHE_TTL}'
    export PATH='${TEST_TEMP_DIR}/bin:${PATH}'
    source '${GSSH_ROOT}/gssh.zsh'
    gssh $*
  "
}
