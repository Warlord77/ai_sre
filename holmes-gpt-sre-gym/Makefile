SHELL := /usr/bin/env bash
.SHELLFLAGS := -eu -o pipefail -c
.DEFAULT_GOAL := help
export PATH := /opt/homebrew/bin:$(PATH)

ENV_FILE ?= .env
ifneq (,$(wildcard $(ENV_FILE)))
  include $(ENV_FILE)
  export
endif

HOLMES_IMAGE     ?= us-central1-docker.pkg.dev/genuine-flight-317411/devel/holmes:latest
MODEL            ?= openrouter/anthropic/claude-sonnet-4-5
PROMETHEUS_URL   ?= http://localhost:9090
ALERTMANAGER_URL ?= http://localhost:9093
GRAFANA_URL      ?= http://localhost:3000
GRAFANA_API_KEY  ?=
KUBE_CONTEXT     ?= kind-sre-gym

# Seconds to wait after chaos for alert to fire
CHAOS_WAIT ?= 75

# SRE gym observability-stack directory (relative)
SRE_GYM ?= ../opensre/observability-stack

FINDINGS_DIR := findings

# Patched kubeconfig (127.0.0.1 -> host.docker.internal) for Docker on macOS. See issues.md #3.
KUBECONFIG_DOCKER ?= /tmp/kube-docker.yaml
# HolmesGPT toolset config (enables prometheus/grafana toolsets). See issues.md #1.
HOLMES_CONFIG ?= holmes-config.yaml
# Alertmanager URL as seen from INSIDE the container. localhost won't work on macOS (issues.md #2).
ALERTMANAGER_URL_DOCKER ?= http://host.docker.internal:9093

.PHONY: help
help: ## Show available targets.
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  \033[36m%-30s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

# ── Preflight ─────────────────────────────────────────────────────────────────

.PHONY: preflight
preflight: ## Check all dependencies and integrations are reachable.
	@echo "==> Checking observability endpoints..."
	@curl -fsS $(PROMETHEUS_URL)/-/ready   >/dev/null && echo "  prometheus  ok" || { echo "  prometheus  FAIL — run make port-forward in observability-stack"; exit 1; }
	@curl -fsS $(ALERTMANAGER_URL)/-/ready >/dev/null && echo "  alertmanager ok" || { echo "  alertmanager FAIL"; exit 1; }
	@curl -fsS $(GRAFANA_URL)/api/health   >/dev/null && echo "  grafana     ok" || { echo "  grafana     FAIL"; exit 1; }
	@kubectl --context $(KUBE_CONTEXT) cluster-info >/dev/null 2>&1 && echo "  k8s cluster ok" || { echo "  k8s cluster FAIL"; exit 1; }
	@test -n "$(OPENROUTER_API_KEY)" && echo "  api key     ok" || { echo "  api key     FAIL — set OPENROUTER_API_KEY"; exit 1; }
	@echo ""
	@echo "All checks passed. Ready to investigate."

# ── HolmesGPT helpers ────────────────────────────────────────────────────────

.PHONY: kubeconfig
kubeconfig: ## Patch the kind kubeconfig for Docker on macOS (127.0.0.1 -> host.docker.internal).
	@scripts/patch-kubeconfig.sh "$(KUBE_CONTEXT)" "$(KUBECONFIG_DOCKER)"

# Base docker run command shared by all investigation targets.
# On macOS, --net=host does NOT reach host ports (issues.md #2), so all URLs use
# host.docker.internal. Mounts the patched kubeconfig (issues.md #3) and the toolset
# config that enables the prometheus/grafana toolsets (issues.md #1).
HOLMES_RUN = docker run --rm \
	-e OPENROUTER_API_KEY="$(OPENROUTER_API_KEY)" \
	-e MODEL="$(MODEL)" \
	-v $(KUBECONFIG_DOCKER):/root/.kube/config:ro \
	-v $(abspath $(HOLMES_CONFIG)):/root/.holmes/config.yaml:ro \
	$(HOLMES_IMAGE)

.PHONY: toolsets
toolsets: kubeconfig ## List which HolmesGPT toolsets are active with current config.
	$(HOLMES_RUN) toolset list 2>&1

# ── Investigate: pull live alerts from Alertmanager → HolmesGPT ──────────────

.PHONY: investigate-live
investigate-live: kubeconfig ## Investigate all currently firing alerts (live from Alertmanager).
	@echo "==> Firing alerts in namespace app:"
	@curl -s "$(ALERTMANAGER_URL)/api/v2/alerts?filter=namespace%3Dapp" \
		| jq -r '.[].labels.alertname' 2>/dev/null | sort -u || true
	@echo "==> Investigating with HolmesGPT (Prometheus + Grafana + K8s)..."
	$(HOLMES_RUN) investigate alertmanager \
		--alertmanager-url "$(ALERTMANAGER_URL_DOCKER)" 2>&1

# ── Chaos scenarios + investigation ──────────────────────────────────────────

.PHONY: scenario-redis-down
scenario-redis-down: kubeconfig ## Chaos: scale Redis to 0, wait, investigate, reset. Saves output to findings/.
	@mkdir -p $(FINDINGS_DIR)
	@echo "==> [scenario] redis-down"
	kubectl --context $(KUBE_CONTEXT) -n app scale deployment/redis --replicas=0
	@echo "Waiting $(CHAOS_WAIT)s for AppRedisDown to fire..."
	@sleep $(CHAOS_WAIT)
	@echo "==> Investigating with HolmesGPT (Prometheus + Grafana + K8s)..."
	$(HOLMES_RUN) investigate alertmanager \
		--alertmanager-url "$(ALERTMANAGER_URL_DOCKER)" 2>&1 | tee $(FINDINGS_DIR)/redis-down.txt
	@echo "==> Resetting..."
	kubectl --context $(KUBE_CONTEXT) -n app scale deployment/redis --replicas=1
	@echo "Done. Output: $(FINDINGS_DIR)/redis-down.txt"

.PHONY: scenario-postgres-down
scenario-postgres-down: kubeconfig ## Chaos: scale Postgres to 0, wait, investigate, reset.
	@mkdir -p $(FINDINGS_DIR)
	@echo "==> [scenario] postgres-down"
	kubectl --context $(KUBE_CONTEXT) -n app scale statefulset/postgres --replicas=0
	@echo "Waiting $(CHAOS_WAIT)s for AppPostgresDown + cascades to fire..."
	@sleep $(CHAOS_WAIT)
	@echo "==> Investigating with HolmesGPT..."
	$(HOLMES_RUN) investigate alertmanager \
		--alertmanager-url "$(ALERTMANAGER_URL_DOCKER)" 2>&1 | tee $(FINDINGS_DIR)/postgres-down.txt
	@echo "==> Resetting..."
	kubectl --context $(KUBE_CONTEXT) -n app scale statefulset/postgres --replicas=1
	@echo "Done. Output: $(FINDINGS_DIR)/postgres-down.txt"

.PHONY: scenario-backend-down
scenario-backend-down: kubeconfig ## Chaos: scale backend to 0, wait, investigate, reset.
	@mkdir -p $(FINDINGS_DIR)
	@echo "==> [scenario] backend-down"
	kubectl --context $(KUBE_CONTEXT) -n app scale deployment/backend --replicas=0
	@echo "Waiting $(CHAOS_WAIT)s for AppBackendDown to fire..."
	@sleep $(CHAOS_WAIT)
	@echo "==> Investigating with HolmesGPT..."
	$(HOLMES_RUN) investigate alertmanager \
		--alertmanager-url "$(ALERTMANAGER_URL_DOCKER)" 2>&1 | tee $(FINDINGS_DIR)/backend-down.txt
	@echo "==> Resetting..."
	kubectl --context $(KUBE_CONTEXT) -n app scale deployment/backend --replicas=2
	@echo "Done. Output: $(FINDINGS_DIR)/backend-down.txt"

.PHONY: scenario-backend-crashloop
scenario-backend-crashloop: kubeconfig ## Chaos: set backend to bogus image → CrashLoopBackOff, investigate, reset.
	@mkdir -p $(FINDINGS_DIR)
	@echo "==> [scenario] backend-crashloop"
	kubectl --context $(KUBE_CONTEXT) -n app scale deployment/backend --replicas=0
	kubectl --context $(KUBE_CONTEXT) -n app set image deployment/backend backend=busybox:1.36
	kubectl --context $(KUBE_CONTEXT) -n app scale deployment/backend --replicas=1
	@echo "Waiting $(CHAOS_WAIT)s for AppPodCrashLooping + AppBackendDown to fire..."
	@sleep $(CHAOS_WAIT)
	@echo "==> Investigating with HolmesGPT..."
	$(HOLMES_RUN) investigate alertmanager \
		--alertmanager-url "$(ALERTMANAGER_URL_DOCKER)" 2>&1 | tee $(FINDINGS_DIR)/backend-crashloop.txt
	@echo "==> Resetting via Helm..."
	helm --kube-context $(KUBE_CONTEXT) upgrade --install app $(SRE_GYM)/charts/app \
		-n app \
		--set gateway.image.repository=opensre/gateway \
		--set gateway.image.tag=dev \
		--set backend.image.repository=opensre/backend \
		--set backend.image.tag=dev \
		--set serviceMonitor.releaseLabel=kps \
		--force-conflicts --wait --timeout 3m
	@echo "Done. Output: $(FINDINGS_DIR)/backend-crashloop.txt"

# ── K8s MCP server ────────────────────────────────────────────────────────────

.PHONY: k8s-mcp-toolsets
k8s-mcp-toolsets: ## Show what tools mcp-server-kubernetes exposes (dry-run via npx).
	@echo "mcp-server-kubernetes@4.1.9 tools:"
	@npx --yes mcp-server-kubernetes@4.1.9 --help 2>&1 || true

.PHONY: k8s-mcp-ask
k8s-mcp-ask: ## Ask HolmesGPT a free-form question against the live cluster.
	$(HOLMES_RUN) ask "$(Q)"
