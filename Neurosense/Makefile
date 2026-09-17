include $(dir $(abspath $(lastword $(MAKEFILE_LIST))))../common.mk

PORT ?= 8004
FRONTEND_DIR := frontend
BACKEND_DIR := neurosense
BACKEND_CMD := uvicorn app.main:app

.PHONY: help

help:
	@printf '%s\n' \
		'Targets:' \
		'  make dev web  Build the Flutter web app and serve it from the backend.' \
		'  make dev-web   Same as above.' \
		'' \
		'Overrides:' \
		'  PORT=8004 HOST_IP=192.168.1.50 API_BASE_URL=http://192.168.1.50:8004 BIND_HOST=0.0.0.0'
