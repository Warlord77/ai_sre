.PHONY: claude down

SHELL   := /bin/bash
WORKDIR := $(shell pwd)

-include .env
export

claude:
	@bash scripts/start.sh claude

down:
	@bash scripts/down.sh
