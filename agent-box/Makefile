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
	@bash scripts/down.sh
