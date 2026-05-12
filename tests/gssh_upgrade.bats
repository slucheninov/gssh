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

printf 'downloaded %s\n' "$name" >"$dest"
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
  [ "$(cat "${GSSH_HOME}/gssh.zsh")" = "downloaded gssh.zsh" ]
  [ "$(cat "${GSSH_HOME}/_gssh")" = "downloaded _gssh" ]
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
