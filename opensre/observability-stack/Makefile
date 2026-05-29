SHELL := /usr/bin/env bash
.SHELLFLAGS := -eu -o pipefail -c
.DEFAULT_GOAL := help

KPS_RELEASE   ?= kps
APP_NAMESPACE ?= app
MON_NAMESPACE ?= monitoring

GATEWAY_IMAGE ?= opensre/gateway:dev
BACKEND_IMAGE ?= opensre/backend:dev

.PHONY: help
help: ## Show this help.
	@awk 'BEGIN {FS = ":.*?## "} \
	     /^# ===/ {printf "\n\033[1m%s\033[0m\n", substr($$0,5)} \
	     /^[a-zA-Z_-]+:.*?## / {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}' \
	     $(MAKEFILE_LIST)

# === Top-level flows
.PHONY: up down e2e pause resume
up: repos secrets platform tidy build deploy
	@echo
	@echo "Stack is up. Run 'make verify' to check it end-to-end, or 'make port-forward' to access it."

e2e: up verify ## Bring up the stack and run end-to-end verification.

pause: silence
	@kubectl get ns $(MON_NAMESPACE) >/dev/null 2>&1 || { echo "namespace $(MON_NAMESPACE) not found"; exit 0; }
	@echo "Pausing namespace $(MON_NAMESPACE)..."
	@for kind in deployment statefulset; do \
		for obj in $$(kubectl -n $(MON_NAMESPACE) get $$kind -o name 2>/dev/null); do \
			current=$$(kubectl -n $(MON_NAMESPACE) get $$obj -o jsonpath='{.spec.replicas}'); \
			[ -z "$$current" ] && current=1; \
			kubectl -n $(MON_NAMESPACE) annotate $$obj opensre.io/paused-replicas=$$current --overwrite >/dev/null; \
			kubectl -n $(MON_NAMESPACE) scale $$obj --replicas=0; \
		done; \
	done
	@for ds in $$(kubectl -n $(MON_NAMESPACE) get daemonset -o name 2>/dev/null); do \
		echo "Suspending $$ds via unschedulable nodeSelector..."; \
		kubectl -n $(MON_NAMESPACE) patch $$ds --type=strategic -p \
			'{"spec":{"template":{"spec":{"nodeSelector":{"opensre.io/paused":"true"}}}}}' >/dev/null; \
	done
	@echo
	@echo "Observability stack paused. App namespace ($(APP_NAMESPACE)) untouched."
	@echo "Resume with: make resume"

resume: ## Scale monitoring workloads back to their pre-pause replica counts.
	@kubectl get ns $(MON_NAMESPACE) >/dev/null 2>&1 || { echo "namespace $(MON_NAMESPACE) not found"; exit 0; }
	@echo "Resuming namespace $(MON_NAMESPACE)..."
	@for kind in deployment statefulset; do \
		for obj in $$(kubectl -n $(MON_NAMESPACE) get $$kind -o name 2>/dev/null); do \
			saved=$$(kubectl -n $(MON_NAMESPACE) get $$obj -o jsonpath="{.metadata.annotations['opensre\.io/paused-replicas']}"); \
			[ -z "$$saved" ] && saved=1; \
			kubectl -n $(MON_NAMESPACE) scale $$obj --replicas=$$saved; \
			kubectl -n $(MON_NAMESPACE) annotate $$obj opensre.io/paused-replicas- >/dev/null 2>&1 || true; \
		done; \
	done
	@for ds in $$(kubectl -n $(MON_NAMESPACE) get daemonset -o name 2>/dev/null); do \
		kubectl -n $(MON_NAMESPACE) patch $$ds --type=json \
			-p='[{"op":"remove","path":"/spec/template/spec/nodeSelector/opensre.io"}]' >/dev/null 2>&1 || true; \
	done
	@echo
	@echo "Observability stack resumed. Check with: make status"

down: silence ## Uninstall all Helm releases and delete the app + monitoring namespaces.
	-helm uninstall app -n $(APP_NAMESPACE)
	-helm uninstall tempo -n $(MON_NAMESPACE)
	-helm uninstall promtail -n $(MON_NAMESPACE)
	-helm uninstall loki -n $(MON_NAMESPACE)
	-helm uninstall $(KPS_RELEASE) -n $(MON_NAMESPACE)
	-kubectl delete ns $(APP_NAMESPACE) $(MON_NAMESPACE) --ignore-not-found

.PHONY: silence
silence: ## Create a 30-min Alertmanager silence on namespace=app (run before `make down`).
	@if ! kubectl -n $(MON_NAMESPACE) get svc $(KPS_RELEASE)-kube-prometheus-stack-alertmanager >/dev/null 2>&1; then \
		echo "Alertmanager service not found — skipping silence."; \
		exit 0; \
	fi
	@STARTS=$$(date -u +%Y-%m-%dT%H:%M:%SZ); \
	ENDS=$$(date -u -v+30M +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d "+30 min" +%Y-%m-%dT%H:%M:%SZ); \
	BODY=$$(printf '{"matchers":[{"name":"namespace","value":"app","isRegex":false}],"startsAt":"%s","endsAt":"%s","createdBy":"makefile","comment":"make down / teardown"}' "$$STARTS" "$$ENDS"); \
	echo "Silencing namespace=app until $$ENDS..."; \
	kubectl -n $(MON_NAMESPACE) run am-silence --rm -i --restart=Never --quiet \
		--image=curlimages/curl:8.10.1 --command -- \
		curl -sS -X POST -H 'content-type: application/json' \
			--data "$$BODY" \
			http://$(KPS_RELEASE)-kube-prometheus-stack-alertmanager:9093/api/v2/silences \
		|| echo "(silence post failed — continuing)"

# === Secrets
.PHONY: secrets
secrets: ## Create the grafana-slack Secret from .secrets/slack-token (gitignored).
	@test -s .secrets/slack-token || { \
		echo "Missing .secrets/slack-token. Put your Slack bot token (xoxb-...) in that file."; \
		exit 1; \
	}
	kubectl get ns $(MON_NAMESPACE) >/dev/null 2>&1 || kubectl create ns $(MON_NAMESPACE)
	kubectl -n $(MON_NAMESPACE) create secret generic grafana-slack \
		--from-literal=SLACK_TOKEN="$$(tr -d '\n' < .secrets/slack-token)" \
		--dry-run=client -o yaml | kubectl apply -f -

# === Platform (Prometheus, Grafana, Loki, Promtail, Tempo)
.PHONY: repos platform
repos: ## Add and update Helm repos.
	helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null
	helm repo add grafana https://grafana.github.io/helm-charts >/dev/null
	helm repo update >/dev/null

platform: ## Install kube-prometheus-stack, Loki, Promtail, and Tempo into the monitoring namespace.
	kubectl get ns $(MON_NAMESPACE) >/dev/null 2>&1 || kubectl create ns $(MON_NAMESPACE)
	helm upgrade --install $(KPS_RELEASE) prometheus-community/kube-prometheus-stack \
		-n $(MON_NAMESPACE) \
		-f platform/values-kube-prometheus-stack.yaml \
		--wait --timeout 10m
	helm upgrade --install loki grafana/loki \
		-n $(MON_NAMESPACE) \
		-f platform/values-loki.yaml \
		--wait --timeout 10m
	helm upgrade --install promtail grafana/promtail \
		-n $(MON_NAMESPACE) \
		-f platform/values-promtail.yaml \
		--wait --timeout 5m
	helm upgrade --install tempo grafana/tempo \
		-n $(MON_NAMESPACE) \
		-f platform/values-tempo.yaml \
		--wait --timeout 5m

# === App (build + deploy)
.PHONY: tidy build deploy redeploy
tidy: ## Run go mod tidy in both services (creates go.sum).
	cd services/gateway && go mod tidy
	cd services/backend && go mod tidy

build: ## Build gateway + backend images. Images are visible to Docker Desktop K8s when
	## the "containerd image store" setting is enabled (Docker Desktop → Settings → General).
	docker build -t $(GATEWAY_IMAGE) services/gateway
	docker build -t $(BACKEND_IMAGE) services/backend

deploy: ## Install/upgrade the app Helm release.
	kubectl get ns $(APP_NAMESPACE) >/dev/null 2>&1 || kubectl create ns $(APP_NAMESPACE)
	helm upgrade --install app charts/app \
		-n $(APP_NAMESPACE) \
		--set gateway.image.repository=$(word 1,$(subst :, ,$(GATEWAY_IMAGE))) \
		--set gateway.image.tag=$(word 2,$(subst :, ,$(GATEWAY_IMAGE))) \
		--set backend.image.repository=$(word 1,$(subst :, ,$(BACKEND_IMAGE))) \
		--set backend.image.tag=$(word 2,$(subst :, ,$(BACKEND_IMAGE))) \
		--set serviceMonitor.releaseLabel=$(KPS_RELEASE) \
		--wait --timeout 5m

redeploy: build ## Rebuild images and rollout-restart the app deployments.
	kubectl -n $(APP_NAMESPACE) rollout restart deployment/gateway deployment/backend
	kubectl -n $(APP_NAMESPACE) rollout status deployment/gateway
	kubectl -n $(APP_NAMESPACE) rollout status deployment/backend

# === Verify
.PHONY: verify
verify: ## End-to-end verification: pods Ready, app HTTP, Prometheus, Loki, Tempo.
	@APP_NAMESPACE=$(APP_NAMESPACE) MON_NAMESPACE=$(MON_NAMESPACE) KPS_RELEASE=$(KPS_RELEASE) \
		bash scripts/verify.sh

# === Access + demo
.PHONY: port-forward grafana-password demo status
port-forward: ## Port-forward Grafana (3000), Alertmanager (9093), PostgreSQL (5432), Gateway (8080). Ctrl-C to stop.
	@trap 'kill 0' EXIT; \
		kubectl -n $(MON_NAMESPACE) port-forward svc/$(KPS_RELEASE)-grafana 3000:80 >/dev/null & \
		kubectl -n $(MON_NAMESPACE) port-forward svc/$(KPS_RELEASE)-kube-prometheus-stack-alertmanager 9093:9093 >/dev/null & \
		kubectl -n $(APP_NAMESPACE) port-forward pod/postgres-0 5432:5432 >/dev/null & \
		kubectl -n $(APP_NAMESPACE) port-forward svc/gateway 8080:8080 >/dev/null & \
		sleep 2; \
		echo ""; \
		echo "Port-forwards ready:"; \
		echo "  Grafana:      http://localhost:3000  (admin / admin)"; \
		echo "  Alertmanager: http://localhost:9093"; \
		echo "  PostgreSQL:   localhost:5432  (user: app / db: app)"; \
		echo "  Gateway:      http://localhost:8080"; \
		echo ""; \
		echo "Ctrl-C to stop."; \
		wait

grafana-password: ## Print the Grafana admin password.
	@kubectl -n $(MON_NAMESPACE) get secret $(KPS_RELEASE)-grafana \
		-o jsonpath='{.data.admin-password}' | base64 -d; echo

demo: ## Hit the gateway in a loop to generate traces, logs, and metrics.
	@for i in 1 2 3 4 5; do \
		id=$$(curl -s -X POST http://localhost:8080/api/items \
			-H 'content-type: application/json' \
			-d "{\"name\":\"thing-$$i\"}" | jq -r .id); \
		echo "created $$id"; \
		curl -s http://localhost:8080/api/items/$$id >/dev/null; \
		curl -s http://localhost:8080/api/items/$$id >/dev/null; \
		sleep 0.3; \
	done
	@echo "Done. Open Grafana → Explore → Tempo / Loki."

status: ## Show platform + app pod status.
	kubectl -n $(MON_NAMESPACE) get pods
	@echo
	kubectl -n $(APP_NAMESPACE) get pods

.PHONY: chaos-load chaos-load-stop chaos-load-status \
        chaos-errors-backend chaos-errors-gateway \
        chaos-latency \
        chaos-crashloop chaos-oom \
        chaos-redis-down chaos-postgres-down chaos-gateway-down chaos-backend-down \
        chaos-reset

URL         ?= http://localhost:8080
DURATION    ?= 30m
CONCURRENCY ?= 10
RATE        ?= 5

chaos-load: ## Run sustained background traffic against the gateway (PID in /tmp/chaos-load.pid).
	@echo "Starting load generator. Expected effect: feeds rate(...) for SLO burn alerts."
	@echo "Reminder: 'make silence' must NOT be active. Stop with 'make chaos-load-stop'."
	@URL=$(URL) DURATION=$(DURATION) CONCURRENCY=$(CONCURRENCY) RATE=$(RATE) \
		bash scripts/chaos-load.sh start

chaos-load-stop: ## Stop the background load generator started by chaos-load.
	@bash scripts/chaos-load.sh stop

chaos-load-status: ## Show whether the load generator is running and tail its log.
	@bash scripts/chaos-load.sh status

chaos-errors-backend: ## Drive backend 5xx by killing Postgres while load runs. Expect AppBackendHighErrorRateFastBurn (2m) + AppPostgresDown (2m).
	@echo "Injecting backend errors: scaling postgres StatefulSet to 0 replicas."
	@echo "Expected alerts (need sustained load — start 'make chaos-load' first):"
	@echo "  AppPostgresDown                        for: 2m"
	@echo "  AppBackendHighErrorRateFastBurn        for: 2m (needs >0.05 rps + ratio > 7.2%)"
	@echo "  AppGatewayHighErrorRateFastBurn        for: 2m (gateway returns 502 on backend failure)"
	kubectl -n $(APP_NAMESPACE) scale statefulset/postgres --replicas=0
	@echo "Reset with: make chaos-reset"

chaos-errors-gateway: ## Drive gateway 5xx by killing the backend deployment while load runs. Expect AppGatewayHighErrorRateFastBurn (2m) + AppBackendDown (2m).
	@echo "Injecting gateway errors: scaling backend Deployment to 0 replicas."
	@echo "Expected alerts (need sustained load — start 'make chaos-load' first):"
	@echo "  AppBackendDown                         for: 2m"
	@echo "  AppGatewayHighErrorRateFastBurn        for: 2m (gateway proxy gets connection refused -> 502)"
	kubectl -n $(APP_NAMESPACE) scale deployment/backend --replicas=0
	@echo "Reset with: make chaos-reset"

chaos-latency: ## Throttle backend CPU to 5m so p99 climbs. Expect AppBackendHighLatencyP99 (10m) and likely AppGatewayHighLatencyP99 (10m).
	@echo "Injecting latency: patching backend container CPU limit to 5m (heavy throttling)."
	@echo "Expected alerts (need sustained load — start 'make chaos-load' first):"
	@echo "  AppBackendHighLatencyP99               for: 10m  (threshold 0.5s)"
	@echo "  AppGatewayHighLatencyP99               for: 10m  (threshold 1s, often follows)"
	kubectl -n $(APP_NAMESPACE) patch deployment/backend --type=strategic -p \
		'{"spec":{"template":{"spec":{"containers":[{"name":"backend","resources":{"limits":{"cpu":"5m"},"requests":{"cpu":"5m"}}}]}}}}'
	@echo "Reset with: make chaos-reset"

chaos-crashloop: ## Force gateway into CrashLoopBackOff via bogus image. Expect AppPodCrashLooping (1m) + AppGatewayDown (2m).
	@echo "Injecting crashloop: setting gateway image to busybox (no gateway binary inside)."
	@echo "Expected alerts:"
	@echo "  AppPodCrashLooping                     for: 1m   (increase(restarts)[5m] > 2)"
	@echo "  AppGatewayDown                         for: 2m   (Prometheus scrape fails)"
	@echo "  AppDeploymentReplicasMismatch          for: 10m"
	kubectl -n $(APP_NAMESPACE) set image deployment/gateway gateway=busybox:1.36
	@echo "Reset with: make chaos-reset"

chaos-oom: ## Patch backend memory limit to 8Mi so it OOMKills repeatedly. Expect AppContainerOOMKilled (1m).
	@echo "Injecting OOM: patching backend memory limit to 8Mi (Go runtime cannot start)."
	@echo "Expected alerts:"
	@echo "  AppContainerOOMKilled                  for: 1m"
	@echo "  AppBackendDown                         for: 2m"
	@echo "  AppPodCrashLooping                     for: 1m   (after enough OOMs)"
	kubectl -n $(APP_NAMESPACE) patch deployment/backend --type=strategic -p \
		'{"spec":{"template":{"spec":{"containers":[{"name":"backend","resources":{"limits":{"memory":"8Mi"},"requests":{"memory":"8Mi"}}}]}}}}'
	@echo "Reset with: make chaos-reset"

chaos-redis-down: ## Scale Redis Deployment to 0 replicas. Expect AppRedisDown (2m).
	@echo "Killing Redis: scaling deployment to 0 replicas."
	@echo "Expected alerts:"
	@echo "  AppRedisDown                           for: 2m"
	@echo "  (cache_lookups_total{result=\"error\"} climbs; backend stays up — Redis is a cache)"
	kubectl -n $(APP_NAMESPACE) scale deployment/redis --replicas=0
	@echo "Reset with: make chaos-reset"

chaos-postgres-down: ## Scale Postgres StatefulSet to 0 replicas. Expect AppPostgresDown (2m) + backend 5xx.
	@echo "Killing Postgres: scaling statefulset to 0 replicas."
	@echo "Expected alerts:"
	@echo "  AppPostgresDown  "
	kubectl -n $(APP_NAMESPACE) scale statefulset/postgres --replicas=0
	@echo "Reset with: make chaos-reset"

chaos-gateway-down: ## Scale gateway Deployment to 0 replicas. Expect AppGatewayDown (2m).
	@echo "Killing gateway: scaling deployment to 0 replicas."
	@echo "Expected alerts:"
	@echo "  AppGatewayDown   "
	kubectl -n $(APP_NAMESPACE) scale deployment/gateway --replicas=0
	@echo "Reset with: make chaos-reset"

chaos-backend-down: ## Scale backend Deployment to 0 replicas. Expect AppBackendDown (2m).
	@echo "Killing backend: scaling deployment to 0 replicas."
	@echo "Expected alerts:"
	@echo "  AppBackendDown "
	kubectl -n $(APP_NAMESPACE) scale deployment/backend --replicas=0
	@echo "Reset with: make chaos-reset"

# Reset: bring everything back to the chart defaults.

chaos-reset: ## Restore baseline: re-deploy chart, restart deployments, stop load, drop silences.
	@echo "Stopping load generator (if running)..."
	-@bash scripts/chaos-load.sh stop
	@echo "Re-applying app Helm release to restore image tags, replicas, and resource limits..."
	helm upgrade --install app charts/app \
		-n $(APP_NAMESPACE) \
		--set gateway.image.repository=$(word 1,$(subst :, ,$(GATEWAY_IMAGE))) \
		--set gateway.image.tag=$(word 2,$(subst :, ,$(GATEWAY_IMAGE))) \
		--set backend.image.repository=$(word 1,$(subst :, ,$(BACKEND_IMAGE))) \
		--set backend.image.tag=$(word 2,$(subst :, ,$(BACKEND_IMAGE))) \
		--set serviceMonitor.releaseLabel=$(KPS_RELEASE) \
		--wait --timeout 5m
	@echo "Restarting app deployments to flush any wedged pods..."
	-kubectl -n $(APP_NAMESPACE) rollout restart deployment/gateway deployment/backend deployment/redis
	-kubectl -n $(APP_NAMESPACE) rollout restart statefulset/postgres
	-kubectl -n $(APP_NAMESPACE) rollout status deployment/gateway --timeout=3m
	-kubectl -n $(APP_NAMESPACE) rollout status deployment/backend --timeout=3m
	@echo "Deleting Alertmanager silences created by the Makefile (best-effort)..."
	-@if kubectl -n $(MON_NAMESPACE) get svc $(KPS_RELEASE)-kube-prometheus-stack-alertmanager >/dev/null 2>&1; then \
		kubectl -n $(MON_NAMESPACE) run am-unsilence --rm -i --restart=Never --quiet \
			--image=curlimages/curl:8.10.1 --command -- sh -c \
			"curl -sS http://$(KPS_RELEASE)-kube-prometheus-stack-alertmanager:9093/api/v2/silences \
			 | sed -n 's/.*\"id\":\"\\([0-9a-f-]*\\)\"[^}]*\"createdBy\":\"makefile\".*/\\1/p' \
			 | xargs -r -n1 -I{} curl -sS -X DELETE http://$(KPS_RELEASE)-kube-prometheus-stack-alertmanager:9093/api/v2/silence/{}" \
			|| echo "(silence cleanup failed — continuing)"; \
	fi
	@echo "Reset complete. Verify with: make status && make verify"
