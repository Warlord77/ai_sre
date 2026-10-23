#!/usr/bin/env bash
# Installs Docker and sets the inotify limits kind needs. Run with sudo:
#   sudo bash scripts/01-install-docker.sh
# Log out and back in afterwards so the docker group applies to your shell.
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "Run with sudo"; exit 1; }
USER_NAME=${SUDO_USER:-$USER}

command -v docker >/dev/null || curl -fsSL https://get.docker.com | sh
usermod -aG docker "$USER_NAME"
systemctl enable --now docker

# SREGym kind README: low inotify limits crash kube-proxy with "too many open files".
printf "fs.inotify.max_user_instances=1024\nfs.inotify.max_user_watches=1048576\n" > /etc/sysctl.d/99-sregym-kind.conf
sysctl --system >/dev/null

command -v make >/dev/null || apt-get install -y make
echo "DONE: docker $(docker --version | cut -d' ' -f3 | tr -d ,), user $USER_NAME added to group docker"
