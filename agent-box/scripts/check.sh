#!/usr/bin/env bash
set -euo pipefail

echo "=== user ==="
whoami

echo ""
echo "=== tools ==="
hermes --version
claude --version
kubectl version --client
helm version --short
gh --version | head -1

echo ""
echo "=== isolation: all three should say 'No such file or directory' ==="
ls ~/.ssh  2>&1 || true
ls ~/.aws  2>&1 || true
ls ~/.claude 2>&1 || true
env | grep AWS || echo "(no AWS vars - good)"

echo ""
echo "all checks passed"
