#!/usr/bin/env bats

load test_helper/setup

install_mock_curl() {
  cat >"${TEST_TEMP_DIR}/bin/curl" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail

url=""
dest=""

while (($# > 0)); do
  case "$1" in
    -o)
      dest="$2"
      shift 2
      ;;
    -*)
      shift
      ;;
    *)
      url="$1"
      shift
      ;;
  esac
done

name="${url##*/}"
if [[ "${GSSH_MOCK_FAIL_DOWNLOAD:-}" == "$name" ]]; then
  exit 1
fi

cp "${GSSH_ROOT}/$name" "$dest"
STUB
  chmod +x "${TEST_TEMP_DIR}/bin/curl"
}

@test "--upgrade replaces files after all downloads succeed" {
  install_mock_curl
  export GSSH_HOME="${TEST_TEMP_DIR}/install"
  mkdir -p "$GSSH_HOME"
  printf 'old gssh\n' >"${GSSH_HOME}/gssh.zsh"
  printf 'old completion\n' >"${GSSH_HOME}/_gssh"

  run_gssh --upgrade

  [ "$status" -eq 0 ]
  [[ "${output}" == *"gssh.zsh: updated"* ]]
  [[ "${output}" == *"_gssh: updated"* ]]
  cmp "${GSSH_ROOT}/gssh.zsh" "${GSSH_HOME}/gssh.zsh"
  cmp "${GSSH_ROOT}/_gssh" "${GSSH_HOME}/_gssh"
}

@test "--upgrade leaves installed files untouched when one download fails" {
  install_mock_curl
  export GSSH_HOME="${TEST_TEMP_DIR}/install"
  export GSSH_MOCK_FAIL_DOWNLOAD="_gssh"
  mkdir -p "$GSSH_HOME"
  printf 'old gssh\n' >"${GSSH_HOME}/gssh.zsh"
  printf 'old completion\n' >"${GSSH_HOME}/_gssh"

  run_gssh --upgrade

  [ "$status" -eq 1 ]
  [[ "${output}" == *"failed to download _gssh"* ]]
  [ "$(cat "${GSSH_HOME}/gssh.zsh")" = "old gssh" ]
  [ "$(cat "${GSSH_HOME}/_gssh")" = "old completion" ]
}

@test "--upgrade reloads stale functions even when installed files are current" {
  install_mock_curl
  export GSSH_HOME="${TEST_TEMP_DIR}/install"
  mkdir -p "$GSSH_HOME"
  cp "${GSSH_ROOT}/gssh.zsh" "${GSSH_ROOT}/_gssh" "$GSSH_HOME/"

  run zsh -c '
    source "$GSSH_ROOT/gssh.zsh"
    GSSH_VERSION=1.1.8
    _gssh_valid_instance() { return 1; }
    _gssh() { print old-completion; }
    gssh --upgrade || exit
    gssh --version
    _gssh_valid_instance vm-web-01 us-central1-a
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"already at the latest version"* ]]
  version=$(sed -n 's/^GSSH_VERSION="\(.*\)"$/\1/p' "${GSSH_ROOT}/gssh.zsh")
  [[ "$output" == *"gssh $version"* ]]
  [[ "$output" != *"gssh 1.1.8"* ]]
}
