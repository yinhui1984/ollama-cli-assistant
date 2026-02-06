#!/usr/bin/env bash
set -euo pipefail

MODEL="cli-assistant"
ASSUME_YES=0

usage() {
  echo "Usage: $0 [-m MODEL] [-y]"
  echo "  -m, --model   model name to remove (default: cli-assistant)"
  echo "  -y, --yes     skip confirmation"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -m|--model)
      if [[ $# -lt 2 ]]; then
        echo "Error: --model needs a value." >&2
        exit 1
      fi
      MODEL="$2"
      shift 2
      ;;
    -y|--yes)
      ASSUME_YES=1
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

if ! command -v ollama >/dev/null 2>&1; then
  echo "Error: ollama command not found." >&2
  exit 1
fi

if ! ollama show "$MODEL" >/dev/null 2>&1; then
  echo "Model '$MODEL' does not exist. Nothing to remove."
  exit 0
fi

if [[ "$ASSUME_YES" -ne 1 ]]; then
  read -r -p "Remove model '$MODEL'? [y/N] " answer
  case "$answer" in
    y|Y|yes|YES)
      ;;
    *)
      echo "Cancelled."
      exit 0
      ;;
  esac
fi

ollama stop "$MODEL" >/dev/null 2>&1 || true
ollama rm "$MODEL"

echo "Removed model: $MODEL"
