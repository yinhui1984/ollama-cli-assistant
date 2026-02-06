#!/usr/bin/env bash
set -euo pipefail

MODEL="cli-assistant"
OUTPUT_FILE=""
CASES_FILE=""
ROOT_DIR="/Users/z/Documents/dev/ollama-cli-assistant"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_CASES_FILE="$ROOT_DIR/model/04_cases_holdout.txt"
CONTEXT_PREFIX="${CONTEXT_PREFIX:-Runtime: macOS (Darwin), shell zsh. Return one executable command only. User request: }"

usage() {
  echo "Usage: $0 [-m MODEL] [-o OUTPUT_FILE] [-c CASES_FILE]"
  echo "  -m, --model      model name (default: cli-assistant)"
  echo "  -o, --output     output file path (default: $ROOT_DIR/model/batch_results_YYYYmmdd_HHMMSS.txt)"
  echo "  -c, --cases      text file with one prompt per line"
  echo "Default cases file: $DEFAULT_CASES_FILE"
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
    -c|--cases)
      [[ $# -ge 2 ]] || { echo "Error: --cases needs a value." >&2; exit 1; }
      CASES_FILE="$2"
      shift 2
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

if ! command -v ollama >/dev/null 2>&1; then
  echo "Error: ollama command not found." >&2
  exit 1
fi

if ! ollama show "$MODEL" >/dev/null 2>&1; then
  echo "Error: model '$MODEL' not found." >&2
  echo "Build example:" >&2
  echo "  ollama create $MODEL -f $SCRIPT_DIR/ollama-cli-assistant.Modelfile" >&2
  exit 1
fi

if [[ -z "$CASES_FILE" ]]; then
  CASES_FILE="$DEFAULT_CASES_FILE"
fi

if [[ ! -f "$CASES_FILE" ]]; then
  echo "Error: cases file not found: $CASES_FILE" >&2
  exit 1
fi

PROMPTS=()
while IFS= read -r line || [[ -n "$line" ]]; do
  case "$line" in
    "" )
      continue
      ;;
    \#*)
      continue
      ;;
  esac
  PROMPTS+=("$line")
done < "$CASES_FILE"

if [[ ${#PROMPTS[@]} -eq 0 ]]; then
  echo "Error: no test cases found in $CASES_FILE" >&2
  exit 1
fi

if [[ -z "$OUTPUT_FILE" ]]; then
  OUTPUT_FILE="$ROOT_DIR/model/batch_results_$(date +%Y%m%d_%H%M%S).txt"
fi

strip_ansi() {
  sed -E $'s/\x1B\[[0-9;?]*[ -/]*[@-~]//g'
}

{
  echo "Batch Test"
  echo "Model: $MODEL"
  echo "Time: $(date '+%Y-%m-%d %H:%M:%S')"
  echo "Cases File: $CASES_FILE"
  echo "Cases: ${#PROMPTS[@]}"
  echo "Context Prefix: $CONTEXT_PREFIX"
  echo
} > "$OUTPUT_FILE"

for i in "${!PROMPTS[@]}"; do
  n=$((i + 1))
  prompt="${PROMPTS[$i]}"
  full_prompt="${CONTEXT_PREFIX}${prompt}"
  stderr_file="$(mktemp)"

  set +e
  stdout_output="$(ollama run "$MODEL" "$full_prompt" 2>"$stderr_file")"
  status=$?
  set -e

  stderr_output="$(cat "$stderr_file")"
  rm -f "$stderr_file"

  if [[ $status -eq 0 ]]; then
    raw_output="$stdout_output"
  else
    raw_output="$stdout_output"
    if [[ -n "$stderr_output" ]]; then
      raw_output="$raw_output
$stderr_output"
    fi
  fi

  clean_output="$(printf '%s\n' "$raw_output" | strip_ansi | tr -d '\r')"

  {
    printf '=== CASE %02d ===\n' "$n"
    echo "PROMPT: $prompt"
    echo "EXIT_CODE: $status"
    echo "OUTPUT:"
    echo "$clean_output"
    echo
  } | tee -a "$OUTPUT_FILE"
done

echo "Saved results: $OUTPUT_FILE"
