SHELL := /usr/bin/env bash
.SHELLFLAGS := -eu -o pipefail -c
.DEFAULT_GOAL := help
export PATH := $(HOME)/.local/bin:$(PATH)

ENV_FILE ?= .env
ifneq (,$(wildcard $(ENV_FILE)))
  include $(ENV_FILE)
  export
endif

SREGYM_DIR   ?= ../../../SREGym
SREGYM_ABS   := $(abspath $(SREGYM_DIR))
MODEL        ?= openai/gpt-oss-120b
JUDGE_MODEL  ?= $(MODEL)
KUBE_CONTEXT ?= kind-kind
HOLMES_IMAGE ?= us-central1-docker.pkg.dev/genuine-flight-317411/devel/holmes:latest
# HolmesGPT is read-only and never remediates, so only diagnosis is graded.
STAGES       ?= diagnosis
PROBLEM      ?= network_policy_block
PROFILE      ?= full
HOLMES_MEMORY ?= 1g
MODEL_HOST   := $(shell echo '$(OPENAI_API_BASE)' | cut -d/ -f3 | cut -d: -f1)

export SREGYM_ROOT := $(SREGYM_ABS)
export HOLMES_MEMORY

RUN := cd $(SREGYM_ABS) && uv run main.py --agent holmesgpt --model $(MODEL) \
	--judge-model $(JUDGE_MODEL) --stages $(STAGES) --internet-access open --profile $(PROFILE)

.PHONY: help
help: ## Show available targets.
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

## --- one-time setup (in order) ---
.PHONY: docker tools cluster sregym holmes setup
docker: ## 1. Install Docker + inotify limits (prompts for sudo).
	sudo bash scripts/01-install-docker.sh
tools: ## 2. Install kind, kubectl, Helm 4, uv into ~/.local/bin.
	@bash scripts/02-install-tools.sh
cluster: ## 3. Create the SREGym kind cluster, 4 nodes capped at NODE_MEMORY (default 4g).
	@bash scripts/03-create-cluster.sh
sregym: ## 4. SREGym submodules, uv sync, pre-commit hook.
	@bash scripts/04-setup-sregym.sh
holmes: ## 5. Pull the HolmesGPT image.
	@bash scripts/05-pull-holmes.sh
setup: tools cluster sregym holmes install ## Steps 2-5 + install (run `make docker` first).

hosts-entry: ## Map the model host to the SSH tunnel for the host-side judge (prompts for sudo).
	@grep -q "127.0.0.1 $(MODEL_HOST)" /etc/hosts && echo "already present" || \
		echo "127.0.0.1 $(MODEL_HOST)" | sudo tee -a /etc/hosts

## --- checks ---
.PHONY: check-model smoke mcp-start mcp-stop mcp-smoke preflight
check-model: ## Tunnel up, model listed, tool calls parsed.
	@bash scripts/check-model.sh
smoke: ## HolmesGPT question against the cluster (Kubernetes toolsets only).
	@bash scripts/holmes-ask.sh
mcp-start: ## Start SREGym's MCP server standalone (127.0.0.1:9954).
	@bash scripts/mcp-server.sh start
mcp-stop: ## Stop the standalone MCP server.
	@bash scripts/mcp-server.sh stop
mcp-smoke: mcp-start ## HolmesGPT with the SREGym Prometheus/Loki/Jaeger MCP servers attached.
	@bash scripts/holmes-ask.sh "List the tools you have from the sregym MCP servers, then say which ones responded." --mcp

preflight: ## Check docker, cluster, uv, API key, model, judge host mapping, image.
	@source scripts/lib.sh && dockr info >/dev/null 2>&1 && echo "  docker      ok" || { echo "  docker      FAIL"; exit 1; }
	@kubectl config current-context | grep -qx '$(KUBE_CONTEXT)' && echo "  context     ok ($(KUBE_CONTEXT))" || { echo "  context     FAIL — kubectl config use-context $(KUBE_CONTEXT)"; exit 1; }
	@kubectl get nodes >/dev/null && echo "  cluster     ok" || { echo "  cluster     FAIL"; exit 1; }
	@command -v uv >/dev/null && echo "  uv          ok" || { echo "  uv          FAIL — make tools"; exit 1; }
	@test -n "$(OPENROUTER_API_KEY)$(OPENAI_API_KEY)$(ANTHROPIC_API_KEY)" && echo "  api key     ok" || { echo "  api key     FAIL — set OPENAI_API_KEY in .env"; exit 1; }
	@bash scripts/check-model.sh >/dev/null && echo "  model       ok ($(MODEL), tool calls)" || { echo "  model       FAIL — make check-model"; exit 1; }
	@getent hosts $(MODEL_HOST) | grep -q '^127.0.0.1' && echo "  judge host  ok" || { echo "  judge host  FAIL — make hosts-entry (SREGym's judge runs on the host)"; exit 1; }
	@source scripts/lib.sh && dockr image inspect $(HOLMES_IMAGE) >/dev/null 2>&1 && echo "  holmes img  ok" || { echo "  holmes img  FAIL — make holmes"; exit 1; }

## --- SREGym agent registration ---
.PHONY: install uninstall
install: ## Link this client into SREGym and register the 'holmesgpt' agent.
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
uninstall: ## Remove the client link and agent registration from SREGym.
	@rm -f $(SREGYM_ABS)/clients/holmesgpt
	@cd $(SREGYM_ABS) && git checkout -- agents.yaml

## --- benchmark ---
.PHONY: run-one run-lite run-list
run-one: preflight install ## Run one SREGym problem (PROBLEM=<id>).
	$(RUN) --problem $(PROBLEM)
run-lite: preflight install ## Run all 17 SREGym-Lite problems.
	$(RUN) --suite sregym-lite
run-list: ## Run problems one at a time (PROBLEMS="<id> <id>...").
	@scripts/run-list.sh $(PROBLEMS)
