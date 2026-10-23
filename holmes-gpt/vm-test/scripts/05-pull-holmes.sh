#!/usr/bin/env bash
# Pulls the HolmesGPT Docker image and prints its version.
set -euo pipefail
source "$(dirname "$0")/lib.sh"

dockr pull "$HOLMES_IMAGE" | tail -1
echo "holmes $(dockr run --rm "$HOLMES_IMAGE" version 2>/dev/null | tail -1)"
