#!/usr/bin/env bash
# Optional: installs the Tailscale client for joining the one2n Headscale network.
# Run with sudo. As of 2026-10-23 headscale.one2n.io drops traffic from this VM
# (103.121.155.94), so the SSH tunnel in setup.md is used instead.
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "Run with sudo"; exit 1; }
curl -fsSL https://tailscale.com/install.sh | sh
systemctl enable --now tailscaled
tailscale set --operator="${SUDO_USER:-$USER}"
tailscale version | head -1
echo "Join with: tailscale up --login-server https://headscale.one2n.io --accept-routes"
