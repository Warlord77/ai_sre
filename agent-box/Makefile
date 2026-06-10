.PHONY: claude claude-headless down demo-up demo-run demo-verify demo-down diagram

SHELL    := /bin/bash
WORKDIR  := $(shell pwd)
DEMO_DIR := $(WORKDIR)/.demo

-include .env
export

claude:
	@bash scripts/start.sh claude

# Non-interactive Claude inside agent-box, runs from the CURRENT directory
# (so the agent operates on the caller's workspace, not agent-box).
# Forward args via ARGS, e.g.:
#   make claude-headless ARGS='--print --output-format stream-json --model claude-opus-4-7 --dangerously-skip-permissions "Fix the typo in README.md"'
# For ralph-style loops, call scripts/headless.sh directly from your target
# repo's loop script -- see scripts/headless.sh for examples.
claude-headless:
	@bash $(WORKDIR)/scripts/headless.sh $(ARGS)

down:
	@bash scripts/down.sh

# Demo: stand up a throwaway target repo (issues queue + PROMPT.md) for a ralph
# run, then tear it down. Lives in .demo/ (gitignored); the agent's commits land
# there, never in ai-bites. Override with DEMO_DIR=/tmp/whatever if you prefer.
demo-up:
	@bash scripts/demo-up.sh "$(DEMO_DIR)"

# Run the ralph loop against the demo repo. Handles the cd for you, so no long
# paths. Override the iteration cap with: make demo-run N=10
N ?= 6
AGENT_IMAGE := agent-box-claude
demo-run:
	@test -d "$(DEMO_DIR)" || { echo "no demo repo yet -- run 'make demo-up' first"; exit 1; }
	@cd "$(DEMO_DIR)" && "$(WORKDIR)/scripts/ralph.sh" --max $(N)

# Independently verify the agent's work -- run the project's own tests + typecheck
# in the box. Don't just trust the agent's "tests pass" summary; this is the proof.
demo-verify:
	@docker run --rm -v "$(DEMO_DIR):/workspace" -w /workspace --entrypoint bash $(AGENT_IMAGE):latest -lc \
		'npm test && npm run typecheck && echo "VERIFIED: tests + typecheck pass"'

demo-down:
	@rm -rf "$(DEMO_DIR)" && echo "removed $(DEMO_DIR)"

# Re-render the architecture diagram (dark + light PNGs) from docs/architecture.drawio
diagram:
	@bash docs/render-diagram.sh
