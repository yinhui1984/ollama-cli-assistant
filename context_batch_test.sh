#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ASSISTANT_SCRIPT="$SCRIPT_DIR/cli-assistant.sh"
MODEL="cli-assistant"
OUTPUT_FILE=""
PRINT_FINAL_PROMPT=1

usage() {
  cat <<'USAGE'
Usage:
  context_batch_test.sh [-m MODEL] [-o OUTPUT_FILE] [--no-print-final-prompt]

Options:
  -m, --model MODEL          Model name (default: cli-assistant)
  -o, --output FILE          Output report path
  --no-print-final-prompt    Do not pass --print-final-prompt to cli-assistant.sh
  -h, --help                 Show this help
USAGE
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

if [[ -z "$OUTPUT_FILE" ]]; then
  OUTPUT_FILE="$SCRIPT_DIR/context_batch_results_$(date +%Y%m%d_%H%M%S).txt"
fi

TMPDIR_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_ROOT"' EXIT

EMPTY_CONTEXT_FILE="$TMPDIR_ROOT/empty_context.md"
touch "$EMPTY_CONTEXT_FILE"

FILE_CONTEXT_ETH="$TMPDIR_ROOT/context_eth.md"
cat > "$FILE_CONTEXT_ETH" <<'EOF'
- 使用 "$RPC_ETH" 作为 eth mainnet rpc
- 使用 "$APIKEY_DEEPSEEK" 作为 deepseek 的 API key
EOF

FILE_CONTEXT_BSC="$TMPDIR_ROOT/context_bsc.md"
cat > "$FILE_CONTEXT_BSC" <<'EOF'
- 使用 "$RPC_BSC" 作为 eth mainnet rpc
EOF

INLINE_CONTEXT_ETH='- 使用 "$RPC_ETH" 作为 eth mainnet rpc'
INLINE_CONTEXT_DEEPSEEK='- 使用 "$APIKEY_DEEPSEEK" 作为 deepseek 的 API key'
INLINE_CONTEXT_CONFLICT='- 使用 "$RPC_ETH" 作为 eth mainnet rpc'

append_header() {
  {
    echo "Context Batch Test"
    echo "Time: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "Model: $MODEL"
    echo "Assistant Script: $ASSISTANT_SCRIPT"
    echo "Output File: $OUTPUT_FILE"
    echo
    echo "Env probe:"
    for var_name in RPC_ETH RPC_BSC APIKEY_DEEPSEEK; do
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
  local case_name="$1"
  local prompt="$2"
  shift 2
  local -a cmd=("$ASSISTANT_SCRIPT" "-m" "$MODEL")
  local stdout_file
  local stderr_file
  local rc

  if [[ "$PRINT_FINAL_PROMPT" -eq 1 ]]; then
    cmd+=("--print-final-prompt")
  fi
  if [[ $# -gt 0 ]]; then
    cmd+=("$@")
  fi
  cmd+=("$prompt")

  stdout_file="$(mktemp)"
  stderr_file="$(mktemp)"

  set +e
  "${cmd[@]}" >"$stdout_file" 2>"$stderr_file"
  rc=$?
  set -e

  {
    echo "=== CASE: $case_name ==="
    echo "PROMPT: $prompt"
    echo "CMD: ${cmd[*]}"
    echo "EXIT_CODE: $rc"
    echo "--- STDERR ---"
    cat "$stderr_file"
    echo "--- STDOUT ---"
    cat "$stdout_file"
    echo
  } | tee -a "$OUTPUT_FILE"

  rm -f "$stdout_file" "$stderr_file"
}

append_header

run_case \
  "default_context_file" \
  "fork eth主网 区块 17000000"

run_case \
  "inline_only_eth" \
  "fork eth主网 区块 17000000" \
  --context-file "$EMPTY_CONTEXT_FILE" \
  --context "$INLINE_CONTEXT_ETH"

run_case \
  "context_file_only_eth" \
  "fork eth主网 区块 17000000" \
  --context-file "$FILE_CONTEXT_ETH"

run_case \
  "context_file_plus_inline_conflict" \
  "fork eth主网 区块 17000000" \
  --context-file "$FILE_CONTEXT_BSC" \
  --context "$INLINE_CONTEXT_CONFLICT"

run_case \
  "inline_only_deepseek" \
  "调用 deepseek 的 chat 接口，使用 curl 发一个最小请求示例" \
  --context-file "$EMPTY_CONTEXT_FILE" \
  --context "$INLINE_CONTEXT_DEEPSEEK"

run_case \
  "empty_context_file_no_inline" \
  "fork eth主网 区块 17000000" \
  --context-file "$EMPTY_CONTEXT_FILE"

echo "Saved results: $OUTPUT_FILE"
