MODEL ?= cli-assistant
ROOT := /Users/z/Documents/dev/ollama-cli-assistant
MODEFILE := $(ROOT)/model/ollama-cli-assistant.Modelfile
BATCH_SCRIPT := $(ROOT)/model/03_batch_test.sh
CLEAN_SCRIPT := $(ROOT)/model/02_clean_model.sh

.PHONY: help create batch batch-cases clean-model recreate

help:
	@echo "Targets:"
	@echo "  make create                 # Create or update model"
	@echo "  make batch                  # Run batch test with default holdout cases"
	@echo "  make batch-cases CASES=...  # Run batch test with custom cases file"
	@echo "  make clean-model            # Delete model (non-interactive)"
	@echo "  make recreate               # clean-model + create"
	@echo
	@echo "Variables:"
	@echo "  MODEL=$(MODEL)"

create:
	ollama create $(MODEL) -f $(MODEFILE)

batch:
	$(BATCH_SCRIPT) -m $(MODEL)

batch-cases:
	@if [ -z "$(CASES)" ]; then \
		echo "Error: CASES is required. Example: make batch-cases CASES=$(ROOT)/model/04_cases_holdout.txt"; \
		exit 1; \
	fi
	$(BATCH_SCRIPT) -m $(MODEL) -c $(CASES)

clean-model:
	$(CLEAN_SCRIPT) -m $(MODEL) -y

recreate: clean-model create
