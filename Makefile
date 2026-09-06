
ifneq ($(shell which docker-compose 2>/dev/null),)
    DOCKER_COMPOSE := docker-compose
else
    DOCKER_COMPOSE := docker compose
endif

install:
	$(DOCKER_COMPOSE) up -d

remove:
	@chmod +x confirm_remove.sh
	@./confirm_remove.sh

start:
	$(DOCKER_COMPOSE) start
startAndBuild: 
	$(DOCKER_COMPOSE) up -d --build

stop:
	$(DOCKER_COMPOSE) stop

update:
	# Calls the LLM update script
	chmod +x update_ollama_models.sh
	@./update_ollama_models.sh
	@git pull
	$(DOCKER_COMPOSE) down
	# Make sure the ollama-webui container is stopped before rebuilding
	@docker stop open-webui || true
	$(DOCKER_COMPOSE) up --build -d
	$(DOCKER_COMPOSE) start

# ── Local (venv, no Docker) targets ───────────────────────────────────────────

local-setup:
	deploy/local/setup.sh --mode local

local-setup-service:
	deploy/local/setup.sh --mode service

local-start:
	deploy/local/run-local.sh

local-dev:
	deploy/local/dev.sh

# ── systemd --user service targets ────────────────────────────────────────────

service-install:
	deploy/service/deploy.sh

service-start:
	systemctl --user start open-webui

service-stop:
	systemctl --user stop open-webui

service-restart:
	systemctl --user restart open-webui

service-status:
	systemctl --user status open-webui

service-logs:
	journalctl --user -u open-webui -f

