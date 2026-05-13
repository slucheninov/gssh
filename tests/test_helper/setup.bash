# Common setup for all gssh tests

setup() {
  export TEST_TEMP_DIR="$(mktemp -d)"
  export GSSH_CACHE_FILE="${TEST_TEMP_DIR}/cache/vms"
  export GSSH_PROJECTS="test-project-1"
  export GSSH_ZONES="us-central1-a"
  export GSSH_ACCOUNTS=""
  export GSSH_EXCLUDE_PREFIXES=""
  export GSSH_CACHE_TTL=86400
  export GSSH_MOCK_FAIL_LIST=0
  unset GSSH_HOME
  unset GSSH_MOCK_FAIL_DOWNLOAD

  # Stub gcloud
  mkdir -p "${TEST_TEMP_DIR}/bin"
  cat > "${TEST_TEMP_DIR}/bin/gcloud" << 'STUB'
#!/usr/bin/env bash
if [[ "$*" == *"auth list"* ]]; then
  if [[ -n "${GSSH_MOCK_AUTHED_ACCOUNTS:-}" ]]; then
    echo "$GSSH_MOCK_AUTHED_ACCOUNTS"
  else
    echo "user@test.com"
  fi
  exit 0
fi
if [[ "$*" == *"instances list"* ]]; then
  if [[ "${GSSH_MOCK_FAIL_LIST:-0}" == "1" ]]; then
    echo "mock list failure" >&2
    exit 1
  fi

  # Multi-account mock: per-account/project data from files
  if [[ -n "${GSSH_MOCK_DATA_DIR:-}" ]]; then
    _mock_account=""
    _mock_project=""
    for _arg in "$@"; do
      case "$_arg" in
        --account=*) _mock_account="${_arg#--account=}" ;;
        --project=*) _mock_project="${_arg#--project=}" ;;
      esac
    done
    _mock_key="${_mock_account}__${_mock_project}"
    if [[ -f "${GSSH_MOCK_DATA_DIR}/${_mock_key}" ]]; then
      cat "${GSSH_MOCK_DATA_DIR}/${_mock_key}"
      exit 0
    else
      echo "ERROR: permission denied for project ${_mock_project}" >&2
      exit 1
    fi
  fi

  echo "vm-web-01 us-central1-a"
  echo "vm-api-01 us-central1-a"
  echo "vm-db-01 us-central1-b"
  echo "vm.db-01 us-central1-c"
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
  run zsh -c '
    export PATH="${TEST_TEMP_DIR}/bin:${PATH}"
    source "${GSSH_ROOT}/gssh.zsh"
    gssh "$@"
  ' gssh-test "$@"
}
