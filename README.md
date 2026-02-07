[English](README.md) | [Chinese](README_CN.md)

# ollama-cli-assistant

A macOS-first CLI command compiler that turns natural language into exactly one runnable zsh command.

This project is designed for daily terminal use with a strict output contract and a practical Linux-to-macOS clipboard correction layer.

## Why this project

- One-line command output contract (no explanation mixed into stdout)
- macOS-native routing by default (`mdfind`, `lsof`, `shasum`, etc.)
- Foundry/Web3-aware command generation (`forge`, `cast`, `anvil`)
- Clipboard correction for common Linux-only flags and behaviors on macOS
- Reproducible integration tests for compatibility correction

Core distinction from calling a generic LLM directly:

- This repo ships a custom command model (`cli-assistant`) with a strict command-only contract.
- The runtime wrapper (`cli-assistant.sh`) adds operational guarantees that a plain model call does not provide.

## Project layout

- `cli-assistant.sh`: Main entrypoint (local Ollama model)
- `cli-assistant-deepseek.sh`: Baseline comparison script (DeepSeek API path)
- `context.md`: Durable context instructions (env vars and preferences)
- `model/ollama-cli-assistant.Modelfile`: Model contract and few-shot examples
- `model/01_interactive_test.sh`: Interactive manual test helper
- `model/02_clean_model.sh`: Non-interactive local model deletion helper
- `model/03_batch_test.sh`: Batch test runner
- `model/04_cases_holdout.txt`: Default batch case set
- `test_clipboard_fix.sh`: Clipboard compatibility integration tests
- `Makefile`: Unified project commands

## Requirements

- macOS (Darwin)
- `zsh`
- [Ollama](https://ollama.com/) installed and running
- Base model available locally (default: `qwen2.5-coder:7b`)

Foundry toolchain (for Web3 prompts):

```bash
curl -L https://foundry.paradigm.xyz | bash
foundryup
```

Recommended for stronger compatibility correction:

```bash
brew install coreutils gnu-sed grep findutils
```

This provides: `gdate`, `gsed`, `ggrep`, `gfind`, `greadlink`, `gstat`.

## Environment variables

Set env vars according to your workflow:

```bash
export RPC_ETH="https://rpc.ankr.com/eth"
export APIKEY_DEEPSEEK="sk-demo-deepseek-key"   # only needed for cli-assistant-deepseek.sh
```

`RPC_ETH` is used by many Foundry/Web3 prompts when your context points to this variable.

## Two-layer architecture

1. Custom model layer (`model/ollama-cli-assistant.Modelfile`)
- Encodes command contract, routing rules, and domain behavior (macOS + Foundry/Web3).
- Built as local model `cli-assistant`.

2. Runtime assistant layer (`cli-assistant.sh`)
- Injects runtime/context hints.
- Sanitizes model output to one executable line.
- Applies clipboard-only compatibility correction on macOS.
- Keeps stdout unchanged for auditability while copying corrected commands for execution.

## Quick start

### Step 1: Build the custom model (required)

```bash
cd ~/dev/ollama-cli-assistant
make create
```

### Step 2: Use the assistant runtime

```bash
./cli-assistant.sh "check whether port 8545 is listening"
```

Safety note:

- Always review generated commands before execution, especially mutating operations.

Interactive mode:

```bash
./cli-assistant.sh -i
```

Why runtime is necessary after model creation:

- Model quality alone does not solve shell/runtime edge cases.
- The wrapper provides deterministic command extraction and clipboard safety fixes.
- It is the boundary that makes daily terminal usage predictable.

## Make targets

```bash
make help
make create
make batch
make batch-cases CASES=./model/04_cases_holdout.txt
make clipboard-fix
make clean-model
make recreate
```

## Example environment (real run)

From a real run in this repo:

- macOS: `15.7.2 (24G325)`
- shell: `zsh 5.9`
- Ollama: `0.15.4`
- model: `cli-assistant:latest`
- GNU tools available: `gdate`, `gsed`, `ggrep`, `greadlink`, `gstat`, `gfind`

## Example outputs (real run)

### Basic/macOS

Prompt:

```text
find app named Visual Studio Code
```

Output:

```bash
mdfind 'Visual Studio Code.app'
```

Prompt:

```text
check whether port 8545 is listening
```

Output:

```bash
lsof -nP -iTCP:8545 -sTCP:LISTEN
```

Prompt:

```text
list all listening TCP ports
```

Output:

```bash
lsof -nP -iTCP -sTCP:LISTEN
```

Prompt:

```text
compute sha256 of README
```

Output:

```bash
shasum -a 256 README.md
```

### Foundry/Web3

Prompt:

```text
query current block number
```

Output:

```bash
cast block-number --rpc-url $RPC_ETH
```

Prompt:

```text
fork mainnet at block 18000000
```

Output:

```bash
anvil --fork-url $RPC_ETH --fork-block-number 18000000
```

Prompt:

```text
compile only and show contract sizes
```

Output:

```bash
forge build --sizes
```

Prompt:

```text
run only test_Deposit in test/Bridge.t.sol with full trace
```

Output:

```bash
forge test --match-path test/Bridge.t.sol --match-test test_Deposit -vvvv
```

## Clipboard correction (Linux -> macOS)

`cli-assistant.sh` keeps stdout unchanged for auditability, but corrects copied commands for common Linux-only incompatibilities.

Enabled by default:

```bash
CLIA_CLIPBOARD_FIX=1
```

Disable for debugging:

```bash
CLIA_CLIPBOARD_FIX=0
```

Real example:

- stdout:

```bash
echo "0x65ff4b03" | xxd -r -p | date -f - +"%Y-%m-%d %H:%M:%S"
```

- clipboard (`pbpaste`):

```bash
gdate -d "@$((16#65ff4b03))" +"%Y-%m-%d %H:%M:%S"
```

Currently covered rules include:

- `date -d` and common hex timestamp conversions
- `sed -i`
- `grep -P` (prefer `ggrep` when available)
- `readlink -f`
- `stat -c`
- `find -printf`
- safe subset of `xargs -r` rewrites

Safety boundary: potentially destructive commands are not auto-rewritten.

## Testing

### 1) Batch model tests

```bash
make batch
make batch-cases CASES=./model/04_cases_holdout.txt
```

### 2) Clipboard integration tests

```bash
make clipboard-fix
```

Current repository result:

- `RESULT: PASS (10/10 cases)`
- runs in two modes: `with_gnu` and `no_gnu`

## Baseline comparison script

`cli-assistant-deepseek.sh` is included as a baseline comparison path.

Use it to compare behavior/output style against the local Ollama path:

```bash
./cli-assistant-deepseek.sh "query current block number"
```

Comparison guidance:

- Treat `cli-assistant.sh` as the primary production path in this repo.
- Treat `cli-assistant-deepseek.sh` as a benchmark/baseline script.
- Prefer evidence-based claims using the same prompt set and captured outputs.
- `cli-assistant-deepseek.sh` requires `APIKEY_DEEPSEEK` and external API availability.

Snapshot from captured runs (same prompts):

| Prompt | `cli-assistant.sh` (stdout -> clipboard) | `cli-assistant-deepseek.sh` |
|---|---|---|
| `0x65ff4b03 to datetime` | `echo ... \| date -f - ...` -> `gdate -d "@$((16#65ff4b03))" ...` | `cast block 0x65ff4b03 --rpc-url $RPC_ETH --field timestamp \| xargs -I {} date -r {}` |
| `grep -P 'a.*b' sample.txt` | `grep -P ...` -> `ggrep -P ...` | `rg -P ...` |
| `readlink -f ./foo/bar` | `readlink -f ...` -> `greadlink -f ...` | `readlink -f ...` |
| `echo -e 'a\nb\n' \| xargs -r -n1 echo` | `... -r ...` -> `... -n1 ...` | `... -r ...` |

Interpretation:

- The primary script preserves model output for auditability, then applies macOS-focused clipboard correction.
- The baseline script is useful for prompt-path comparison, but does not provide the same clipboard compatibility layer.

## Configuration

- Default model: `cli-assistant`
- Override model:

```bash
./cli-assistant.sh -m cli-assistant "check whether port 8545 is listening"
```

- Inline context:

```bash
./cli-assistant.sh --context 'Use "$RPC_ETH" as Ethereum mainnet RPC' "query current block number"
```

- Context file:

```bash
./cli-assistant.sh --context-file ./context.md "query current block number"
```

### `context.md` basic example (recommended)

`context.md` is a core feature for persistent preferences and env-var routing.

Example file:

```markdown
# Context Instructions

- Use "$RPC_ETH" as Ethereum mainnet RPC
- Use "$APIKEY_DEEPSEEK" as DeepSeek API key

# Optional Notes

- Put long-lived preferences and constraints here, not one-off tasks.
```

Typical effect:

- Prompt: `query current block number`
- Output: `cast block-number --rpc-url $RPC_ETH`

This gives stable, reusable behavior without repeating the same constraints in every prompt.

## Known limits

- Not all Linux-only flags can be perfectly translated in all command shapes.
- Complex regex or shell constructs may require manual review.
- Clipboard correction is intentionally conservative for safety.

## License

MIT. See [`LICENSE`](LICENSE).
