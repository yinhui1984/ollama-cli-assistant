#!/usr/bin/env bash
set -euo pipefail

MODEL="${1:-cli-assistant}"
CONTEXT_PREFIX="${CONTEXT_PREFIX:-Runtime: macOS (Darwin), shell zsh. Return one executable command only. User request: }"

if ! command -v ollama >/dev/null 2>&1; then
  echo "Error: ollama command not found." >&2
  exit 1
fi

if ! ollama show "$MODEL" >/dev/null 2>&1; then
  echo "Error: model '$MODEL' not found. Build it first:" >&2
  echo "  make create" >&2
  exit 1
fi

echo "Interactive test mode"
echo "Model: $MODEL"
echo "Context prefix enabled: macOS + zsh"
echo "Type 'exit' or 'quit' to stop."

while true; do
  read -r -p "prompt> " user_input || break

  case "$user_input" in
    "" )
      continue
      ;;
    exit|quit)
      break
      ;;
  esac

  ollama run "$MODEL" "${CONTEXT_PREFIX}${user_input}"
  echo

done
