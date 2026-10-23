"""Checks that the configured model answers a tool call through LiteLLM, the library
HolmesGPT and SREGym's judge both use. Run with SREGym's venv python.
Usage: check-model.py <litellm-model>
"""
import json
import sys

import litellm

model = sys.argv[1]
tools = [{
    "type": "function",
    "function": {
        "name": "kubectl_get",
        "description": "Run kubectl get",
        "parameters": {
            "type": "object",
            "properties": {"kind": {"type": "string"}, "namespace": {"type": "string"}},
            "required": ["kind", "namespace"],
        },
    },
}]
try:
    r = litellm.completion(
        model=model,
        messages=[{"role": "user", "content": "List the pods in namespace default."}],
        tools=tools,
        max_tokens=2000,
        timeout=180,
    )
except Exception as e:  # report any provider error in one line
    print(f"  ❌ {model}: {type(e).__name__}: {str(e)[:300]}")
    sys.exit(1)

calls = r.choices[0].message.tool_calls
if not calls:
    print(f"  ❌ {model}: answered without a tool call (finish_reason={r.choices[0].finish_reason}); "
          "HolmesGPT needs tool calling. Self-hosted vLLM: --enable-auto-tool-choice --tool-call-parser <parser>")
    sys.exit(1)
f = calls[0].function
print(f"  ✅ {model}: tool call {f.name}({json.dumps(json.loads(f.arguments))})")
