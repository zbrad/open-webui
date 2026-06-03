
DOCKER_DIR  := deploy/docker
LOCAL_DIR   := deploy/local
SERVICE_DIR := deploy/service

ifneq ($(shell which docker-compose 2>/dev/null),)
    DOCKER_COMPOSE := docker-compose
else
    DOCKER_COMPOSE := docker compose
endif

# ── Docker targets ────────────────────────────────────────────────────────────

docker-up:
	cd $(DOCKER_DIR) && $(DOCKER_COMPOSE) up -d

docker-up-build:
	cd $(DOCKER_DIR) && $(DOCKER_COMPOSE) up -d --build

docker-start:
	cd $(DOCKER_DIR) && $(DOCKER_COMPOSE) start

docker-stop:
	cd $(DOCKER_DIR) && $(DOCKER_COMPOSE) stop

docker-remove:
	$(DOCKER_DIR)/docker-cleanup.sh

docker-update:
	$(DOCKER_DIR)/docker-update-models.sh
	@git pull
	cd $(DOCKER_DIR) && $(DOCKER_COMPOSE) down
	@docker stop open-webui || true
	cd $(DOCKER_DIR) && $(DOCKER_COMPOSE) up --build -d
	cd $(DOCKER_DIR) && $(DOCKER_COMPOSE) start

docker-launch:
	$(DOCKER_DIR)/docker-compose-launcher.sh

# ── Local (venv) targets ──────────────────────────────────────────────────────

local-setup:
	$(LOCAL_DIR)/setup.sh --mode local

local-setup-service:
	$(LOCAL_DIR)/setup.sh --mode service

local-start:
	$(LOCAL_DIR)/run-local.sh

local-dev:
	$(LOCAL_DIR)/dev.sh

# ── Service (systemd) targets ─────────────────────────────────────────────────

service-install:
	$(SERVICE_DIR)/deploy.sh

service-start:
	sudo systemctl start open-webui

service-stop:
	sudo systemctl stop open-webui

service-restart:
	sudo systemctl restart open-webui

service-status:
	systemctl status open-webui

service-logs:
	journalctl -u open-webui -f

# ── Aliases (backwards compat) ────────────────────────────────────────────────

install: docker-up
remove:  docker-remove
start:   docker-start
stop:    docker-stop

.PHONY: docker-up docker-up-build docker-start docker-stop docker-remove \
        docker-update docker-launch \
        local-setup local-setup-service local-start local-dev \
        service-install service-start service-stop service-restart \
        service-status service-logs \
        install remove start stop
