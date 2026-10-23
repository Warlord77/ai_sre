#!/usr/bin/env bash
# Starts/stops SREGym's MCP server on its own (outside a benchmark run), for testing
# HolmesGPT's MCP connections. During `make run-one` SREGym starts it itself.
# Serves /prometheus, /loki, /jaeger, /kubectl, /submit (SSE) on 127.0.0.1:9954.
# Usage: scripts/mcp-server.sh start|stop|status
set -euo pipefail
source "$(dirname "$0")/lib.sh"

PORT=${MCP_SERVER_PORT:-9954}
LOG=${TMPDIR:-/tmp}/sregym-mcp-server.log

case ${1:-status} in
  start)
    ss -ltn | grep -q ":$PORT " && { echo "already listening on $PORT"; exit 0; }
    (cd "$SREGYM_ABS" && nohup uv run python -m mcp_server.sregym_mcp_server >"$LOG" 2>&1 &)
    for _ in $(seq 1 30); do ss -ltn | grep -q ":$PORT " && break; sleep 1; done
    ss -ltn | grep -q ":$PORT " && ok "MCP server on 127.0.0.1:$PORT (log $LOG)" || fail "did not start, see $LOG"
    ;;
  stop)
    pkill -f 'mcp_server.sregym_mcp_server' && ok "stopped" || echo "not running"
    ;;
  status)
    ss -ltn | grep -q ":$PORT " && ok "listening on $PORT" || echo "  not running"
    ;;
esac
