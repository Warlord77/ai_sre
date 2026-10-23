SHELL := /usr/bin/env bash
.DEFAULT_GOAL := help

# Problem selection for `make run`: a number, list, range, "all" or problem ids.
P ?=

.PHONY: help
help: ## Show targets.
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)
	@echo; echo "  Start: cp .env.example .env, set PROVIDER and its key, then make setup"

.env:
	@cp .env.example .env && chmod 600 .env
	@echo "Created .env from .env.example: set PROVIDER and its key, then run make setup"; exit 1

.PHONY: setup check-model install list pick run summary
setup: .env ## Check/install everything: tools, cluster, SREGym, HolmesGPT image, model, driver.
	@bash scripts/setup.sh all
check-model: .env ## Check the configured model returns a tool call (HolmesGPT needs it).
	@bash scripts/setup.sh model
install: .env ## Link the HolmesGPT driver into SREGym and register the agent.
	@bash scripts/setup.sh install
list: .env ## List the 17 SREGym-Lite problems with their numbers.
	@source scripts/common.sh && lite_problems | nl -w3 -s') '
pick: .env ## Interactive menu: choose problems to run.
	@bash scripts/pick.sh
run: .env ## Run problems: make run P=3 | P=1,4,7 | P=2-5 | P=all | P=<problem_id>
	@[ -n "$(P)" ] || { echo "Choose problems: make run P=3 (see make list) or make pick"; exit 1; }
	@bash scripts/run.sh $(P)
summary: ## Results table of the latest run (or RUN=results/<stamp>).
	@bash scripts/summary.sh $(RUN)
