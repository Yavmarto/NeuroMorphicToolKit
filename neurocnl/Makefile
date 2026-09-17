include $(dir $(abspath $(lastword $(MAKEFILE_LIST))))../common.mk

PORT ?= 8000
FRONTEND_DIR := frontend
BACKEND_DIR := .
BACKEND_CMD := uvicorn backend.app.main:app --reload

.PHONY: help backend docker

help:
	@printf '%s\n' \
		'Targets:' \
		'  make docker    Rebuild and start the Docker Compose stack.' \
		'  make dev web  Build the Flutter web app and serve it from the backend.' \
		'  make dev-web   Same as above.' \
		'  make backend   Start only the backend (with --reload for live code changes).' \
		'' \
		'Overrides:' \
		'  PORT=8000 HOST_IP=198.51.100.50 API_BASE_URL=http://198.51.100.50:8000 BIND_HOST=0.0.0.0'

backend:
	@printf 'Starting backend on %s:%s (--reload active)\n' "$(BIND_HOST)" "$(PORT)"
	cd "$(BACKEND_DIR)" && $(BACKEND_CMD) --host "$(BIND_HOST)" --port "$(PORT)"

docker:
	docker compose up --build
