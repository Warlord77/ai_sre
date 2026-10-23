#!/usr/bin/env bash
# Interactive menu: choose which SREGym-Lite problems to run.
set -uo pipefail
source "$(dirname "$0")/common.sh"

mapfile -t ALL < <(lite_problems)
echo "SREGym-Lite problems (agent: $MODEL):"
for i in "${!ALL[@]}"; do printf '  %2d) %s\n' $((i + 1)) "${ALL[i]}"; done
echo
read -rp "Run which? (e.g. 3 | 1,4,7 | 2-5 | all, empty to cancel): " sel
[[ -n $sel ]] || { echo "cancelled"; exit 0; }
mapfile -t CHOSEN < <(resolve_problems "$sel") || exit 1
printf '  %s\n' "${CHOSEN[@]}"
read -rp "Run these ${#CHOSEN[@]} problem(s)? [y/N] " yn
[[ $yn =~ ^[Yy] ]] || { echo "cancelled"; exit 0; }
exec bash "$(dirname "$0")/run.sh" "$sel"
