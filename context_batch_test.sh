#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ASSISTANT_SCRIPT="$SCRIPT_DIR/cli-assistant.sh"
MODEL="cli-assistant"
OUTPUT_FILE=""
PRINT_FINAL_PROMPT=1
CASES_FILE="$SCRIPT_DIR/context_batch_cases_holdout.txt"

CASE_PROMPTS=()
CASE_CONTEXTS=()

usage() {
  cat <<'USAGE'
Usage:
  context_batch_test.sh [-m MODEL] [-o OUTPUT_FILE] [--cases FILE] [--no-print-final-prompt]

Cases format (one case per line):
  1) prompt
  2) context ||| prompt

Rules:
  - Blank lines and lines starting with # are ignored.
  - If a case has context (format #2), script injects it with --context.
  - Context cases are run with an empty --context-file to avoid default file interference.

Options:
  -m, --model MODEL          Model name (default: cli-assistant)
  -o, --output FILE          Output report path
  --cases FILE               Cases file path (default: ./context_batch_cases_holdout.txt)
  --no-print-final-prompt    Do not pass --print-final-prompt to cli-assistant.sh
  -h, --help                 Show this help
USAGE
}

trim() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -m|--model)
      [[ $# -ge 2 ]] || { echo "Error: --model needs a value." >&2; exit 1; }
      MODEL="$2"
      shift 2
      ;;
    -o|--output)
      [[ $# -ge 2 ]] || { echo "Error: --output needs a value." >&2; exit 1; }
      OUTPUT_FILE="$2"
      shift 2
      ;;
    --cases)
      [[ $# -ge 2 ]] || { echo "Error: --cases needs a value." >&2; exit 1; }
      CASES_FILE="$2"
      shift 2
      ;;
    --no-print-final-prompt)
      PRINT_FINAL_PROMPT=0
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Error: unknown argument '$1'" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ ! -x "$ASSISTANT_SCRIPT" ]]; then
  echo "Error: cli-assistant.sh not found or not executable: $ASSISTANT_SCRIPT" >&2
  exit 1
fi

if [[ ! -f "$CASES_FILE" ]]; then
  echo "Error: cases file not found: $CASES_FILE" >&2
  exit 1
fi

if [[ -z "$OUTPUT_FILE" ]]; then
  OUTPUT_FILE="$SCRIPT_DIR/context_batch_results_$(date +%Y%m%d_%H%M%S).txt"
fi

TMPDIR_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_ROOT"' EXIT

EMPTY_CONTEXT_FILE="$TMPDIR_ROOT/empty_context.md"
touch "$EMPTY_CONTEXT_FILE"

load_cases() {
  local raw_line
  local line
  local prompt
  local context

  while IFS= read -r raw_line || [[ -n "$raw_line" ]]; do
    line="$(trim "$raw_line")"
    [[ -z "$line" ]] && continue
    [[ "$line" == \#* ]] && continue

    if [[ "$line" == *"|||"* ]]; then
      context="$(trim "${line%%|||*}")"
      prompt="$(trim "${line#*|||}")"
    else
      context=""
      prompt="$line"
    fi

    [[ -z "$prompt" ]] && continue
    CASE_PROMPTS+=("$prompt")
    CASE_CONTEXTS+=("$context")
  done < "$CASES_FILE"

  if [[ ${#CASE_PROMPTS[@]} -eq 0 ]]; then
    echo "Error: no runnable cases found in $CASES_FILE" >&2
    exit 1
  fi
}

append_header() {
  {
    echo "Context Batch Test"
    echo "Time: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "Model: $MODEL"
    echo "Assistant Script: $ASSISTANT_SCRIPT"
    echo "Cases File: $CASES_FILE"
    echo "Cases: ${#CASE_PROMPTS[@]}"
    echo "Output File: $OUTPUT_FILE"
    echo
    echo "Env probe:"
    for var_name in RPC_ETH RPC_BSC APIKEY_DEEPSEEK RPC_SEPOLIA ETHERSCAN_API_KEY; do
      if [[ "${!var_name+x}" == "x" ]]; then
        echo "  $var_name=SET"
      else
        echo "  $var_name=UNSET"
      fi
    done
    echo
  } > "$OUTPUT_FILE"
}

run_case() {
  local case_num="$1"
  local prompt="$2"
  local context="$3"
  local -a cmd=("$ASSISTANT_SCRIPT" "-m" "$MODEL")
  local stdout_file
  local stderr_file
  local rc
  local cmd_text
  local context_label

  if [[ "$PRINT_FINAL_PROMPT" -eq 1 ]]; then
    cmd+=("--print-final-prompt")
  fi

  if [[ -n "${context//[[:space:]]/}" ]]; then
    cmd+=("--context-file" "$EMPTY_CONTEXT_FILE" "--context" "$context")
    context_label="$context"
  else
    context_label="<none>"
  fi

  cmd+=("$prompt")

  stdout_file="$(mktemp)"
  stderr_file="$(mktemp)"

  set +e
  "${cmd[@]}" >"$stdout_file" 2>"$stderr_file"
  rc=$?
  set -e

  cmd_text="${cmd[*]}"

  {
    printf '=== CASE %03d ===\n' "$case_num"
    echo "PROMPT: $prompt"
    echo "CONTEXT: $context_label"
    echo "CMD: $cmd_text"
    echo "EXIT_CODE: $rc"
    echo "--- STDERR ---"
    cat "$stderr_file"
    echo "--- STDOUT ---"
    cat "$stdout_file"
    echo
  } | tee -a "$OUTPUT_FILE"

  rm -f "$stdout_file" "$stderr_file"
}

load_cases
append_header

for i in "${!CASE_PROMPTS[@]}"; do
  run_case "$((i + 1))" "${CASE_PROMPTS[$i]}" "${CASE_CONTEXTS[$i]}"
done

echo "Saved results: $OUTPUT_FILE"
