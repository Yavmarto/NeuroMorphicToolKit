PORT ?= 8005
BIND_HOST ?= 0.0.0.0
HOST_IP ?= $(shell python3 -c "import socket; s=socket.socket(socket.AF_INET, socket.SOCK_DGRAM); s.connect(('8.8.8.8', 80)); print(s.getsockname()[0]); s.close()" 2>/dev/null || echo 127.0.0.1)
API_BASE_URL ?= http://$(HOST_IP):$(PORT)
FRONTEND_DIR := frontend
BACKEND_DIR := neurohub
BACKEND_CMD := PYTHONPATH=. uvicorn app.main:app

.PHONY: help dev web dev-web

help:
	@printf '%s\n' \
		'Targets:' \
		'  make dev web  Build the Flutter web app and serve it from the backend.' \
		'  make dev-web   Same as above.' \
		'' \
		'Overrides:' \
		'  PORT=8005 HOST_IP=198.51.100.50 API_BASE_URL=http://198.51.100.50:8005 BIND_HOST=0.0.0.0'

dev web: dev-web
	@:

dev-web:
	@printf 'Building %s for %s\n' "$(FRONTEND_DIR)" "$(API_BASE_URL)"
	cd "$(FRONTEND_DIR)" && flutter pub get && flutter build web --release --dart-define=API_BASE_URL="$(API_BASE_URL)"
	@printf '\nServing on:\n  Local: http://localhost:%s\n  LAN:   http://%s:%s\n\n' "$(PORT)" "$(HOST_IP)" "$(PORT)"
	cd "$(BACKEND_DIR)" && $(BACKEND_CMD) --host "$(BIND_HOST)" --port "$(PORT)"
