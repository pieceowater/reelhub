# Reelhub — see README.md for the full picture.
# Every target here is safe to run from a clean checkout.
#
# Everything actually runs on the server named in ansible/inventory.ini, not
# on this machine — `deploy` goes through Ansible (which also bootstraps
# Docker there the first time); the day-to-day targets below (up/down/ps/
# logs/pull/destroy) just SSH over and run `docker compose` in the checkout
# Ansible made on the server, since a raw SSH one-liner is simpler than
# reaching for Ansible for something this direct.

.DEFAULT_GOAL := help
ANSIBLE := ansible-playbook
SSH := ssh

# Extra flags forwarded to ansible-playbook — for password-based SSH:
#   make deploy ANSIBLE_ARGS="--ask-pass --ask-become-pass"
# (--ask-become-pass, the sudo password, is only actually used the first time,
# to install Docker — harmless to keep passing it after that.)
# Using an SSH key instead? Leave ANSIBLE_ARGS empty; the key lives in
# inventory.ini instead.
ANSIBLE_ARGS ?=

# Limit `make logs` to one service, e.g.  make logs S=radarr
S ?=

# Parsed straight out of inventory.ini so up/down/ps/logs/pull/destroy hit the
# same server `make deploy` does, without repeating the address everywhere.
# REMOTE_DIR matches deploy.yml's own default (reelhub_dir) — if you changed
# that there, change it here too.
REMOTE_HOST := $(shell awk '/^\[reelhub\]/{f=1;next} f && NF && $$1 !~ /^\[/{print $$1; exit}' ansible/inventory.ini 2>/dev/null)
REMOTE_USER := $(shell awk '/^\[reelhub\]/{f=1;next} f && NF && $$1 !~ /^\[/{for(i=1;i<=NF;i++) if ($$i ~ /^ansible_user=/) print substr($$i, index($$i,"=")+1); exit}' ansible/inventory.ini 2>/dev/null)
REMOTE_DIR := reelhub
REMOTE := $(SSH) $(REMOTE_USER)@$(REMOTE_HOST)

.PHONY: help deploy up down restart ps logs pull urls backup backup-list destroy check check-remote

help: ## Show this help
	@echo "Reelhub"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[1m%-10s\033[0m %s\n", $$1, $$2}'
	@echo ""
	@echo "  First run:"
	@echo "    cp ansible/vars.yml.example ansible/vars.yml && \$$EDITOR ansible/vars.yml"
	@echo "    cp ansible/inventory.ini.example ansible/inventory.ini && \$$EDITOR ansible/inventory.ini"
	@echo "    make deploy ANSIBLE_ARGS=\"--ask-pass --ask-become-pass\""

deploy: check ## Set up Docker (first run only) and the whole stack on the server
	@cd ansible && $(ANSIBLE) deploy.yml $(ANSIBLE_ARGS)

up: check-remote ## Start the containers on the server (no configuration)
	@$(REMOTE) 'cd $(REMOTE_DIR) && docker compose up -d'

down: check-remote ## Stop and remove the containers (settings and media are kept)
	@$(REMOTE) 'cd $(REMOTE_DIR) && docker compose down'

restart: down up ## Restart the whole stack

ps: check-remote ## Show what is running on the server
	@$(REMOTE) 'cd $(REMOTE_DIR) && docker compose ps'

logs: check-remote ## Tail logs for everything, or one service: make logs S=radarr
	@$(SSH) -t $(REMOTE_USER)@$(REMOTE_HOST) 'cd $(REMOTE_DIR) && docker compose logs -f --tail=100 $(S)'

pull: check-remote ## Pull the pinned images again and recreate the containers
	@$(REMOTE) 'cd $(REMOTE_DIR) && docker compose pull && docker compose up -d'

backup: check-remote ## Run the config/ backup right now, instead of waiting for the nightly timer
	@$(REMOTE) 'sudo systemctl start reelhub-backup.service && journalctl -u reelhub-backup.service -n 15 --no-pager'

backup-list: check-remote ## List config/ backup snapshots on the server
	@$(REMOTE) 'RESTIC_REPOSITORY=~/reelhub-backups RESTIC_PASSWORD_FILE=~/.reelhub/restic-password restic snapshots'

urls: check-remote ## Print every service's URL on the server
	@echo "  Jellyseerr   http://$(REMOTE_HOST):5055   request things here"
	@echo "  Jellyfin     http://$(REMOTE_HOST):8096   watch things here"
	@echo "  Prowlarr     http://$(REMOTE_HOST):9696   add your indexers here"
	@echo "  Radarr       http://$(REMOTE_HOST):7878"
	@echo "  Sonarr       http://$(REMOTE_HOST):8989"
	@echo "  qBittorrent  http://$(REMOTE_HOST):8080"
	@echo ""
	@echo "  Same addresses from any device on your network — Infuse, JellySee,"
	@echo "  a phone, another computer."

# Deliberately noisy and interactive: this throws away every service's settings,
# API keys and watch history ON THE SERVER. It does NOT touch data/ — your
# media survives.
destroy: check-remote ## Remove containers AND all service config on the server (asks first)
	@echo "This deletes config/ on $(REMOTE_HOST) — all six services go back to"
	@echo "first-boot state. Your media in data/ is NOT touched."
	@printf "Type 'yes' to continue: " && read ans && [ "$$ans" = "yes" ]
	@$(REMOTE) 'cd $(REMOTE_DIR) && docker compose down -v && rm -rf config'
	@echo "Removed. Run 'make deploy' to set everything up again."

# Guard rail: the most common first-run mistakes are forgetting to create
# vars.yml/inventory.ini, or not having Ansible itself yet — Docker is no
# longer this machine's problem, the playbook installs it on the server.
check:
	@test -f ansible/vars.yml || { \
		echo "ansible/vars.yml is missing."; \
		echo "Create it first:  cp ansible/vars.yml.example ansible/vars.yml"; \
		exit 1; }
	@test -f ansible/inventory.ini || { \
		echo "ansible/inventory.ini is missing."; \
		echo "Create it first:  cp ansible/inventory.ini.example ansible/inventory.ini"; \
		exit 1; }
	@command -v ansible-playbook >/dev/null || { \
		echo "ansible is not installed.  brew install ansible"; exit 1; }

# Same idea, for the targets that skip Ansible and SSH over directly.
check-remote: check
	@if [ -z "$(REMOTE_HOST)" ] || [ "$(REMOTE_HOST)" = "SERVER_IP" ]; then \
		echo "ansible/inventory.ini still has the placeholder SERVER_IP."; \
		echo "Edit it with your server's real address first."; exit 1; fi
