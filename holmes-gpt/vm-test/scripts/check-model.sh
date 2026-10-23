#!/usr/bin/env bash
# Checks the model endpoint: tunnel, model listed, and that tool calls come back parsed.
# HolmesGPT only works when the last check passes.
set -euo pipefail
source "$(dirname "$0")/lib.sh"

MODEL_ID=${MODEL#openai/}
echo "Endpoint $OPENAI_API_BASE, model $MODEL_ID"

if [[ " ${HOLMES_EXTRA_HOSTS:-} " == *":127.0.0.1"* ]]; then
  port=$(sed -nE 's#^https?://[^:/]+:([0-9]+).*#\1#p' <<<"$OPENAI_API_BASE")
  ss -ltn | grep -q ":${port:-443} " && ok "tunnel listening on 127.0.0.1:${port:-443}" \
    || fail "nothing listening on 127.0.0.1:${port:-443}: start the SSH tunnel (setup.md, Model access)"
fi

models=$(model_curl -m 30 "$OPENAI_API_BASE/models" | python3 -c 'import json,sys; print(" ".join(m["id"] for m in json.load(sys.stdin)["data"]))') \
  || fail "could not list models"
[[ " $models " == *" $MODEL_ID "* ]] && ok "model listed ($models)" || fail "$MODEL_ID not in: $models"

body=$(python3 -c 'import json,sys; print(json.dumps({"model": sys.argv[1], "max_tokens": 1000,
  "messages": [{"role": "user", "content": "List the pods in namespace default."}],
  "tools": [{"type": "function", "function": {"name": "kubectl_get", "description": "Run kubectl get",
    "parameters": {"type": "object", "properties": {"kind": {"type": "string"}, "namespace": {"type": "string"}},
    "required": ["kind", "namespace"]}}}]}))' "$MODEL_ID")
model_curl -m 240 "$OPENAI_API_BASE/chat/completions" -H 'Content-Type: application/json' -d "$body" \
  | python3 -c '
import json, sys
d = json.load(sys.stdin)
if "choices" not in d:
    print("  ❌ request failed:", json.dumps(d)[:300]); sys.exit(1)
calls = d["choices"][0]["message"].get("tool_calls")
if not calls:
    print("  ❌ no tool call returned: the server needs --enable-auto-tool-choice and the right --tool-call-parser"); sys.exit(1)
f = calls[0]["function"]
print("  ✅ tool call parsed: %s(%s)" % (f["name"], f["arguments"]))'
