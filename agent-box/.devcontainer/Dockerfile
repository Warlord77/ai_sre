# ── base: minimal shared layer for all agent variants ─────────────────────────
# python:3.13-slim (Debian bookworm) -- minimal base layer; Node is added in the claude stage.
# Pin to digest for reproducibility:
#   docker pull python:3.13-slim && docker inspect --format='{{index .RepoDigests 0}}' python:3.13-slim
FROM python:3.13-slim AS base

ENV DEBIAN_FRONTEND=noninteractive

# pipefail: fail if any command in a pipe fails, not just the last one
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# ca-certificates + curl: HTTPS downloads (nodesource setup, generic)
# git: standard dev tool inside the container
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
  && echo '[ -f /tmp/.autorun ] && { _cmd=$(cat /tmp/.autorun); rm -f /tmp/.autorun; eval "$_cmd"; }' \
      >> /home/agent/.bashrc

USER ${USERNAME}
WORKDIR /workspace
CMD ["bash"]

# ── claude: Claude Code (Anthropic non-interactive auth) ────────────────────
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

# Pre-populate ~/.claude.json so first interactive `claude` skips the
# onboarding wizard (theme picker + syntax-theme picker + /login OAuth URL +
# workspace-trust dialog). Without these markers, every fresh container would
# show all four prompts on first interactive launch -- defeating the
# unattended/CI use case. CLAUDE_CODE_OAUTH_TOKEN handles the actual auth.
#
# The template ships with __CLAUDE_VERSION__ as a placeholder; sed replaces it
# with the version of @anthropic-ai/claude-code that npm installed above, so
# the marker stays in sync with the installed binary.
#
# Refs:
#   https://code.claude.com/docs/en/authentication  (env-var auth precedence)
#   anthropics/claude-code#9113                     (pre-configured trust)
COPY .devcontainer/claude-onboarding-bypass.json /home/agent/.claude.json
RUN sed -i "s/__CLAUDE_VERSION__/$(claude --version | awk '{print $1}')/" /home/agent/.claude.json \
  && chown agent:agent /home/agent/.claude.json \
  && chmod 600 /home/agent/.claude.json

# Launcher: strips empty Claude auth env vars (devcontainer fills them with ""
# when the host var is unset, which Claude treats as "set" and prefers over
# CLAUDE_CODE_OAUTH_TOKEN at lower precedence), prints a one-line auth banner,
# then execs `claude`. With the onboarding markers baked above, `claude` lands
# directly at its REPL.
COPY .devcontainer/claude-launch.sh /usr/local/bin/claude-launch
RUN chmod +x /usr/local/bin/claude-launch

# Skills: bake the agent-box-curated skills set into the image so every
# Claude invocation (REPL or headless) has the same persona library.
# Skills live at the agent-box repo root (top-level concept), not inside
# .devcontainer/ -- so the build context must be the agent-box root, not
# .devcontainer/. start.sh handles this.
COPY --chown=agent:agent skills/ /home/agent/.claude/skills/

USER agent

# Trust any bind-mounted repo regardless of its host owner uid. headless/ralph runs
# mount the caller's cwd, whose files are owned by the host user, not `agent` (uid
# 1000) -- without this, git refuses with "detected dubious ownership".
RUN git config --global --add safe.directory '*'

# ── add new agents below as additional FROM base AS <name> stages ────────────
