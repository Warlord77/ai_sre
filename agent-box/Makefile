.PHONY: build build-base build-hermes build-claude test hermes claude down

SHELL        := /bin/bash
IMAGE_BASE   := agent-box-base:latest
IMAGE_HERMES := agent-box-hermes:latest
IMAGE_CLAUDE := agent-box-claude:latest
IMAGE        := agent-box:latest
WORKDIR      := $(shell pwd)

-include .env
export

build-base:
	docker build --target base -t $(IMAGE_BASE) -f .devcontainer/Dockerfile .devcontainer/

build-hermes: build-base
	docker build -t $(IMAGE_HERMES) -f .devcontainer/Dockerfile.hermes .devcontainer/

build-claude: build-base
	docker build -t $(IMAGE_CLAUDE) -f .devcontainer/Dockerfile.claude .devcontainer/

build: build-base
	docker build --target agent-box -t $(IMAGE) -f .devcontainer/Dockerfile .devcontainer/

test:
	docker run --rm \
		--cap-drop=ALL \
		--security-opt=no-new-privileges \
		-v $(WORKDIR):/workspace \
		$(IMAGE) bash /workspace/scripts/check.sh

hermes:
	@bash scripts/start-hermes.sh

claude:
	@bash scripts/start-claude.sh

down:
	docker rmi $(IMAGE) $(IMAGE_BASE) $(IMAGE_HERMES) $(IMAGE_CLAUDE) 2>/dev/null || true
