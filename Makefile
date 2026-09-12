# Reelhub — see README.md for the full picture.
# Every target here is safe to run from a clean checkout.

.DEFAULT_GOAL := help
COMPOSE := docker compose
ANSIBLE := ansible-playbook

# Extra flags forwarded to ansible-playbook, e.g.
#   make deploy ANSIBLE_ARGS=--ask-vault-pass
ANSIBLE_ARGS ?=

# Limit `make logs` to one service, e.g.  make logs S=radarr
S ?=

.PHONY: help deploy up down restart ps logs pull urls destroy check

help: ## Show this help
	@echo "Reelhub"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[1m%-10s\033[0m %s\n", $$1, $$2}'
	@echo ""
	@echo "  First run:  cp ansible/vars.yml.example ansible/vars.yml && make deploy"

deploy: check ## Start the stack and run the full configuration playbook
	@cd ansible && $(ANSIBLE) deploy.yml $(ANSIBLE_ARGS)

up: ## Start the containers (no configuration)
	@$(COMPOSE) up -d

down: ## Stop and remove the containers (settings and media are kept)
	@$(COMPOSE) down

restart: down up ## Restart the whole stack

ps: ## Show what is running
	@$(COMPOSE) ps

logs: ## Tail logs for everything, or one service: make logs S=radarr
	@$(COMPOSE) logs -f --tail=100 $(S)

pull: ## Pull newer images and recreate the containers
	@$(COMPOSE) pull
	@$(COMPOSE) up -d

# LAN_IP tries macOS's usual interfaces first, then falls back to a Linux-style
# lookup; if neither finds one, prints a placeholder instead of failing.
LAN_IP := $(shell ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || hostname -I 2>/dev/null | awk '{print $$1}' || echo "<this-machine's-IP>")

urls: ## Print the service URLs (+ the LAN address for Infuse/other devices)
	@echo "  Jellyseerr   http://localhost:5055   request things here"
	@echo "  Jellyfin     http://localhost:8096   watch things here"
	@echo "  Prowlarr     http://localhost:9696   add your indexers here"
	@echo "  Radarr       http://localhost:7878"
	@echo "  Sonarr       http://localhost:8989"
	@echo "  qBittorrent  http://localhost:8080"
	@echo ""
	@echo "  From another device on your network (Infuse, a phone, another"
	@echo "  computer), Jellyfin is at: $(LAN_IP):8096"

# Deliberately noisy and interactive: this throws away every service's settings,
# API keys and watch history. It does NOT touch data/ — your media survives.
destroy: ## Remove containers AND all service config (asks first)
	@echo "This deletes config/ — all six services go back to first-boot state."
	@echo "Your media in data/ is NOT touched."
	@printf "Type 'yes' to continue: " && read ans && [ "$$ans" = "yes" ]
	@$(COMPOSE) down -v
	@rm -rf config
	@echo "Removed. Run 'make deploy' to set everything up again."

# Guard rail: the most common first-run mistake is forgetting to create vars.yml.
check:
	@test -f ansible/vars.yml || { \
		echo "ansible/vars.yml is missing."; \
		echo "Create it first:  cp ansible/vars.yml.example ansible/vars.yml"; \
		exit 1; }
	@command -v ansible-playbook >/dev/null || { \
		echo "ansible is not installed.  brew install ansible"; exit 1; }
	@docker info >/dev/null 2>&1 || { \
		echo "Docker is not running. Start Docker Desktop and try again."; exit 1; }
