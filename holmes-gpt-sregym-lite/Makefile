SHELL := /usr/bin/env bash
.SHELLFLAGS := -eu -o pipefail -c
.DEFAULT_GOAL := help
export PATH := /opt/homebrew/bin:$(PATH)

ENV_FILE ?= .env
ifneq (,$(wildcard $(ENV_FILE)))
  include $(ENV_FILE)
  export
endif

SREGYM_DIR   ?= ../../SREGym
SREGYM_ABS   := $(abspath $(SREGYM_DIR))
MODEL        ?= openrouter/anthropic/claude-sonnet-4-5
JUDGE_MODEL  ?= $(MODEL)
KUBE_CONTEXT ?= kind-sre-gym
HOLMES_IMAGE ?= us-central1-docker.pkg.dev/genuine-flight-317411/devel/holmes:latest
# SREGym-Lite is graded on diagnosis only: HolmesGPT is read-only and never remediates.
STAGES       ?= diagnosis
PROBLEM      ?= network_policy_block
# 8 GB Docker Desktop: 'svelte' drops components nothing in SREGym reads (Alertmanager,
# Pushgateway, astronomy-shop's OpenSearch/Grafana/Jaeger, OpenEBS NDM) and caps Prometheus.
PROFILE      ?= svelte
HOLMES_MEMORY ?= 1g

export SREGYM_ROOT := $(SREGYM_ABS)
export HOLMES_MEMORY

RUN := cd $(SREGYM_ABS) && uv run main.py --agent holmesgpt --model $(MODEL) \
	--judge-model $(JUDGE_MODEL) --stages $(STAGES) --internet-access open --profile $(PROFILE)

.PHONY: help
help: ## Show available targets.
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

.PHONY: preflight
preflight: ## Check docker, cluster, uv, API key and the HolmesGPT image.
	@docker info >/dev/null 2>&1 && echo "  docker      ok" || { echo "  docker      FAIL"; exit 1; }
	@mem=$$(docker info --format '{{.MemTotal}}'); gib=$$((mem / 1073741824)); \
		echo "  docker mem  $${gib} GiB (profile $(PROFILE))"; \
		[ $$gib -ge 7 ] || { echo "  docker mem  FAIL — need >= 8 GB in Docker Desktop"; exit 1; }
	@kubectl config current-context | grep -qx '$(KUBE_CONTEXT)' && echo "  context     ok ($(KUBE_CONTEXT))" || { echo "  context     FAIL — kubectl config use-context $(KUBE_CONTEXT)"; exit 1; }
	@kubectl get nodes >/dev/null && echo "  cluster     ok" || { echo "  cluster     FAIL"; exit 1; }
	@command -v uv >/dev/null && echo "  uv          ok" || { echo "  uv          FAIL — brew install uv"; exit 1; }
	@test -n "$(OPENROUTER_API_KEY)" && echo "  api key     ok" || { echo "  api key     FAIL — set OPENROUTER_API_KEY in .env"; exit 1; }
	@docker image inspect $(HOLMES_IMAGE) >/dev/null 2>&1 && echo "  holmes img  ok" || docker pull $(HOLMES_IMAGE)

.PHONY: install
install: ## Link the HolmesGPT client into SREGym and register the agent.
	@ln -sfn $(abspath client/holmesgpt) $(SREGYM_ABS)/clients/holmesgpt
	@grep -q 'name: holmesgpt' $(SREGYM_ABS)/agents.yaml || printf '%s\n' \
		'  - name: holmesgpt' \
		'    kickoff_command: python -m clients.holmesgpt.driver' \
		'    kickoff_workdir: .' \
		'    kickoff_env: null' \
		'    install_script: null' \
		'    agent_version: null' \
		'    container_isolation: false' >> $(SREGYM_ABS)/agents.yaml
	@echo "Linked $(SREGYM_ABS)/clients/holmesgpt and registered agent 'holmesgpt'"

.PHONY: uninstall
uninstall: ## Remove the client link and agent registration from SREGym.
	@rm -f $(SREGYM_ABS)/clients/holmesgpt
	@cd $(SREGYM_ABS) && git checkout -- agents.yaml

.PHONY: run-one
run-one: preflight install ## Run one problem (PROBLEM=<id>).
	$(RUN) --problem $(PROBLEM)

.PHONY: run-lite
run-lite: preflight install ## Run all 17 SREGym-Lite problems.
	$(RUN) --suite sregym-lite

.PHONY: run-list
run-list: ## Run the given problems one at a time (PROBLEMS="<id> <id>...").
	@scripts/run-list.sh $(PROBLEMS)

.PHONY: resume
resume: preflight install ## Resume a lite run (CSV=<path to results csv>).
	$(RUN) --suite sregym-lite --resume $(CSV)

.PHONY: summary
summary: ## Collect results into results/ and regenerate the README results block (RUNS="<dir>...").
	@python3 scripts/summarize.py --sregym $(SREGYM_ABS) --out results --readme README.md --root-readme ../README.md $(if $(RUNS),--run $(RUNS))

.PHONY: watch
watch: ## Regenerate + commit README after every problem until the run ends (RUNS="<dir> [<dir>...]").
	@scripts/watch.sh $(SREGYM_ABS) $(RUNS)
