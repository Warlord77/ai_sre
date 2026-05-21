# ── base: shared tooling for all agent variants ─────────────────────────────
# python:3.13-slim matches Hermes upstream runtime (Debian bookworm base).
# Pin to digest for reproducibility:
#   docker pull python:3.13-slim && docker inspect --format='{{index .RepoDigests 0}}' python:3.13-slim
FROM python:3.13-slim AS base

ENV DEBIAN_FRONTEND=noninteractive
# Hermes data dir lives inside the container, not on host
ENV HERMES_HOME=/home/agent/.hermes

# pipefail: fail if any command in a pipe fails, not just the last one
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# ── system deps + Node.js 20 + gh CLI + kubectl + helm ────────────────────────
# Single RUN - one layer, apt-get update always paired with install.
# kubectl/helm installed via official channels so download is platform-aware.
# hadolint ignore=DL3008
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl git gnupg jq make apt-transport-https \
  && curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
  && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | \
      dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg \
  && chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg \
  && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
      > /etc/apt/sources.list.d/github-cli.list \
  && apt-get update && apt-get install -y --no-install-recommends nodejs gh \
  && KUBE_ARCH=$(dpkg --print-architecture) \
  && KUBE_VER=$(curl --retry 3 --retry-delay 5 -fsSL https://dl.k8s.io/release/stable.txt) \
  && curl --retry 3 --retry-delay 5 -fsSL "https://dl.k8s.io/release/${KUBE_VER}/bin/linux/${KUBE_ARCH}/kubectl" \
      -o /usr/local/bin/kubectl \
  && chmod 0755 /usr/local/bin/kubectl \
  && HELM_ARCH=$(dpkg --print-architecture) \
  && HELM_VER=$(curl --retry 3 --retry-delay 5 -fsSL https://api.github.com/repos/helm/helm/releases/latest | grep '"tag_name"' | cut -d'"' -f4) \
  && curl --retry 3 --retry-delay 5 -fsSL "https://get.helm.sh/helm-${HELM_VER}-linux-${HELM_ARCH}.tar.gz" \
      | tar -xz --strip-components=1 -C /usr/local/bin "linux-${HELM_ARCH}/helm" \
  && rm -rf /var/lib/apt/lists/*

# ── non-root user ──────────────────────────────────────────────────────────────
# ARG-based UID/GID - not hardcoded (one2n principle: don't bind to a specific UID).
# devcontainer updateRemoteUserUID syncs this to the host user at runtime.
ARG USERNAME=agent
ARG USER_UID=1000
ARG USER_GID=${USER_UID}

RUN groupadd --gid "${USER_GID}" "${USERNAME}" \
  && useradd --uid "${USER_UID}" --gid "${USER_GID}" --create-home --shell /bin/bash "${USERNAME}" \
  && mkdir -p /workspace \
  && chown "${USERNAME}":"${USERNAME}" /workspace \
  && echo '[ "$TERM_PROGRAM" = "vscode" ] && [ -f /tmp/.autorun ] && { _cmd=$(cat /tmp/.autorun); rm -f /tmp/.autorun; eval "$_cmd"; }' \
      >> /home/agent/.bashrc

USER ${USERNAME}
WORKDIR /workspace
CMD ["bash"]

# ── agent-box: Hermes + Claude Code, used by devcontainer.json ───────────────
FROM base AS agent-box

LABEL org.opencontainers.image.title="agent-box" \
      org.opencontainers.image.description="Isolated devcontainer for AI coding agents - Hermes (DeepSeek) + Claude Code (OAuth)" \
      org.opencontainers.image.vendor="one2n" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.source="https://github.com/one2nc/ai-bites"

USER root
# Hermes: pinned to v2026.4.30, no [all] extras - skips Playwright/web/TUI.
# hadolint ignore=DL3016
RUN pip install --no-cache-dir \
    "hermes-agent @ git+https://github.com/NousResearch/hermes-agent.git@v2026.4.30" \
  && npm install -g @anthropic-ai/claude-code
USER agent
