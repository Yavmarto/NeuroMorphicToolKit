# common.mk — included by all module Makefiles
# Provides shared HOST_IP detection, BIND_HOST default, API_BASE_URL, and dev-web target.
# Include from a module Makefile with:
#   include $(dir $(abspath $(lastword $(MAKEFILE_LIST))))../common.mk

BIND_HOST ?= 0.0.0.0
HOST_IP ?= $(shell python3 -c "import socket; s=socket.socket(socket.AF_INET, socket.SOCK_DGRAM); s.connect(('8.8.8.8', 80)); print(s.getsockname()[0]); s.close()" 2>/dev/null || echo 127.0.0.1)
API_BASE_URL ?= http://$(HOST_IP):$(PORT)

FRONTEND_DIR ?= frontend

.PHONY: dev web dev-web

dev web: dev-web
	@:

dev-web:
	@printf 'Building %s for %s\n' "$(FRONTEND_DIR)" "$(API_BASE_URL)"
	cd "$(FRONTEND_DIR)" && flutter pub get && flutter build web --release --dart-define=API_BASE_URL="$(API_BASE_URL)"
	@printf '\nServing on:\n  Local: http://localhost:%s\n  LAN:   http://%s:%s\n\n' "$(PORT)" "$(HOST_IP)" "$(PORT)"
	cd "$(BACKEND_DIR)" && $(BACKEND_CMD) --host "$(BIND_HOST)" --port "$(PORT)"
