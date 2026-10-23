#!/usr/bin/env bash
# Prepares the SREGym checkout: app chart submodules, Python deps, pre-commit hook.
set -euo pipefail
source "$(dirname "$0")/lib.sh"

[[ -d "$SREGYM_ABS/.git" ]] || git clone --recurse-submodules https://github.com/SREGym/SREGym "$SREGYM_ABS"
cd "$SREGYM_ABS"
# Without the submodule every problem fails with "Helm chart_path does not exist".
git submodule update --init --recursive
uv sync
uv run prek install
.venv/bin/python -c "import sregym; print('sregym import OK')"
