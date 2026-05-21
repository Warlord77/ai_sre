# ── base: minimal shared layer for all agent variants ─────────────────────────
# python:3.13-slim is the Hermes upstream runtime (Debian bookworm base).
# Pin to digest for reproducibility:
#   docker pull python:3.13-slim && docker inspect --format='{{index .RepoDigests 0}}' python:3.13-slim
FROM python:3.13-slim AS base

ENV DEBIAN_FRONTEND=noninteractive

# pipefail: fail if any command in a pipe fails, not just the last one
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# ca-certificates + curl: HTTPS downloads (pip git+https, nodesource setup)
# git: required by pip to install hermes-agent from a git URL
# jq + make: used by Makefile targets and launch scripts
# hadolint ignore=DL3008
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl git jq make \
  && rm -rf /var/lib/apt/lists/*

# ARG-based UID/GID - devcontainer updateRemoteUserUID syncs this to the host user at runtime.
ARG USERNAME=agent
ARG USER_UID=1000
ARG USER_GID=${USER_UID}

RUN groupadd --gid "${USER_GID}" "${USERNAME}" \
  && useradd --uid "${USER_UID}" --gid "${USER_GID}" --create-home --shell /bin/bash "${USERNAME}" \
  && mkdir -p /workspace \
  && chown "${USERNAME}":"${USERNAME}" /workspace \
  && echo '{ [ "$TERM_PROGRAM" = "vscode" ] || [ -n "$VSCODE_IPC_HOOK_CLI" ]; } && [ -f /tmp/.autorun ] && { _cmd=$(cat /tmp/.autorun); rm -f /tmp/.autorun; eval "$_cmd"; }' \
      >> /home/agent/.bashrc \
  # VS Code attached containers ignore devcontainer.json settings; .vscode/settings.json in workspaceFolder is the only way to control the editor layout.
  && mkdir -p /home/agent/.vscode \
  && printf '{\n  "workbench.panel.opensMaximized": "never",\n  "terminal.integrated.defaultHeight": 12\n}\n' \
      > /home/agent/.vscode/settings.json \
  && chown -R "${USERNAME}":"${USERNAME}" /home/agent/.vscode

USER ${USERNAME}
WORKDIR /workspace
CMD ["bash"]

# ── hermes: Hermes agent (Option A - DeepSeek API key) ──────────────────────
FROM base AS hermes

LABEL org.opencontainers.image.title="agent-box-hermes" \
      org.opencontainers.image.description="Isolated devcontainer for Hermes AI agent (DeepSeek via API key)" \
      org.opencontainers.image.vendor="one2n" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.source="https://github.com/one2nc/ai-bites"

ENV HERMES_HOME=/home/agent/.hermes

USER root
# Hermes: pinned to v2026.4.30, no [all] extras - skips Playwright/web/TUI.
# hadolint ignore=DL3016
RUN pip install --no-cache-dir \
    "hermes-agent @ git+https://github.com/NousResearch/hermes-agent.git@v2026.4.30"
USER agent

# ── claude: Claude Code (Option B - Anthropic OAuth) ────────────────────────
FROM base AS claude

LABEL org.opencontainers.image.title="agent-box-claude" \
      org.opencontainers.image.description="Isolated devcontainer for Claude Code AI agent (Anthropic OAuth)" \
      org.opencontainers.image.vendor="one2n" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.source="https://github.com/one2nc/ai-bites"

USER root
# Node.js 20 is required by Claude Code and only needed in this stage.
# gnupg is required by the NodeSource setup script for APT key verification.
# hadolint ignore=DL3008
RUN apt-get update && apt-get install -y --no-install-recommends gnupg \
  && curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
  && apt-get install -y --no-install-recommends nodejs \
  && rm -rf /var/lib/apt/lists/*
# hadolint ignore=DL3016
RUN npm install -g @anthropic-ai/claude-code
USER agent

# ── add new agents below as additional FROM base AS <name> stages ────────────
