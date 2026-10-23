#!/usr/bin/env bash
# Installs kind, kubectl, Helm 4 and uv into ~/.local/bin (no sudo needed).
set -euo pipefail
source "$(dirname "$0")/lib.sh"

KIND_VERSION=${KIND_VERSION:-v0.27.0}
BIN=$HOME/.local/bin
mkdir -p "$BIN"
cd "$(mktemp -d)"

if ! command -v kind >/dev/null; then
  curl -fsSLo "$BIN/kind" "https://kind.sigs.k8s.io/dl/${KIND_VERSION}/kind-linux-amd64"
  chmod +x "$BIN/kind"
fi

if ! command -v kubectl >/dev/null; then
  KV=$(curl -fsSL https://dl.k8s.io/release/stable.txt)
  curl -fsSLo "$BIN/kubectl" "https://dl.k8s.io/release/${KV}/bin/linux/amd64/kubectl"
  chmod +x "$BIN/kubectl"
fi

if ! helm version --short 2>/dev/null | grep -q '^v4'; then
  HV=$(curl -fsSL https://api.github.com/repos/helm/helm/releases \
    | grep -o '"tag_name": "v4[^"]*"' | grep -v -- '-rc\|-beta\|-alpha' | head -1 | cut -d'"' -f4)
  curl -fsSL "https://get.helm.sh/helm-${HV}-linux-amd64.tar.gz" | tar xz
  mv linux-amd64/helm "$BIN/helm"
fi

command -v uv >/dev/null || curl -LsSf https://astral.sh/uv/install.sh | env UV_NO_MODIFY_PATH=1 sh

echo "kind    $(kind version | cut -d' ' -f2)"
echo "kubectl $(kubectl version --client | head -1 | cut -d' ' -f3)"
echo "helm    $(helm version --short)"
echo "uv      $(uv --version | cut -d' ' -f2)"
