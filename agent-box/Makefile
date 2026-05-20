.PHONY: help build test hermes claude down

SHELL   := /bin/bash
IMAGE   := agent-box:latest
WORKDIR := $(shell pwd)

-include .env
export

build:
	docker build -t $(IMAGE) -f .devcontainer/Dockerfile .devcontainer/

test:
	docker run --rm \
		--cap-drop=ALL \
		--security-opt=no-new-privileges \
		-v $(WORKDIR):/workspace \
		$(IMAGE) bash /workspace/scripts/check.sh

hermes:
	@CONTAINER_ID=$$(devcontainer up --workspace-folder . 2>/dev/null | grep '^{' | jq -r '.containerId') && \
	docker exec "$$CONTAINER_ID" bash -c 'mkdir -p ~/.hermes && printf "DEEPSEEK_API_KEY=$(DEEPSEEK_API_KEY)\n" > ~/.hermes/.env && hermes config set model.provider deepseek 2>/dev/null && hermes config set model.base_url https://api.deepseek.com/v1 2>/dev/null && hermes config set model.default deepseek-chat 2>/dev/null' && \
	docker exec "$$CONTAINER_ID" bash -c 'echo "hermes -m deepseek-v4-pro chat" > /tmp/.autorun' && \
	HEX=$$(printf '%s' "$$CONTAINER_ID" | xxd -p | tr -d '\n') && \
	code --new-window --folder-uri "vscode-remote://attached-container+$$HEX/workspace" && \
	osascript \
	  -e 'delay 1' \
	  -e 'tell application "Visual Studio Code" to activate' \
	  -e 'tell application "System Events" to key code 50 using {control down}'

claude:
	@CONTAINER_ID=$$(devcontainer up --workspace-folder . 2>/dev/null | grep '^{' | jq -r '.containerId') && \
	docker exec "$$CONTAINER_ID" bash -c 'echo "claude auth login" > /tmp/.autorun' && \
	HEX=$$(printf '%s' "$$CONTAINER_ID" | xxd -p | tr -d '\n') && \
	code --new-window --folder-uri "vscode-remote://attached-container+$$HEX/workspace" && \
	osascript \
	  -e 'delay 1' \
	  -e 'tell application "Visual Studio Code" to activate' \
	  -e 'tell application "System Events" to key code 50 using {control down}'

down:
	docker rmi $(IMAGE)
