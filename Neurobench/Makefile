include $(dir $(abspath $(lastword $(MAKEFILE_LIST))))../common.mk

PORT ?= 8003
FRONTEND_DIR := frontend
BACKEND_DIR := neurobench
BACKEND_CMD := poetry run uvicorn app.main:app

.PHONY: help

help:
	@printf '%s\n' \
		'Targets:' \
		'  make dev web  Build the Flutter web app and serve it from the backend.' \
		'  make dev-web   Same as above.' \
		'' \
		'Overrides:' \
		'  PORT=8003 HOST_IP=198.51.100.50 API_BASE_URL=http://198.51.100.50:8003 BIND_HOST=0.0.0.0'
