# Repository Guidelines

## Project Structure
- `cli-assistant.sh`: Main entrypoint for running the CLI assistant in interactive or one-shot mode.
- `model/`: Model build and test assets.
- `model/ollama-cli-assistant.Modelfile`: Ollama model definition and prompt contract.
- `model/01_interactive_test.sh`: Interactive test harness for the model.
- `model/03_batch_test.sh`: Batch test runner with case files.
- `model/04_cases_holdout.txt`: Default prompt set for batch testing.

## Build, Test, and Development Commands
- `./cli-assistant.sh -i`: Start interactive REPL against the model.
- `./cli-assistant.sh "<prompt>"`: Run one prompt and return one command.
- `make -C model create`: Build or update the `cli-assistant` model.
- `make -C model batch`: Run batch tests with holdout cases and save results.
- `make -C model batch-cases CASES=/path/to/file.txt`: Use a custom case file.
- `make -C model clean-model`: Remove the model locally.
- `make -C model recreate`: Clean and rebuild the model.

## Coding Style & Naming Conventions
- Shell scripts use `bash` with `set -euo pipefail` and `case`-based flag parsing.
- Indentation is two spaces in shell blocks; keep it consistent.
- Script names are prefixed with ordered numbers in `model/` (e.g., `01_*.sh`).
- No formatter is enforced; keep changes minimal and readable.

## Testing Guidelines
- Testing is script-driven, not framework-based.
- Use `model/01_interactive_test.sh` for manual validation.
- Use `model/03_batch_test.sh` for repeatable batch runs.
- Case files are one prompt per line; lines starting with `#` are comments.

## Commit & Pull Request Guidelines
- Git history is not available in this directory, so no commit convention is enforced.
- When proposing changes, include a short summary, test command run (if any), and output file paths (e.g., batch results) when relevant.
- For model changes, note the updated Modelfile sections and confirm a rebuild.

## Configuration & Model Notes
- Default model name is `cli-assistant` and can be overridden via `-m` or `MODEL=...`.
- The Modelfile defines strict output contracts; keep changes aligned with the “one command only” requirement.
