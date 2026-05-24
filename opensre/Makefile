SHELL := /usr/bin/env bash
.SHELLFLAGS := -eu -o pipefail -c
.DEFAULT_GOAL := help

ENV_FILE ?= .env

# Load .env if present
ifneq (,$(wildcard $(ENV_FILE)))
  include $(ENV_FILE)
  export
endif

.PHONY: help
help: ## Show this help.
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  \033[36m%-22s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

# ── Setup ────────────────────────────────────────────────────────────────────

.PHONY: env
env: ## Create .env from .env.example (first-time setup).
	@test -f .env && echo ".env already exists — edit it directly." || \
		(cp .env.example .env && echo "Created .env — fill in your API keys before running anything.")

.PHONY: install
install: ## Install opensre CLI via homebrew.
	brew install tracer-cloud/tap/opensre

.PHONY: doctor
doctor: ## Run opensre diagnostics.
	opensre doctor

.PHONY: integrations
integrations: ## Verify all opensre integrations.
	opensre integrations verify

# ── Observability stack ───────────────────────────────────────────────────────

.PHONY: stack-up
stack-up: ## Bring up the full observability stack (platform + app).
	$(MAKE) -C observability-stack up

.PHONY: stack-down
stack-down: ## Tear down the observability stack.
	$(MAKE) -C observability-stack down

.PHONY: stack-status
stack-status: ## Show pod status across monitoring + app namespaces.
	$(MAKE) -C observability-stack status

.PHONY: port-forward
port-forward: ## Port-forward Grafana (:3000), Alertmanager (:9093), PostgreSQL (:5432).
	$(MAKE) -C observability-stack port-forward

# ── Investigate ───────────────────────────────────────────────────────────────

# Guard: LLM_PROVIDER must be set (from .env file or exported env var).
_check-llm:
	@test -n "$$LLM_PROVIDER" || { \
		echo "LLM_PROVIDER not set. Either run 'make env' and fill in .env, or export LLM_PROVIDER + API key."; \
		exit 1; \
	}

.PHONY: investigate
investigate: _check-llm ## Run opensre investigation against the alert fixture (tests/actual-dev-env.alert.json).
	opensre investigate -i tests/actual-dev-env.alert.json

# Alertmanager /api/v2/alerts returns a JSON array.
# opensre investigate -i - requires Alertmanager webhook format (JSON object with "alerts" key). So it directly listens to alertmanager
.PHONY: investigate-stdin
investigate-stdin: _check-llm ## Pull live alerts from Alertmanager and feed to opensre (wraps array into webhook format).
	@curl -s http://localhost:9093/api/v2/alerts \
		| jq '{ \
			"version":"4", \
			"status":"firing", \
			"receiver":"opensre-live", \
			"groupLabels":{}, \
			"helm_release":"app", \
			"helm_namespace":"app", \
			"commonLabels":{"meta.helm.sh/release-name":"app","meta.helm.sh/release-namespace":"app"}, \
			"commonAnnotations":{"grafana_url":"http://localhost:3000"}, \
			"externalURL":"", \
			"alerts": [.[] | .labels += {"meta.helm.sh/release-name":"app","meta.helm.sh/release-namespace":"app","helm_release":"app","helm_namespace":"app"}] \
		}' \
		| opensre investigate -i -

# ── Chaos (requires stack-up + port-forward running) ─────────────────────────

.PHONY: chaos-postgres-down chaos-redis-down chaos-gateway-down chaos-backend-down chaos-reset
chaos-postgres-down: ## Scale Postgres to 0 — triggers AppPostgresDown alert.
	$(MAKE) -C observability-stack chaos-postgres-down

chaos-redis-down: ## Scale Redis to 0 — triggers AppRedisDown alert.
	$(MAKE) -C observability-stack chaos-redis-down

chaos-gateway-down: ## Scale gateway to 0 — triggers AppGatewayDown alert.
	$(MAKE) -C observability-stack chaos-gateway-down

chaos-backend-down: ## Scale backend to 0 — triggers AppBackendDown alert.
	$(MAKE) -C observability-stack chaos-backend-down

chaos-reset: ## Restore stack to baseline.
	$(MAKE) -C observability-stack chaos-reset

.PHONY: load-start load-stop
load-start: ## Start sustained background load against the gateway (feeds Grafana metrics).
	$(MAKE) -C observability-stack chaos-load

load-stop: ## Stop the background load generator.
	$(MAKE) -C observability-stack chaos-load-stop

# Seconds to wait after a chaos event before investigating (alert needs to fire).
CHAOS_WAIT   ?= 60
# Seconds of baseline load before first chaos scenario (Grafana needs data to correlate).
LOAD_WARM    ?= 60
# Max seconds to wait for all app alerts to clear between scenarios.
ALERT_DRAIN  ?= 180

# Poll Alertmanager until no firing alerts remain in namespace=app (or timeout).
_wait-alerts-clear:
	@echo "waiting for all app alerts to clear (max $(ALERT_DRAIN)s)..."; \
	deadline=$$(( $$(date +%s) + $(ALERT_DRAIN) )); \
	while true; do \
		firing=$$(curl -s 'http://localhost:9093/api/v2/alerts?filter=namespace%3Dapp' \
			| jq '[.[] | select(.status.state=="active")] | length' 2>/dev/null || echo 1); \
		[ "$$firing" -eq 0 ] && echo "all alerts cleared." && break; \
		[ "$$(date +%s)" -ge "$$deadline" ] && echo "WARNING: $$firing alert(s) still firing after $(ALERT_DRAIN)s — continuing anyway." && break; \
		echo "  $$firing alert(s) still active, retrying in 10s..."; \
		sleep 10; \
	done

.PHONY: chaos-full-run
chaos-full-run: _check-llm ## Run all chaos scenarios sequentially: postgres→redis→backend→gateway→all-down, with investigate + reset between each.
	@echo "==> starting load generator for baseline data"
	$(MAKE) load-start
	@echo "warming up $(LOAD_WARM)s before first scenario..."; sleep $(LOAD_WARM)

	@echo "==> [1/5] postgres down"
	$(MAKE) chaos-postgres-down
	@echo "waiting $(CHAOS_WAIT)s for alert to fire..."; sleep $(CHAOS_WAIT)
	$(MAKE) investigate-stdin
	$(MAKE) chaos-reset
	$(MAKE) _wait-alerts-clear
	$(MAKE) load-start

	@echo "==> [2/5] redis down"
	$(MAKE) chaos-redis-down
	@echo "waiting $(CHAOS_WAIT)s for alert to fire..."; sleep $(CHAOS_WAIT)
	$(MAKE) investigate-stdin
	$(MAKE) chaos-reset
	$(MAKE) _wait-alerts-clear
	$(MAKE) load-start

	@echo "==> [3/5] backend down"
	$(MAKE) chaos-backend-down
	@echo "waiting $(CHAOS_WAIT)s for alert to fire..."; sleep $(CHAOS_WAIT)
	$(MAKE) investigate-stdin
	$(MAKE) chaos-reset
	$(MAKE) _wait-alerts-clear
	$(MAKE) load-start

	@echo "==> [4/5] gateway down"
	$(MAKE) chaos-gateway-down
	@echo "waiting $(CHAOS_WAIT)s for alert to fire..."; sleep $(CHAOS_WAIT)
	$(MAKE) investigate-stdin
	$(MAKE) chaos-reset
	$(MAKE) _wait-alerts-clear
	$(MAKE) load-start

	@echo "==> [5/5] all services down"
	$(MAKE) chaos-postgres-down chaos-redis-down chaos-backend-down chaos-gateway-down
	@echo "waiting $(CHAOS_WAIT)s for alerts to fire..."; sleep $(CHAOS_WAIT)
	$(MAKE) investigate-stdin
	$(MAKE) chaos-reset
	$(MAKE) _wait-alerts-clear
