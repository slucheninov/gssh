#!/usr/bin/env bats

load test_helper/setup

@test "installer installs NumPy for gcloud Python when it is missing" {
  cat >"${TEST_TEMP_DIR}/bin/gcloud" <<'STUB'
#!/usr/bin/env bash
if [[ "$*" == *"info --format=value(basic.python_location)"* ]]; then
  echo "${TEST_TEMP_DIR}/bin/gcloud-python"
  exit 0
fi
exit 1
STUB
  cat >"${TEST_TEMP_DIR}/bin/gcloud-python" <<'STUB'
#!/usr/bin/env bash
if [[ "$1" == "-c" ]]; then
  exit 1
fi
if [[ "$1" == "-m" && "$2" == "pip" && "$3" == "install" && "$4" == "numpy" ]]; then
  touch "${TEST_TEMP_DIR}/numpy-installed"
  exit 0
fi
exit 1
STUB
  chmod +x "${TEST_TEMP_DIR}/bin/gcloud" "${TEST_TEMP_DIR}/bin/gcloud-python"
  mkdir -p "${TEST_TEMP_DIR}/home"

  run bash -c 'printf "n\n" | HOME="$TEST_TEMP_DIR/home" PATH="$TEST_TEMP_DIR/bin:$PATH" bash "$GSSH_ROOT/install.sh"'

  [ "$status" -eq 0 ]
  [ -f "${TEST_TEMP_DIR}/numpy-installed" ]
  [[ "${output}" == *"IAP acceleration: NumPy installed."* ]]
}
