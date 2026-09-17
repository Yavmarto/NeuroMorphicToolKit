include $(dir $(abspath $(lastword $(MAKEFILE_LIST))))../common.mk

PORT ?= 8001
FRONTEND_DIR := frontend
BACKEND_DIR := .
BACKEND_CMD := uvicorn neurosim.app.main:app

.PHONY: help test

help:
	@printf '%s\n' \
		'Targets:' \
		'  make dev web  Build the Flutter web app and serve it from the backend.' \
		'  make dev-web   Same as above.' \
		'' \
		'Overrides:' \
		'  PORT=8001 HOST_IP=198.51.100.50 API_BASE_URL=http://198.51.100.50:8001 BIND_HOST=0.0.0.0'

test:
	pytest neurosim/tests -q
