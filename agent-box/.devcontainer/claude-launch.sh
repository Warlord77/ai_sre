#!/usr/bin/env bash
# Invoked once per container start via the autorun trigger in
# /home/agent/.bashrc. Strips empty auth env vars and execs `claude`.
#
# devcontainer's containerEnv substitutes ${localEnv:VAR} to "" when the host
# var is unset. Claude treats an empty ANTHROPIC_API_KEY as "set" and prefers
# it over CLAUDE_CODE_OAUTH_TOKEN at lower precedence. Unset empties first.
#
# Onboarding (theme + syntax + /login + trust dialog) is skipped because the
# Dockerfile pre-populates ~/.claude.json with hasCompletedOnboarding and a
# trusted /workspace entry. With those markers in place, `claude` lands at
# its REPL using CLAUDE_CODE_OAUTH_TOKEN for auth.

set -u

for v in CLAUDE_CODE_OAUTH_TOKEN ANTHROPIC_API_KEY; do
  [ -z "${!v:-}" ] && unset "$v"
done

if [[ -t 1 ]]; then
  BOLD='\033[1m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; NC='\033[0m'
else
  BOLD=''; GREEN=''; YELLOW=''; NC=''
fi

if [ -n "${CLAUDE_CODE_OAUTH_TOKEN:-}" ]; then
  echo -e "  ${GREEN}✓${NC}  claude auth: ${BOLD}CLAUDE_CODE_OAUTH_TOKEN${NC}"
elif [ -n "${ANTHROPIC_API_KEY:-}" ]; then
  echo -e "  ${GREEN}✓${NC}  claude auth: ${BOLD}ANTHROPIC_API_KEY${NC}"
else
  echo -e "  ${YELLOW}!${NC}  no claude auth env var set -- claude will prompt /login"
fi

exec claude "$@"
