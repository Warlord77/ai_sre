.PHONY: hermes claude down

SHELL   := /bin/bash
WORKDIR := $(shell pwd)

-include .env
export

hermes:
	@bash scripts/start.sh hermes

claude:
	@bash scripts/start.sh claude

down:
	docker rmi \
		$$(docker images --format 'agent-box-hermes:{{.Tag}}' agent-box-hermes) \
		$$(docker images --format 'agent-box-claude:{{.Tag}}' agent-box-claude) \
		2>/dev/null || true
