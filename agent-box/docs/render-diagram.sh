#!/usr/bin/env bash
# Render the agent-box architecture diagram to dark + light PNGs from ONE source.
# Source of truth: docs/architecture.drawio (dark-themed -- edit this). The light
# variant is derived by a color swap, both exported via the draw.io desktop CLI.
#
# Usage:  ./render-diagram.sh   (or `make diagram` from agent-box/). Commit the PNGs.
set -euo pipefail
cd "$(dirname "$0")"

DRAWIO="${DRAWIO_BIN:-/Applications/draw.io.app/Contents/MacOS/draw.io}"
SCALE="${SCALE:-2}"
SRC="architecture.drawio"

[ -x "$DRAWIO" ] || { echo "draw.io CLI not found at $DRAWIO (set DRAWIO_BIN, or: brew install --cask drawio)"; exit 1; }

echo "==> dark  -> architecture-dark.png"
"$DRAWIO" -x -f png -t -s "$SCALE" --no-sandbox -o architecture-dark.png "$SRC" 2>/dev/null

echo "==> light -> architecture-light.png (derived from the dark source)"
LIGHT="$(mktemp -t agentbox-arch-light).drawio"
sed -E \
  -e 's/fillColor=#161616/fillColor=#f5f5f5/g' \
  -e 's/fillColor=#13161c/fillColor=#dae8fc/g' \
  -e 's/fillColor=#181320/fillColor=#e1d5e7/g' \
  -e 's/fillColor=#201313/fillColor=#f8cecc/g' \
  -e 's/fillColor=#14241c/fillColor=#d5e8d4/g' \
  -e 's/fontColor=#c8c8c8/fontColor=#333333/g' \
  -e 's/fontColor=#8a8a8a/fontColor=#666666/g' \
  -e 's/fontColor=#8088a0/fontColor=#5a627a/g' \
  -e 's/fontColor=#a0a0a0/fontColor=#777777/g' \
  -e 's/fontColor=#bcd0ec/fontColor=#1f3a5f/g' \
  -e 's/fontColor=#d2bfe2/fontColor=#4a2c66/g' \
  -e 's/fontColor=#e0a89f/fontColor=#6e2420/g' \
  -e 's/fontColor=#a6d6a6/fontColor=#2d5016/g' \
  -e 's/fontColor=#d79b00/fontColor=#9a7000/g' \
  -e 's/fontColor=#82b366/fontColor=#4f7a3a/g' \
  -e 's/strokeColor=#555555/strokeColor=#999999/g' \
  -e 's/strokeColor=#8a8a8a/strokeColor=#999999/g' \
  -e 's/strokeColor=#c8c8c8/strokeColor=#888888/g' \
  "$SRC" > "$LIGHT"
"$DRAWIO" -x -f png -t -s "$SCALE" --no-sandbox -o architecture-light.png "$LIGHT" 2>/dev/null
rm -f "$LIGHT"

echo "done: docs/architecture-dark.png + docs/architecture-light.png"
