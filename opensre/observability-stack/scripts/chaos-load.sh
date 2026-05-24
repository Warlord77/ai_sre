#!/usr/bin/env bash
# Sustained load generator against the gateway.
# Usage:
#   scripts/chaos-load.sh start
#   scripts/chaos-load.sh stop
#   scripts/chaos-load.sh status

set -uo pipefail

URL="${URL:-http://localhost:8080}"
DURATION="${DURATION:-30m}"
CONCURRENCY="${CONCURRENCY:-10}"
RATE="${RATE:-5}"
PIDFILE="${PIDFILE:-/tmp/chaos-load.pid}"

cmd="${1:-start}"

# Convert "30m" / "2h" / "45s" / "120" to seconds. Used by the curl fallback.
to_seconds() {
  local d="$1"
  case "$d" in
    *s) echo "${d%s}" ;;
    *m) echo $(( ${d%m} * 60 )) ;;
    *h) echo $(( ${d%h} * 3600 )) ;;
    *)  echo "$d" ;;
  esac
}

is_running() {
  [ -f "$PIDFILE" ] || return 1
  local pid
  pid=$(cat "$PIDFILE" 2>/dev/null || echo "")
  [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null
}

start_hey() {
  nohup hey \
    -z "$DURATION" \
    -c "$CONCURRENCY" \
    -q "$RATE" \
    -m POST \
    -H 'content-type: application/json' \
    -d '{"name":"chaos"}' \
    "$URL/api/items" \
    >/tmp/chaos-load.log 2>&1 &
  echo $! > "$PIDFILE"
}

start_curl() {
  local total_sec
  total_sec=$(to_seconds "$DURATION")

  nohup bash -c '
    URL="'"$URL"'"
    CONCURRENCY="'"$CONCURRENCY"'"
    RATE="'"$RATE"'"
    TOTAL='"$total_sec"'
    end=$(( $(date +%s) + TOTAL ))
    pids=()
    for i in $(seq 1 "$CONCURRENCY"); do
      (
        while [ "$(date +%s)" -lt "$end" ]; do
          curl -sS -o /dev/null -m 3 \
            -X POST -H "content-type: application/json" \
            -d "{\"name\":\"chaos-$i\"}" \
            "$URL/api/items" || true
          if [ "$RATE" -gt 0 ]; then
            sleep "$(awk "BEGIN { printf \"%.3f\", 1.0 / $RATE }")"
          fi
        done
      ) &
      pids+=("$!")
    done
    # Wait, but on TERM kill children first.
    trap "for p in ${pids[*]}; do kill \$p 2>/dev/null || true; done; exit 0" TERM INT
    wait
  ' >/tmp/chaos-load.log 2>&1 &
  echo $! > "$PIDFILE"
}

case "$cmd" in
  start)
    if is_running; then
      echo "chaos-load already running (pid=$(cat "$PIDFILE")). Run 'chaos-load-stop' first."
      exit 0
    fi
    echo "Target:       $URL"
    echo "Duration:     $DURATION"
    echo "Concurrency:  $CONCURRENCY"
    echo "Rate/worker:  $RATE rps"
    echo "Log:          /tmp/chaos-load.log"
    if command -v hey >/dev/null 2>&1; then
      echo "Engine:       hey"
      start_hey
    else
      echo "Engine:       curl (hey not on PATH)"
      start_curl
    fi
    echo "Started pid=$(cat "$PIDFILE"). Stop with 'make chaos-load-stop'."
    ;;
  stop)
    if ! is_running; then
      echo "chaos-load is not running."
      rm -f "$PIDFILE"
      exit 0
    fi
    pid=$(cat "$PIDFILE")
    echo "Stopping chaos-load pid=$pid..."
    # Kill children first (curl workers / hey subprocs), then the wrapper.
    pkill -P "$pid" 2>/dev/null || true
    kill "$pid" 2>/dev/null || true
    sleep 1
    kill -9 "$pid" 2>/dev/null || true
    rm -f "$PIDFILE"
    echo "Stopped."
    ;;
  status)
    if is_running; then
      echo "chaos-load is running (pid=$(cat "$PIDFILE"))."
      echo "Log tail:"
      tail -n 5 /tmp/chaos-load.log 2>/dev/null || true
    else
      echo "chaos-load is not running."
      [ -f "$PIDFILE" ] && rm -f "$PIDFILE"
    fi
    ;;
  *)
    echo "Usage: $0 {start|stop|status}"
    exit 2
    ;;
esac
