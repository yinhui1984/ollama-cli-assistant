#!/usr/bin/env bash
set -euo pipefail

MODEL="deepseek-chat"
API_ENDPOINT="${DEEPSEEK_API_ENDPOINT:-https://api.deepseek.com/chat/completions}"
INTERACTIVE=0
DEBUG=0
STREAM_MODE="auto"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
CONTEXT_FILE="$SCRIPT_DIR/context.md"
CONTEXT_FILE_EXPLICIT=0
CONTEXT_INLINE=""
CONTEXT_INLINE_EXPLICIT=0
MODELFILE_PATH="$SCRIPT_DIR/model/ollama-cli-assistant.Modelfile"
SYSTEM_PROMPT=""

usage() {
  cat <<'USAGE'
Usage:
  cli-assistant-deepseek.sh [-i] [-m MODEL] [--context TEXT] [--context-file FILE] [--api-endpoint URL] [--debug] [--stream|--no-stream] [PROMPT...]

Modes:
  1) Interactive mode (-i)
     cli-assistant-deepseek.sh -i

  2) Non-interactive mode
     cli-assistant-deepseek.sh "查找 app 名称为 Visual Studio Code"
     echo "查看 8545 端口是否被监听" | cli-assistant-deepseek.sh

Options:
  -i, --interactive   Start interactive REPL mode
  -m, --model MODEL   DeepSeek model name (default: deepseek-chat)
  --api-endpoint URL  DeepSeek API endpoint (default: https://api.deepseek.com/chat/completions)
  --context TEXT      Inline context instructions string
  -c, --context-file FILE
                      Context file path (default: <script_dir>/context.md)
  --debug             Print final prompt and timing diagnostics to stderr
  --stream            Force streaming model output to stdout
  --no-stream         Force buffered/sanitized single-line output
  -h, --help          Show this help

Environment:
  APIKEY_DEEPSEEK     DeepSeek API key (required)
USAGE
}

now_ms() {
  perl -MTime::HiRes=time -e 'printf "%.3f\n", time()*1000'
}

elapsed_ms() {
  local start_ms="$1"
  local end_ms="$2"
  awk -v s="$start_ms" -v e="$end_ms" 'BEGIN { printf "%.3f", (e - s) }'
}

debug_log() {
  if [[ "$DEBUG" -eq 1 ]]; then
    printf '[debug] %s\n' "$1" >&2
  fi
}

extract_system_prompt() {
  python3 - "$MODELFILE_PATH" <<'PY'
import re
import sys

path = sys.argv[1]
with open(path, "r", encoding="utf-8") as f:
    text = f.read()

m = re.search(r'(?ms)^SYSTEM\s+"""\n?(.*?)\n?"""', text)
if not m:
    sys.exit(1)

print(m.group(1), end="")
PY
}

require_deepseek() {
  if ! command -v curl >/dev/null 2>&1; then
    echo "Error: curl command not found." >&2
    exit 1
  fi

  if ! command -v python3 >/dev/null 2>&1; then
    echo "Error: python3 command not found." >&2
    exit 1
  fi

  if [[ -z "${APIKEY_DEEPSEEK:-}" ]]; then
    echo "Error: APIKEY_DEEPSEEK is not set." >&2
    exit 1
  fi

  if [[ ! -f "$MODELFILE_PATH" ]]; then
    echo "Error: Modelfile not found: $MODELFILE_PATH" >&2
    exit 1
  fi

  if ! SYSTEM_PROMPT="$(extract_system_prompt)"; then
    echo "Error: failed to extract SYSTEM prompt from $MODELFILE_PATH" >&2
    exit 1
  fi

  if [[ -z "${SYSTEM_PROMPT//[[:space:]]/}" ]]; then
    echo "Error: SYSTEM prompt extracted from $MODELFILE_PATH is empty." >&2
    exit 1
  fi
}

join_by_comma() {
  local out=""
  local item
  for item in "$@"; do
    if [[ -n "$out" ]]; then
      out+=", "
    fi
    out+="$item"
  done
  printf '%s' "$out"
}

collect_tool_availability() {
  local tools=(anvil forge cast ollama rg jq curl kubectl aws psql node python3 go git)
  local available=()
  local missing=()
  local tool

  for tool in "${tools[@]}"; do
    if command -v "$tool" >/dev/null 2>&1; then
      available+=("$tool")
    else
      missing+=("$tool")
    fi
  done

  printf 'available_tools: %s\n' "$(join_by_comma "${available[@]}")"
  printf 'missing_tools: %s\n' "$(join_by_comma "${missing[@]}")"
}

extract_context_env_vars() {
  local context_text="$1"
  if [[ -z "${context_text//[[:space:]]/}" ]]; then
    return 0
  fi
  printf '%s\n' "$context_text" | grep -oE '\$[A-Za-z_][A-Za-z0-9_]*' | LC_ALL=C sort -u || true
}

build_context_var_hints() {
  local context_vars="$1"
  local present=()
  local missing=()
  local token

  if [[ -z "${context_vars//[[:space:]]/}" ]]; then
    cat <<'EOT'
context_env_vars: none
context_env_vars_present: none
context_env_vars_missing: none
EOT
    return
  fi

  while IFS= read -r token; do
    [[ -z "$token" ]] && continue
    local var_name="${token#\$}"
    if [[ "${!var_name+x}" == "x" ]]; then
      present+=("$token")
    else
      missing+=("$token")
    fi
  done <<< "$context_vars"

  printf 'context_env_vars: %s\n' "$(join_by_comma ${context_vars//$'\n'/ })"
  if [[ ${#present[@]} -gt 0 ]]; then
    printf 'context_env_vars_present: %s\n' "$(join_by_comma "${present[@]}")"
  else
    printf 'context_env_vars_present: none\n'
  fi

  if [[ ${#missing[@]} -gt 0 ]]; then
    printf 'context_env_vars_missing: %s\n' "$(join_by_comma "${missing[@]}")"
  else
    printf 'context_env_vars_missing: none\n'
  fi
}

sanitize_model_output() {
  local raw_output="$1"
  local normalized
  local command_line=""
  local line
  local trimmed
  local first_non_empty_seen=0

  normalized="$(printf '%s\n' "$raw_output" | tr -d '\r')"

  while IFS= read -r line; do
    trimmed="$(printf '%s' "$line" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
    [[ -z "$trimmed" ]] && continue

    if [[ "$first_non_empty_seen" -eq 0 ]]; then
      command_line="$trimmed"
      first_non_empty_seen=1
      continue
    fi

    case "$trimmed" in
      \`\`\`*|"Explanation:"*|"解释："*|"解释:"*)
        break
        ;;
    esac

    if [[ "$command_line" =~ (\\|&&|\|\||\|)$ || "$command_line" =~ [\(\[]$ || "$trimmed" == --* || "$trimmed" == \$* ]]; then
      command_line="$command_line $trimmed"
      continue
    fi

    local single_quotes_count
    local double_quotes_count
    single_quotes_count="$(printf '%s' "$command_line" | tr -cd "'" | wc -c | tr -d '[:space:]')"
    double_quotes_count="$(printf '%s' "$command_line" | tr -cd '"' | wc -c | tr -d '[:space:]')"
    if (( single_quotes_count % 2 == 1 || double_quotes_count % 2 == 1 )); then
      command_line="$command_line $trimmed"
      continue
    fi

    break
  done <<< "$normalized"

  command_line="${command_line#\`}"
  command_line="${command_line%\`}"
  command_line="$(printf '%s' "$command_line" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
  printf '%s' "$command_line"
}

build_runtime_context() {
  local os_name
  local current_shell
  local current_cwd

  os_name="$(uname -s)"
  current_shell="${SHELL##*/}"
  current_cwd="$(pwd -P)"

  cat <<EOT
os: $os_name
target_shell: zsh
current_shell: $current_shell
cwd: $current_cwd
script_dir: $SCRIPT_DIR
$(collect_tool_availability)
EOT
}

build_deepseek_payload() {
  local user_prompt="$1"
  local stream_enabled="$2"

  SYSTEM_PROMPT="$SYSTEM_PROMPT" USER_PROMPT="$user_prompt" MODEL_NAME="$MODEL" STREAM_ENABLED="$stream_enabled" python3 - <<'PY'
import json
import os

payload = {
    "model": os.environ["MODEL_NAME"],
    "messages": [
        {"role": "system", "content": os.environ["SYSTEM_PROMPT"]},
        {"role": "user", "content": os.environ["USER_PROMPT"]},
    ],
    "temperature": 0,
    "stream": os.environ["STREAM_ENABLED"] == "1",
}

print(json.dumps(payload, ensure_ascii=False), end="")
PY
}

extract_response_content() {
  local response_file="$1"

  python3 - "$response_file" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as f:
    data = json.load(f)

content = data["choices"][0]["message"]["content"]
print(content, end="")
PY
}

extract_error_message() {
  local response_file="$1"

  python3 - "$response_file" <<'PY'
import json
import sys

try:
    with open(sys.argv[1], "r", encoding="utf-8") as f:
        data = json.load(f)
except Exception:
    print("(non-JSON error response)", end="")
    raise SystemExit(0)

if isinstance(data, dict):
    err = data.get("error")
    if isinstance(err, dict):
        msg = err.get("message")
        if msg:
            print(str(msg), end="")
            raise SystemExit(0)

print("(unknown API error)", end="")
PY
}

stream_deepseek_response() {
  local payload="$1"

  curl -sS -N -X POST "$API_ENDPOINT" \
    -H "Authorization: Bearer $APIKEY_DEEPSEEK" \
    -H 'Content-Type: application/json' \
    -d "$payload" | python3 -c '
import json
import sys

for line in sys.stdin:
    line = line.strip()
    if not line.startswith("data:"):
        continue

    chunk = line[5:].strip()
    if chunk == "[DONE]":
        break

    try:
        data = json.loads(chunk)
    except Exception:
        continue

    choices = data.get("choices") or []
    if not choices:
        continue

    delta = choices[0].get("delta") or {}
    text = delta.get("content")
    if not text:
        continue

    text = text.replace("\r", " ").replace("\n", " ")
    sys.stdout.write(text)
    sys.stdout.flush()
'
}

run_once() {
  local prompt="$1"
  local runtime_context
  local context_var_hints
  local context_vars=""
  local context_text=""
  local file_context_text=""
  local inline_context_text=""
  local context_status=""
  local context_source_label=""
  local full_prompt
  local raw_output
  local sanitized_output
  local t_start
  local t_runtime_done
  local t_context_done
  local t_prompt_done
  local t_model_start
  local t_model_done
  local t_sanitize_done
  local ttft_ms="N/A"
  local stream_enabled=0
  local payload
  local response_file
  local http_code
  local error_message

  t_start="$(now_ms)"
  runtime_context="$(build_runtime_context)"
  t_runtime_done="$(now_ms)"

  if [[ -f "$CONTEXT_FILE" ]]; then
    file_context_text="$(cat "$CONTEXT_FILE")"
    if [[ -n "${file_context_text//[[:space:]]/}" ]]; then
      context_text="[Context file: $CONTEXT_FILE]
$file_context_text"
      context_status="file_loaded"
    else
      context_status="file_empty"
    fi
  else
    context_status="file_not_found"
  fi

  if [[ "$CONTEXT_INLINE_EXPLICIT" -eq 1 ]]; then
    inline_context_text="$CONTEXT_INLINE"
    if [[ -n "${inline_context_text//[[:space:]]/}" ]]; then
      if [[ -n "${context_text//[[:space:]]/}" ]]; then
        context_text="$context_text

[Inline context (--context)]
$inline_context_text"
      else
        context_text="[Inline context (--context)]
$inline_context_text"
      fi

      if [[ "$context_status" == "file_loaded" ]]; then
        context_status="file_loaded+inline"
      elif [[ "$context_status" == "file_empty" ]]; then
        context_status="file_empty+inline"
      elif [[ "$context_status" == "file_not_found" ]]; then
        context_status="inline_only"
      fi
    else
      if [[ "$context_status" == "file_loaded" ]]; then
        context_status="file_loaded+inline_empty"
      elif [[ "$context_status" == "file_empty" ]]; then
        context_status="file_empty+inline_empty"
      elif [[ "$context_status" == "file_not_found" ]]; then
        context_status="inline_empty_only"
      fi
    fi
  fi

  if [[ -z "${context_text//[[:space:]]/}" ]]; then
    context_text="(no context instructions provided)"
  fi

  if [[ "$CONTEXT_INLINE_EXPLICIT" -eq 1 ]]; then
    context_source_label="$CONTEXT_FILE + --context"
  else
    context_source_label="$CONTEXT_FILE"
  fi

  context_vars="$(extract_context_env_vars "$context_text")"
  context_var_hints="$(build_context_var_hints "$context_vars")"
  t_context_done="$(now_ms)"

  full_prompt="Return exactly one executable zsh command line.
Instruction priority:
1) User request
2) Context instructions
3) Runtime context
Conflict resolution:
- If both file context and inline context are present, inline context (--context) has higher priority.
- When context instructions conflict, the later instruction is higher priority.
Context usage rules:
- Treat context instructions as durable user preferences and constraints.
- If context includes explicit env var tokens (for example \$RPC_ETH), use those exact tokens verbatim when relevant.
- Do not rename context-provided env vars into temporary aliases unless the user explicitly asks.
- Prefer direct usage (for example: anvil --fork-url \$RPC_ETH) over alias chains (for example: RPC_URL=\$RPC_ETH ... --fork-url \$RPC_URL).
- If a relevant context token exists, do not emit placeholders like REQUIRED_*.
- Preserve the exact task semantics from the user request. Do not replace the requested operation with a nearby but different command.
- Keep concrete entities unchanged when present: tool name, path, contract/test/function name, chain, block number, host/port, and git message text.
- Output must be one complete executable command line with balanced quotes/brackets (no truncation).
Runtime context:
$runtime_context
Context source: $context_source_label ($context_status)
$context_var_hints
Context instructions:
$context_text
User request: $prompt"
  t_prompt_done="$(now_ms)"

  if [[ "$DEBUG" -eq 1 ]]; then
    {
      echo "----- FINAL PROMPT BEGIN -----"
      echo "$full_prompt"
      echo "----- FINAL PROMPT END -----"
    } >&2
  fi

  if [[ "$DEBUG" -eq 0 ]]; then
    case "$STREAM_MODE" in
      on)
        stream_enabled=1
        ;;
      off)
        stream_enabled=0
        ;;
      auto)
        if [[ -t 1 ]]; then
          stream_enabled=1
        fi
        ;;
    esac
  fi

  payload="$(build_deepseek_payload "$full_prompt" "$stream_enabled")"

  if [[ "$stream_enabled" -eq 1 ]]; then
    stream_deepseek_response "$payload"
    printf '\n'
    return
  fi

  t_model_start="$(now_ms)"
  response_file="$(mktemp)"
  http_code="$(curl -sS -o "$response_file" -w '%{http_code}' -X POST "$API_ENDPOINT" \
    -H "Authorization: Bearer $APIKEY_DEEPSEEK" \
    -H 'Content-Type: application/json' \
    -d "$payload")"
  t_model_done="$(now_ms)"

  if [[ ! "$http_code" =~ ^2 ]]; then
    error_message="$(extract_error_message "$response_file")"
    rm -f "$response_file"
    echo "Error: DeepSeek API request failed (HTTP $http_code): $error_message" >&2
    exit 1
  fi

  raw_output="$(extract_response_content "$response_file")"
  rm -f "$response_file"

  sanitized_output="$(sanitize_model_output "$raw_output")"
  t_sanitize_done="$(now_ms)"

  if [[ "$DEBUG" -eq 1 ]]; then
    debug_log "timing.build_runtime_context_ms=$(elapsed_ms "$t_start" "$t_runtime_done")"
    debug_log "timing.build_context_and_hints_ms=$(elapsed_ms "$t_runtime_done" "$t_context_done")"
    debug_log "timing.build_prompt_ms=$(elapsed_ms "$t_context_done" "$t_prompt_done")"
    debug_log "timing.model_ttft_ms=$ttft_ms"
    debug_log "timing.model_total_ms=$(elapsed_ms "$t_model_start" "$t_model_done")"
    debug_log "timing.sanitize_output_ms=$(elapsed_ms "$t_model_done" "$t_sanitize_done")"
    debug_log "timing.total_ms=$(elapsed_ms "$t_start" "$t_sanitize_done")"
  fi

  printf '%s\n' "$sanitized_output"
}

args=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    -i|--interactive)
      INTERACTIVE=1
      shift
      ;;
    -m|--model)
      if [[ $# -lt 2 ]]; then
        echo "Error: --model needs a value." >&2
        exit 1
      fi
      MODEL="$2"
      shift 2
      ;;
    --api-endpoint)
      if [[ $# -lt 2 ]]; then
        echo "Error: --api-endpoint needs a value." >&2
        exit 1
      fi
      API_ENDPOINT="$2"
      shift 2
      ;;
    --context)
      if [[ $# -lt 2 ]]; then
        echo "Error: --context needs a text value." >&2
        exit 1
      fi
      CONTEXT_INLINE="$2"
      CONTEXT_INLINE_EXPLICIT=1
      shift 2
      ;;
    -c|--context-file)
      if [[ $# -lt 2 ]]; then
        echo "Error: --context-file needs a file path." >&2
        exit 1
      fi
      CONTEXT_FILE="$2"
      CONTEXT_FILE_EXPLICIT=1
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --debug)
      DEBUG=1
      shift
      ;;
    --stream)
      STREAM_MODE="on"
      shift
      ;;
    --no-stream)
      STREAM_MODE="off"
      shift
      ;;
    --)
      shift
      while [[ $# -gt 0 ]]; do
        args+=("$1")
        shift
      done
      ;;
    -*)
      echo "Error: unknown option '$1'" >&2
      usage >&2
      exit 1
      ;;
    *)
      args+=("$1")
      shift
      ;;
  esac
done

if [[ "$CONTEXT_FILE_EXPLICIT" -eq 1 && ! -f "$CONTEXT_FILE" ]]; then
  echo "Error: context file not found: $CONTEXT_FILE" >&2
  exit 1
fi

require_deepseek

if [[ "$INTERACTIVE" -eq 1 ]]; then
  echo "Interactive mode"
  echo "Model: $MODEL"
  echo "API endpoint: $API_ENDPOINT"
  echo "Context injection: enabled"
  echo "Context file: $CONTEXT_FILE"
  if [[ "$DEBUG" -eq 1 ]]; then
    echo "Debug mode: enabled"
  fi
  if [[ "$CONTEXT_INLINE_EXPLICIT" -eq 1 ]]; then
    echo "Inline context (--context): provided"
  fi
  echo "Type 'exit' or 'quit' to stop."

  while true; do
    read -r -p "prompt> " user_input || break
    case "$user_input" in
      "")
        continue
        ;;
      exit|quit)
        break
        ;;
    esac

    run_once "$user_input"
    echo
  done
  exit 0
fi

prompt=""
if [[ ${#args[@]} -gt 0 ]]; then
  prompt="${args[*]}"
elif [[ ! -t 0 ]]; then
  prompt="$(cat)"
else
  echo "Error: no prompt provided. Use -i or pass a prompt/pipe input." >&2
  usage >&2
  exit 1
fi

if [[ -z "${prompt//[[:space:]]/}" ]]; then
  echo "Error: empty prompt." >&2
  exit 1
fi

run_once "$prompt"
