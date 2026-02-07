#!/usr/bin/env bash
set -euo pipefail

CLI_PATH="${CLI_PATH:-/Users/z/Documents/dev/ollama-cli-assistant/cli-assistant.sh}"
MODEL="${MODEL:-cli-assistant}"

if [[ ! -x "$CLI_PATH" ]]; then
  echo "ERROR: cli-assistant.sh not found or not executable: $CLI_PATH" >&2
  exit 1
fi

TMP_DIR="$(mktemp -d)"
cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

ORIG_PATH="$PATH"
PATH_WITH_GNU="$TMP_DIR:$ORIG_PATH"
PATH_NO_GNU="$TMP_DIR:/usr/bin:/bin:/usr/sbin:/sbin"
CLIPBOARD_FILE="$TMP_DIR/clipboard.txt"

# Fake ollama for deterministic integration tests.
cat > "$TMP_DIR/ollama" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

cmd="${1:-}"
case "$cmd" in
  show)
    exit 0
    ;;
  run)
    printf '%s\n' "${FAKE_OLLAMA_OUTPUT:-}"
    ;;
  *)
    echo "fake ollama: unsupported subcommand: $cmd" >&2
    exit 2
    ;;
esac
SH
chmod +x "$TMP_DIR/ollama"

# Fake clipboard commands to avoid dependency on system pasteboard access.
cat > "$TMP_DIR/pbcopy" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
cat > "${CLIPBOARD_FILE:?}"
SH
chmod +x "$TMP_DIR/pbcopy"

cat > "$TMP_DIR/pbpaste" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
if [[ -f "${CLIPBOARD_FILE:?}" ]]; then
  cat "${CLIPBOARD_FILE:?}"
fi
SH
chmod +x "$TMP_DIR/pbpaste"

have_cmd_in_path() {
  local bin="$1"
  local path_env="$2"
  PATH="$path_env" command -v "$bin" >/dev/null 2>&1
}

expected_copy_enabled() {
  local in="$1"
  local path_env="$2"

  case "$in" in
    'echo "0x65ff4b03" | xxd -r -p | date -f - +"%Y-%m-%d %H:%M:%S"')
      if have_cmd_in_path gdate "$path_env"; then
        printf '%s' 'gdate -d "@$((16#65ff4b03))" +"%Y-%m-%d %H:%M:%S"'
      else
        printf '%s' 'date -r $((16#65ff4b03)) +"%Y-%m-%d %H:%M:%S"'
      fi
      ;;
    'date -d "@1700000000" +"%Y-%m-%d %H:%M:%S"')
      if have_cmd_in_path gdate "$path_env"; then
        printf '%s' 'gdate -d "@1700000000" +"%Y-%m-%d %H:%M:%S"'
      else
        printf '%s' 'date -r 1700000000 +"%Y-%m-%d %H:%M:%S"'
      fi
      ;;
    "sed -i 's/foo/bar/g' test.txt")
      if have_cmd_in_path gsed "$path_env"; then
        printf '%s' "gsed -i 's/foo/bar/g' test.txt"
      else
        printf '%s' "sed -i '' 's/foo/bar/g' test.txt"
      fi
      ;;
    "grep -P 'a.*b' sample.txt")
      if have_cmd_in_path ggrep "$path_env"; then
        printf '%s' "ggrep -P 'a.*b' sample.txt"
      else
        printf '%s' "grep -P 'a.*b' sample.txt"
      fi
      ;;
    'readlink -f ./foo/bar')
      if have_cmd_in_path greadlink "$path_env"; then
        printf '%s' 'greadlink -f ./foo/bar'
      elif have_cmd_in_path realpath "$path_env"; then
        printf '%s' 'realpath ./foo/bar'
      else
        printf '%s' 'readlink -f ./foo/bar'
      fi
      ;;
    "stat -c '%s %n' test.txt")
      if have_cmd_in_path gstat "$path_env"; then
        printf '%s' "gstat -c '%s %n' test.txt"
      else
        printf '%s' 'stat -f "%z %N" test.txt'
      fi
      ;;
    "find . -maxdepth 2 -printf '%p\\n'")
      if have_cmd_in_path gfind "$path_env"; then
        printf '%s' "gfind . -maxdepth 2 -printf '%p\\n'"
      else
        printf '%s' 'find . -maxdepth 2 -print'
      fi
      ;;
    "echo -e 'a\\nb\\n' | xargs -r -n1 echo")
      printf '%s' "echo -e 'a\\nb\\n' | xargs -n1 echo"
      ;;
    "sudo date -d '@1'")
      printf '%s' "sudo date -d '@1'"
      ;;
    'ls -al')
      printf '%s' 'ls -al'
      ;;
    *)
      printf '%s' "$in"
      ;;
  esac
}

assert_eq() {
  local want="$1"
  local got="$2"
  local msg="$3"
  if [[ "$want" == "$got" ]]; then
    printf 'PASS: %s\n' "$msg"
    return 0
  fi
  printf 'FAIL: %s\n' "$msg"
  printf '  want: %s\n' "$want"
  printf '  got : %s\n' "$got"
  return 1
}

prepare_fixtures() {
  local work_dir="$1"
  rm -rf "$work_dir"
  mkdir -p "$work_dir/foo"
  printf '%s\n' 'foo line' 'alpha' > "$work_dir/test.txt"
  printf '%s\n' 'acb' 'zzz' > "$work_dir/sample.txt"
  printf '%s\n' 'nested' > "$work_dir/foo/bar"
}

smoke_exec_if_safe() {
  local cmd="$1"
  local path_env="$2"
  local work_dir="$3"
  local mode_label="$4"

  # Skip smoke when command is expected to remain potentially unsupported by design.
  if printf '%s\n' "$cmd" | grep -Eq '\bgrep\s+-P\b|\breadlink\s+-f\b|\bsudo\b'; then
    printf 'SKIP: smoke (%s)\n' "$mode_label"
    return 0
  fi

  set +e
  PATH="$path_env" zsh -lc "cd '$work_dir' && $cmd" >"$work_dir/smoke.out" 2>&1
  local rc=$?
  set -e

  if [[ $rc -eq 0 ]]; then
    printf 'PASS: smoke (%s)\n' "$mode_label"
    return 0
  fi

  printf 'FAIL: smoke (%s)\n' "$mode_label"
  cat "$work_dir/smoke.out"
  return 1
}

run_case_mode() {
  local idx="$1"
  local input_cmd="$2"
  local mode_name="$3"
  local path_env="$4"
  local failures=0
  local stdout_file="$TMP_DIR/stdout_${idx}_${mode_name}.txt"
  local work_dir="$TMP_DIR/work_${idx}_${mode_name}"

  echo "-- mode: $mode_name"

  # fix enabled
  FAKE_OLLAMA_OUTPUT="$input_cmd" \
  CLIA_CLIPBOARD_FIX=1 \
  CLIPBOARD_FILE="$CLIPBOARD_FILE" \
  PATH="$path_env" \
  "$CLI_PATH" -m "$MODEL" "dummy prompt" >"$stdout_file"

  local printed_enabled copied_enabled expected_enabled
  printed_enabled="$(cat "$stdout_file")"
  copied_enabled="$(CLIPBOARD_FILE="$CLIPBOARD_FILE" PATH="$path_env" pbpaste)"
  expected_enabled="$(expected_copy_enabled "$input_cmd" "$path_env")"

  assert_eq "$input_cmd" "$printed_enabled" "printed unchanged (fix=1, $mode_name)" || failures=$((failures + 1))
  assert_eq "$expected_enabled" "$copied_enabled" "clipboard expected (fix=1, $mode_name)" || failures=$((failures + 1))

  prepare_fixtures "$work_dir"
  smoke_exec_if_safe "$copied_enabled" "$path_env" "$work_dir" "$mode_name/fix=1" || failures=$((failures + 1))

  # fix disabled
  FAKE_OLLAMA_OUTPUT="$input_cmd" \
  CLIA_CLIPBOARD_FIX=0 \
  CLIPBOARD_FILE="$CLIPBOARD_FILE" \
  PATH="$path_env" \
  "$CLI_PATH" -m "$MODEL" "dummy prompt" >"$stdout_file"

  local printed_disabled copied_disabled
  printed_disabled="$(cat "$stdout_file")"
  copied_disabled="$(CLIPBOARD_FILE="$CLIPBOARD_FILE" PATH="$path_env" pbpaste)"

  assert_eq "$input_cmd" "$printed_disabled" "printed unchanged (fix=0, $mode_name)" || failures=$((failures + 1))
  assert_eq "$input_cmd" "$copied_disabled" "clipboard unchanged (fix=0, $mode_name)" || failures=$((failures + 1))

  return "$failures"
}

run_case() {
  local idx="$1"
  local input_cmd="$2"
  local failures=0

  echo
  echo "=== CASE $idx ==="
  echo "input: $input_cmd"

  run_case_mode "$idx" "$input_cmd" "with_gnu" "$PATH_WITH_GNU" || failures=$((failures + 1))
  run_case_mode "$idx" "$input_cmd" "no_gnu" "$PATH_NO_GNU" || failures=$((failures + 1))

  return "$failures"
}

TEST_CASES=(
  'echo "0x65ff4b03" | xxd -r -p | date -f - +"%Y-%m-%d %H:%M:%S"'
  'date -d "@1700000000" +"%Y-%m-%d %H:%M:%S"'
  "sed -i 's/foo/bar/g' test.txt"
  "grep -P 'a.*b' sample.txt"
  'readlink -f ./foo/bar'
  "stat -c '%s %n' test.txt"
  "find . -maxdepth 2 -printf '%p\\n'"
  "echo -e 'a\\nb\\n' | xargs -r -n1 echo"
  "sudo date -d '@1'"
  'ls -al'
)

echo "Running clipboard integration tests"
echo "cli: $CLI_PATH"
echo "cases: ${#TEST_CASES[@]}"
echo "modes: with_gnu, no_gnu"

TOTAL=0
FAILED=0

for i in "${!TEST_CASES[@]}"; do
  TOTAL=$((TOTAL + 1))
  if ! run_case "$((i + 1))" "${TEST_CASES[$i]}"; then
    FAILED=$((FAILED + 1))
  fi
done

echo
if [[ "$FAILED" -eq 0 ]]; then
  echo "RESULT: PASS ($TOTAL/$TOTAL cases)"
  exit 0
fi

echo "RESULT: FAIL ($FAILED failed of $TOTAL cases)"
exit 1
