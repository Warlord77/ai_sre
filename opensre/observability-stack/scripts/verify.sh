#!/usr/bin/env bash
set -uo pipefail

APP_NS="${APP_NAMESPACE:-app}"
MON_NS="${MON_NAMESPACE:-monitoring}"
KPS_RELEASE="${KPS_RELEASE:-kps}"

GATEWAY_PORT=18080
PROM_PORT=19090
LOKI_PORT=13100
TEMPO_PORT=13200

PASS=0
FAIL=0
PIDS=()

cleanup() {
  for pid in "${PIDS[@]:-}"; do
    [ -n "${pid:-}" ] && kill "$pid" 2>/dev/null || true
  done
}
trap cleanup EXIT

if [ -t 1 ]; then
  C_GREEN=$'\033[32m'; C_RED=$'\033[31m'; C_DIM=$'\033[2m'; C_BOLD=$'\033[1m'; C_RESET=$'\033[0m'
else
  C_GREEN=''; C_RED=''; C_DIM=''; C_BOLD=''; C_RESET=''
fi

step()    { printf "  %-54s" "$1"; }
ok()      { printf " [ %sPASS%s ]" "$C_GREEN" "$C_RESET"; [ $# -gt 0 ] && printf " %s%s%s" "$C_DIM" "$1" "$C_RESET"; echo; PASS=$((PASS+1)); }
softfail(){ printf " [ %sFAIL%s ]" "$C_RED"   "$C_RESET"; [ $# -gt 0 ] && printf " %s" "$1"; echo; FAIL=$((FAIL+1)); }
hardfail(){ softfail "$@"; echo; printf "%sCannot continue.%s\n" "$C_RED" "$C_RESET"; exit 1; }
section() { printf "\n%s── %s%s\n\n" "$C_BOLD" "$1" "$C_RESET"; }

# Normalize jq output to a non-negative integer; treat "null"/empty as 0.
to_int() {
  local v=${1:-0}
  case "$v" in
    ''|null) v=0 ;;
  esac
  [[ "$v" =~ ^[0-9]+$ ]] || v=0
  echo "$v"
}

start_pf() {
  local ns=$1 svc=$2 lp=$3 rp=$4
  kubectl -n "$ns" port-forward "svc/$svc" "${lp}:${rp}" >/dev/null 2>&1 &
  PIDS+=("$!")
}

wait_http() {
  local url=$1 timeout=${2:-15}
  for _ in $(seq 1 "$timeout"); do
    if curl -fsS --max-time 1 -o /dev/null "$url" 2>/dev/null; then return 0; fi
    sleep 1
  done
  return 1
}

# ────────────────────────────────────────────────────────────────────────────
section "Cluster"

step "kubectl reaches a cluster"
if kubectl cluster-info >/dev/null 2>&1; then
  ctx=$(kubectl config current-context 2>/dev/null || echo unknown)
  ok "context=$ctx"
else
  hardfail "no reachable cluster in current kubectl context"
fi

for ns in "$MON_NS" "$APP_NS"; do
  step "namespace ${ns} exists"
  if kubectl get ns "$ns" >/dev/null 2>&1; then ok; else softfail; fi
done

# ────────────────────────────────────────────────────────────────────────────
section "Pod readiness"

ready_in() {
  local ns=$1
  kubectl -n "$ns" get pods --no-headers 2>/dev/null | awk '
    {
      split($2, r, "/");
      if (r[1] != r[2] || ($3 != "Running" && $3 != "Completed")) {
        print $1 " (" $3 ")";
      }
    }'
}

for ns in "$MON_NS" "$APP_NS"; do
  total=$(kubectl -n "$ns" get pods --no-headers 2>/dev/null | wc -l | tr -d ' ')
  step "all ${total} pods Ready in ${ns}"
  not_ready=$(ready_in "$ns")
  if [ -z "$not_ready" ] && [ "$total" -gt 0 ]; then
    ok
  else
    softfail "$(echo "$not_ready" | tr '\n' ' ')"
  fi
done

# ────────────────────────────────────────────────────────────────────────────
section "Required services"

PROM_SVC="${KPS_RELEASE}-kube-prometheus-stack-prometheus"
declare -a SVC_LIST=(
  "${APP_NS}/gateway"
  "${MON_NS}/${PROM_SVC}"
  "${MON_NS}/loki"
  "${MON_NS}/tempo"
)

missing=0
for entry in "${SVC_LIST[@]}"; do
  ns=${entry%/*}; svc=${entry#*/}
  step "service ${ns}/${svc} exists"
  if kubectl -n "$ns" get svc "$svc" >/dev/null 2>&1; then ok; else softfail; missing=1; fi
done

if [ "$missing" -eq 1 ]; then
  echo
  printf "%sCannot continue without all four services.%s\n" "$C_RED" "$C_RESET"
  echo "If kube-prometheus-stack uses a different release name, run:"
  echo "    make verify KPS_RELEASE=<your-release-name>"
  exit 1
fi

# ────────────────────────────────────────────────────────────────────────────
section "Connectivity (port-forward)"

start_pf "$APP_NS" gateway     "$GATEWAY_PORT" 8080
start_pf "$MON_NS" "$PROM_SVC" "$PROM_PORT"    9090
start_pf "$MON_NS" loki        "$LOKI_PORT"    3100
start_pf "$MON_NS" tempo       "$TEMPO_PORT"   3200

step "gateway reachable on :${GATEWAY_PORT}"
wait_http "http://localhost:${GATEWAY_PORT}/healthz" 20 && ok || softfail
step "Prometheus reachable on :${PROM_PORT}"
wait_http "http://localhost:${PROM_PORT}/-/ready"     20 && ok || softfail
step "Loki reachable on :${LOKI_PORT}"
wait_http "http://localhost:${LOKI_PORT}/ready"       20 && ok || softfail
step "Tempo reachable on :${TEMPO_PORT}"
wait_http "http://localhost:${TEMPO_PORT}/ready"      20 && ok || softfail

# ────────────────────────────────────────────────────────────────────────────
section "Application end-to-end"

step "GET /healthz returns 200"
[ "$(curl -sS -o /dev/null -w '%{http_code}' "http://localhost:${GATEWAY_PORT}/healthz")" = "200" ] && ok || softfail

step "GET /readyz returns 200 (probes Postgres + Redis)"
[ "$(curl -sS -o /dev/null -w '%{http_code}' "http://localhost:${GATEWAY_PORT}/readyz")" = "200" ] && ok || softfail

step "POST /api/items writes to Postgres"
ITEM_ID=$(curl -sS -X POST "http://localhost:${GATEWAY_PORT}/api/items" \
  -H 'content-type: application/json' \
  -d '{"name":"verify-probe"}' 2>/dev/null | jq -r .id 2>/dev/null || echo "")
if [[ "$ITEM_ID" =~ ^[0-9a-f-]{36}$ ]]; then
  ok "id=${ITEM_ID:0:8}…"
else
  softfail "got: ${ITEM_ID:-<empty>}"
  ITEM_ID=""
fi

if [ -n "$ITEM_ID" ]; then
  step "GET /api/items/{id} returns the item"
  got=$(curl -sS "http://localhost:${GATEWAY_PORT}/api/items/${ITEM_ID}" | jq -r .id 2>/dev/null || echo "")
  [ "$got" = "$ITEM_ID" ] && ok || softfail "got: $got"

  step "2nd GET produces a 'cache hit' log line"
  curl -sS "http://localhost:${GATEWAY_PORT}/api/items/${ITEM_ID}" >/dev/null
  found=0
  for _ in $(seq 1 10); do
    sleep 1
    if kubectl -n "$APP_NS" logs -l app.kubernetes.io/name=backend --tail=200 2>/dev/null | grep -q "\"cache hit\".*${ITEM_ID}"; then
      found=1
      break
    fi
  done
  if [ "$found" -eq 1 ]; then
    ok
  else
    softfail "no 'cache hit' log line in backend (Redis path may be broken)"
  fi
fi

# ────────────────────────────────────────────────────────────────────────────
section "Generating sample traffic"

for i in 1 2 3 4 5; do
  id=$(curl -sS -X POST "http://localhost:${GATEWAY_PORT}/api/items" \
    -H 'content-type: application/json' \
    -d "{\"name\":\"probe-${i}\"}" 2>/dev/null | jq -r .id 2>/dev/null || echo "")
  if [ -n "$id" ] && [ "$id" != "null" ]; then
    curl -sS "http://localhost:${GATEWAY_PORT}/api/items/${id}" >/dev/null
    curl -sS "http://localhost:${GATEWAY_PORT}/api/items/${id}" >/dev/null
  fi
done
echo "  Sleeping 25s for Prometheus scrape (~15s) + Tempo batch export…"
sleep 25

# ────────────────────────────────────────────────────────────────────────────
section "Observability backends"

q_prom() {
  curl -sS --get --data-urlencode "query=$1" \
    "http://localhost:${PROM_PORT}/api/v1/query" \
    | jq -r '.data.result | length' 2>/dev/null
}

step "Prometheus has 'up' targets in ${APP_NS}"
n=$(to_int "$(q_prom "up{namespace=\"${APP_NS}\"}")")
[ "$n" -ge 2 ] && ok "$n targets" || softfail "${n} target(s) — expected ≥2 (gateway+backend)"

step "Prometheus has http_requests_total samples"
n=$(to_int "$(q_prom 'http_requests_total')")
[ "$n" -gt 0 ] && ok "$n series" || softfail "no series — ServiceMonitor not picked up?"

step "Prometheus has Tempo service-graph metrics"
n=$(to_int "$(q_prom 'traces_service_graph_request_total')")
if [ "$n" -gt 0 ]; then
  ok "$n series"
else
  softfail "may take a few minutes after first traffic"
fi

# Loki query window: last 10 minutes.
end_ns=$(date +%s)000000000
start_ns=$(( $(date +%s) - 600 ))000000000

q_loki() {
  curl -sS --get \
    --data-urlencode "query=$1" \
    --data-urlencode "start=${start_ns}" \
    --data-urlencode "end=${end_ns}" \
    --data-urlencode "limit=5" \
    "http://localhost:${LOKI_PORT}/loki/api/v1/query_range" \
    | jq -r '.data.result | length' 2>/dev/null
}

step "Loki has logs from ${APP_NS} namespace"
n=$(to_int "$(q_loki "{namespace=\"${APP_NS}\"}")")
[ "$n" -gt 0 ] && ok "$n streams" || softfail "no streams — promtail not shipping?"

step "Loki has 'item created' lines (backend → Loki)"
n=$(to_int "$(q_loki "{namespace=\"${APP_NS}\"} |= \"item created\"")")
[ "$n" -gt 0 ] && ok || softfail

step "Loki log lines include trace_id (logs↔traces correlation)"
n=$(to_int "$(q_loki "{namespace=\"${APP_NS}\"} |= \"trace_id\"")")
[ "$n" -gt 0 ] && ok || softfail "trace correlation missing"

q_tempo() {
  curl -sS --get \
    --data-urlencode "tags=service.name=$1" \
    --data-urlencode 'limit=5' \
    "http://localhost:${TEMPO_PORT}/api/search" \
    | jq -r '.traces | length' 2>/dev/null
}

step "Tempo has traces with service.name=gateway"
n=$(to_int "$(q_tempo gateway)")
[ "$n" -gt 0 ] && ok "$n traces" || softfail "no traces — OTLP export not working?"

step "Tempo has traces with service.name=backend"
n=$(to_int "$(q_tempo backend)")
[ "$n" -gt 0 ] && ok "$n traces" || softfail

# ────────────────────────────────────────────────────────────────────────────
echo
printf "%s── Summary%s\n\n" "$C_BOLD" "$C_RESET"
if [ "$FAIL" -eq 0 ]; then
  printf "  %s%d passed%s, %d failed\n" "$C_GREEN" "$PASS" "$C_RESET" "$FAIL"
  printf "  %sStack is healthy end-to-end.%s\n" "$C_GREEN" "$C_RESET"
else
  printf "  %s%d passed%s, %s%d failed%s\n" "$C_GREEN" "$PASS" "$C_RESET" "$C_RED" "$FAIL" "$C_RESET"
  echo "  See the failed checks above and the Troubleshooting section in README.md."
fi

exit "$FAIL"
