.PHONY: release help dev dev-a dev-i dev-web dev-native clean-all bump-version ci notices notices-check suite_api_dev check-devices docker docker-a docker-i docker-all docker-ex docker-ex-deploy docker-ex-m docker-ex-l docker-ex-a docker-ex-i docker-ex-down docker-ex-all docker-ex-all-m docker-ex-all-a docker-ex-all-i secrets-init macos-signing-check build-macos-dmg-signed webtop-build webtop-up webtop-down webtop

# OS detection for Flutter device targeting
OS := $(shell uname)
ifeq ($(OS), Darwin)
  FLUTTER_DEVICE = macos
else ifeq ($(OS), Linux)
  FLUTTER_DEVICE = linux
else
  FLUTTER_DEVICE = windows
endif

# Resolve a concrete Android device id for flutter run. Prefer wireless ADB
# targets when one is connected, and allow callers to override explicitly.
ANDROID_DEVICE ?= $(shell flutter devices --machine 2>/dev/null | python3 -c 'import json,sys; devices=json.load(sys.stdin); android_ids=[d["id"] for d in devices if d.get("isSupported") and str(d.get("targetPlatform", "")).startswith("android")]; wireless_ids=[device_id for device_id in android_ids if ":" in device_id]; print((wireless_ids or android_ids or ["android"])[0])' 2>/dev/null || printf 'android')

# Resolve a concrete iOS device id for flutter run.
IOS_DEVICE ?= $(shell flutter devices --machine 2>/dev/null | python3 -c 'import json,sys; devices=json.load(sys.stdin); ios_ids=[d["id"] for d in devices if d.get("isSupported") and str(d.get("targetPlatform", "")).startswith("ios")]; print((ios_ids or ["ios"])[0])' 2>/dev/null || printf 'ios')


help:
	@echo "NeuroMorphicToolkit (NMTK) Build System"
	@echo ""
	@echo "Usage:"
	@echo "  make dev                      - Run suite_api and the native launcher"
	@echo "  make dev-web                  - Run suite_api and the launcher in Chrome"
	@echo "  make dev-a                    - Run suite_api and the launcher on the resolved Android device"
	@echo "                                  Override with ANDROID_DEVICE=<flutter-device-id> when needed"
	@echo "  make dev-i                    - Run suite_api and the launcher on iOS"
	@echo "  make dev-native               - Run the native launcher control API and Flutter app"
	@echo "  make docker                   - Run backend in Docker and native launcher on host"
	@echo "  make docker-a                 - Run backend in Docker and launcher on Android"
	@echo "  make docker-i                 - Run backend in Docker and launcher on iOS"
	@echo "  make docker-all               - Run full stack in Docker and native launcher (alias for docker)"
	@echo "  make docker-ex REMOTE_HOST=user@ip - Deploy full backend stack to remote + run Flutter macOS dev app (alias for docker-ex-all)"
	@echo "  make docker-ex-all REMOTE_HOST=user@ip - Deploy full backend stack to remote + run Flutter macOS dev app"
	@echo "  make docker-ex-m REMOTE_HOST=user@ip - Same as docker-ex (alias)"
	@echo "  make docker-ex-l REMOTE_HOST=user@ip - Deploy to remote and run Flutter Linux desktop app"
	@echo "  make docker-ex-a REMOTE_HOST=user@ip - Deploy to remote and run frontend on Android"
	@echo "  make docker-ex-i REMOTE_HOST=user@ip - Deploy to remote and run frontend on iOS"
	@echo "  make docker-ex-all-m REMOTE_HOST=user@ip - Same as docker-ex-all (alias)"
	@echo "  make docker-ex-all-a REMOTE_HOST=user@ip - Deploy full stack (all workers) to remote and run frontend on Android"
	@echo "  make docker-ex-all-i REMOTE_HOST=user@ip - Deploy full stack (all workers) to remote and run frontend on iOS"
	@echo "  make docker-ex-down REMOTE_HOST=user@ip - Stop and remove remote Docker containers"
	@echo "  make suite_api_dev            - Start unified suite_api backend on port 9000 (with reload)"
	@echo "  make release VERSION=x.y.z    - Run the full release automation pipeline"
	@echo "  make bump-version VERSION=x.y.z - Synchronize all versions across the monorepo"
	@echo "  make clean-all                - Deep clean the entire monorepo"
	@echo "  make notices                  - Regenerate THIRD_PARTY_NOTICES.md from manifests"
	@echo "  make notices-check            - Fail if THIRD_PARTY_NOTICES.md is stale"
	@echo "  make macos-signing-check      - Report macOS signing/notarization env readiness"
	@echo "  make build-macos-dmg-signed   - Build a signed/notarized macOS DMG when secrets are set"
	@echo "  make webtop                   - Build and start NMTK desktop in browser (webtop/kiosk)"
	@echo "  make webtop-build             - Build the webtop Docker image"
	@echo "  make webtop-up                - Start the webtop container"
	@echo "  make webtop-down              - Stop the webtop container"
	@echo ""

dev:
	@./scripts/run_dev.sh --flutter-device "$(FLUTTER_DEVICE)"

dev-a:
	@$(MAKE) check-devices
	@echo "==> Using Android device: $(ANDROID_DEVICE)"
	@./scripts/run_dev.sh --flutter-device "$(ANDROID_DEVICE)"

dev-i:
	@$(MAKE) check-devices
	@echo "==> Using iOS device: $(IOS_DEVICE)"
	@./scripts/run_dev.sh --flutter-device "$(IOS_DEVICE)"

dev-native:
	@chmod +x scripts/run_dev.sh
	@./scripts/run_dev.sh --flutter-device "$(FLUTTER_DEVICE)"

dev-web:
	@./scripts/run_dev.sh --flutter-device chrome

docker:
	@./scripts/run_dev.sh --docker --flutter-device "$(FLUTTER_DEVICE)"

docker-a:
	@$(MAKE) check-devices
	@echo "==> Using Android device: $(ANDROID_DEVICE)"
	@./scripts/run_dev.sh --docker --flutter-device "$(ANDROID_DEVICE)"

docker-i:
	@$(MAKE) check-devices
	@echo "==> Using iOS device: $(IOS_DEVICE)"
	@./scripts/run_dev.sh --docker --flutter-device "$(IOS_DEVICE)"

docker-all:
	@./scripts/run_dev.sh --docker --flutter-device "$(FLUTTER_DEVICE)"

# Deployment variables (can be overridden on command line)
REMOTE_HOST ?=
DEPLOY_DIR ?= ~/nmtk-deploy
LAUNCHER_CONTROL_PORT ?= 8091
# Set DOCKER_EX_PRUNE=1 to run `docker builder prune` before deploy (slower; rarely needed).
DOCKER_EX_PRUNE ?=
# Set DOCKER_EX_RSYNC_VERBOSE=1 to list every rsync'd file (debug only).
DOCKER_EX_RSYNC_VERBOSE ?=
# SSH ControlMaster: reuses a single TCP connection across all ssh/rsync calls in one make run.
# The %h/%p/%r tokens are expanded by ssh itself, so this is safe when REMOTE_HOST is empty.
SSH_OPTS ?= -o ControlMaster=auto -o ControlPath=/tmp/nmtk-ssh-%h-%p-%r -o ControlPersist=60s

## Initialise required secrets on the remote host if they are missing.
## Safe to re-run — only fills gaps, never overwrites existing values.
secrets-init:
	@if [ -z "$(REMOTE_HOST)" ]; then \
		echo "Error: REMOTE_HOST is not set."; exit 1; \
	fi
	@echo "==> Initialising required secrets on $(REMOTE_HOST)..."
	ssh $(SSH_OPTS) $(REMOTE_HOST) '\
	  touch $(DEPLOY_DIR)/.env; \
	  grep -q GRAFANA_ADMIN_PASSWORD $(DEPLOY_DIR)/.env || \
	    echo "GRAFANA_ADMIN_PASSWORD=$$(openssl rand -base64 32)" >> $(DEPLOY_DIR)/.env; \
	  echo "secrets-init: OK (GRAFANA_ADMIN_PASSWORD present)"'

## Sync repo to remote, rebuild images when sources change, start full backend stack.
.PHONY: docker-ex-deploy
docker-ex-deploy:
	@if [ -z "$(REMOTE_HOST)" ]; then \
		echo "Error: REMOTE_HOST is not set. Example: make docker-ex-all REMOTE_HOST=user@192.168.1.50"; \
		exit 1; \
	fi
	@echo "==> Syncing backend source to $(REMOTE_HOST):$(DEPLOY_DIR) (rsync, incremental)..."
	ssh $(SSH_OPTS) $(REMOTE_HOST) "mkdir -p $(DEPLOY_DIR)"
	rsync -a --delete -v -e "ssh $(SSH_OPTS)" \
		$(if $(DOCKER_EX_RSYNC_VERBOSE),-v,) \
		--exclude '.git' --exclude '.env' --exclude 'venv' --exclude '.venv' \
		--exclude '__pycache__' --exclude 'node_modules' \
		--exclude 'build/' --exclude '*.dill' --exclude '*.dill.track.dill' \
		--exclude '.cache' --exclude '.mypy_cache' --exclude '.pytest_cache' \
		--exclude '.ruff_cache' --exclude 'logs/' --exclude 'NMTK_SIDE/' \
		--exclude '.hypothesis' --exclude '.kiro' \
		--exclude '.understand-anything' --exclude '.sisyphus' \
		--exclude '.impeccable' --exclude '.tmp_manual_ui' \
		--exclude '.swarm/' --exclude '.opencode/' --exclude '.cursor/' \
		--exclude 'docs/' --exclude 'issues/' --exclude 'issues-archive/' \
		--exclude 'ai_safe/' --exclude 'Neuro-Dream-Hand/' --exclude 'paper/' \
		--exclude 'neurocnl/frontend/' --exclude 'Neurohub/frontend/' \
		--exclude 'Neurochip/frontend/' --exclude 'Neurobench/frontend/' \
		--exclude 'Neurosim/frontend/' --exclude 'nmtk_ui_core/' \
		--exclude 'nmtk/neuro_toolkit/lib/' --exclude 'nmtk/neuro_toolkit/build/' \
		--exclude 'nmtk/neuro_toolkit/.dart_tool/' --exclude 'nmtk/neuro_toolkit/android/' \
		--exclude 'nmtk/neuro_toolkit/ios/' --exclude 'nmtk/neuro_toolkit/macos/' \
		--exclude 'nmtk/neuro_toolkit/linux/' --exclude 'nmtk/neuro_toolkit/windows/' \
		--exclude 'nmtk/neuro_toolkit/web/' --exclude 'nmtk/packages/' \
		. $(REMOTE_HOST):$(DEPLOY_DIR)/
	@echo "==> Evicting any native process on port $(LAUNCHER_CONTROL_PORT) on $(REMOTE_HOST)..."
	ssh $(SSH_OPTS) $(REMOTE_HOST) "fuser -k $(LAUNCHER_CONTROL_PORT)/tcp 2>/dev/null || true"
	@if [ -n "$(DOCKER_EX_PRUNE)" ]; then \
		echo "==> Pruning stale build cache on $(REMOTE_HOST) (keeping 20GB most-recent)..."; \
		ssh $(SSH_OPTS) $(REMOTE_HOST) "docker builder prune -f --keep-storage=20GB"; \
	fi
	@echo "==> Building and starting full backend stack on $(REMOTE_HOST) (--build picks up source changes)..."
	ssh $(SSH_OPTS) $(REMOTE_HOST) "cd $(DEPLOY_DIR) && DOCKER_BUILDKIT=1 COMPOSE_DOCKER_CLI_BUILD=1 LAUNCHER_CONTROL_PORT=$(LAUNCHER_CONTROL_PORT) JUPYTER_PUBLIC_URL=http://$$(echo $(REMOTE_HOST) | cut -d@ -f2):8008/lab docker compose up --build -d --wait --remove-orphans"
	@echo "==> Full backend ready. Suite API at http://$$(echo $(REMOTE_HOST) | cut -d@ -f2):9000"

docker-ex-all: secrets-init docker-ex-deploy
	@./scripts/run_dev.sh --flutter-device macos --remote-host "$$(echo $(REMOTE_HOST) | cut -d@ -f2)"

docker-ex: docker-ex-all

docker-ex-m: docker-ex

docker-ex-l: secrets-init docker-ex-deploy
	@./scripts/run_dev.sh --flutter-device linux --remote-host "$$(echo $(REMOTE_HOST) | cut -d@ -f2)"

.PHONY: deploy-prod
deploy-prod: secrets-init
	@if [ -z "$(REMOTE_HOST)" ]; then \
		echo "Error: REMOTE_HOST is not set. Example: make deploy-prod REMOTE_HOST=user@192.168.1.50"; \
		exit 1; \
	fi
	@echo "==> Syncing compose files to $(REMOTE_HOST):$(DEPLOY_DIR)..."
	ssh $(SSH_OPTS) $(REMOTE_HOST) "mkdir -p $(DEPLOY_DIR)"
	rsync -a -v -e "ssh $(SSH_OPTS)" docker-compose.yml docker-compose.prod.yml $(REMOTE_HOST):$(DEPLOY_DIR)/
	@echo "==> Evicting any native process on port $(LAUNCHER_CONTROL_PORT) on $(REMOTE_HOST)..."
	ssh $(SSH_OPTS) $(REMOTE_HOST) "fuser -k $(LAUNCHER_CONTROL_PORT)/tcp 2>/dev/null || true"
	@echo "==> Pulling and starting full backend stack on $(REMOTE_HOST)..."
	ssh $(SSH_OPTS) $(REMOTE_HOST) "cd $(DEPLOY_DIR) && LAUNCHER_CONTROL_PORT=$(LAUNCHER_CONTROL_PORT) JUPYTER_PUBLIC_URL=http://$$(echo $(REMOTE_HOST) | cut -d@ -f2):8008/lab docker compose -f docker-compose.yml -f docker-compose.prod.yml pull && LAUNCHER_CONTROL_PORT=$(LAUNCHER_CONTROL_PORT) JUPYTER_PUBLIC_URL=http://$$(echo $(REMOTE_HOST) | cut -d@ -f2):8008/lab docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d --wait --remove-orphans"
	@echo "==> Production backend ready."

.PHONY: dev-sync
dev-sync:
	@if [ -z "$(REMOTE_HOST)" ]; then \
		echo "Error: REMOTE_HOST is not set. Example: make dev-sync REMOTE_HOST=user@192.168.1.50"; \
		exit 1; \
	fi
	@echo "==> Syncing backend source to $(REMOTE_HOST):$(DEPLOY_DIR) (rsync, incremental)..."
	ssh $(SSH_OPTS) $(REMOTE_HOST) "mkdir -p $(DEPLOY_DIR)"
	rsync -a --delete -v -e "ssh $(SSH_OPTS)" \
		$(if $(DOCKER_EX_RSYNC_VERBOSE),-v,) \
		--exclude '.git' --exclude '.env' --exclude 'venv' --exclude '.venv' \
		--exclude '__pycache__' --exclude 'node_modules' \
		--exclude 'build/' --exclude '*.dill' --exclude '*.dill.track.dill' \
		--exclude '.cache' --exclude '.mypy_cache' --exclude '.pytest_cache' \
		--exclude '.ruff_cache' --exclude 'logs/' --exclude 'NMTK_SIDE/' \
		--exclude '.hypothesis' --exclude '.kiro' \
		--exclude '.understand-anything' --exclude '.sisyphus' \
		--exclude '.impeccable' --exclude '.tmp_manual_ui' \
		--exclude '.swarm/' --exclude '.opencode/' --exclude '.cursor/' \
		--exclude 'docs/' --exclude 'issues/' --exclude 'issues-archive/' \
		--exclude 'ai_safe/' --exclude 'Neuro-Dream-Hand/' --exclude 'paper/' \
		--exclude 'neurocnl/frontend/' --exclude 'Neurohub/frontend/' \
		--exclude 'Neurochip/frontend/' --exclude 'Neurobench/frontend/' \
		--exclude 'Neurosim/frontend/' --exclude 'nmtk_ui_core/' \
		--exclude 'nmtk/neuro_toolkit/lib/' --exclude 'nmtk/neuro_toolkit/build/' \
		--exclude 'nmtk/neuro_toolkit/.dart_tool/' --exclude 'nmtk/neuro_toolkit/android/' \
		--exclude 'nmtk/neuro_toolkit/ios/' --exclude 'nmtk/neuro_toolkit/macos/' \
		--exclude 'nmtk/neuro_toolkit/linux/' --exclude 'nmtk/neuro_toolkit/windows/' \
		--exclude 'nmtk/neuro_toolkit/web/' --exclude 'nmtk/packages/' \
		. $(REMOTE_HOST):$(DEPLOY_DIR)/
	@echo "==> Restarting container processes if necessary (live-reload handles python changes automatically)..."
	ssh $(SSH_OPTS) $(REMOTE_HOST) "cd $(DEPLOY_DIR) && LAUNCHER_CONTROL_PORT=$(LAUNCHER_CONTROL_PORT) JUPYTER_PUBLIC_URL=http://$$(echo $(REMOTE_HOST) | cut -d@ -f2):8008/lab docker compose -f docker-compose.yml -f docker-compose.dev.yml up -d"
	@echo "==> Dev backend synced."

docker-ex-a: secrets-init docker-ex-deploy
	@$(MAKE) check-devices
	@echo "==> Using Android device: $(ANDROID_DEVICE)"
	@./scripts/run_dev.sh --flutter-device "$(ANDROID_DEVICE)" --remote-host "$$(echo $(REMOTE_HOST) | cut -d@ -f2)"

docker-ex-i: secrets-init docker-ex-deploy
	@$(MAKE) check-devices
	@echo "==> Using iOS device: $(IOS_DEVICE)"
	@./scripts/run_dev.sh --flutter-device "$(IOS_DEVICE)" --remote-host "$$(echo $(REMOTE_HOST) | cut -d@ -f2)"

docker-ex-all-m: docker-ex-all

docker-ex-all-a: secrets-init docker-ex-deploy
	@$(MAKE) check-devices
	@echo "==> Using Android device: $(ANDROID_DEVICE)"
	@./scripts/run_dev.sh --flutter-device "$(ANDROID_DEVICE)" --remote-host "$$(echo $(REMOTE_HOST) | cut -d@ -f2)"

docker-ex-all-i: secrets-init docker-ex-deploy
	@$(MAKE) check-devices
	@echo "==> Using iOS device: $(IOS_DEVICE)"
	@./scripts/run_dev.sh --flutter-device "$(IOS_DEVICE)" --remote-host "$$(echo $(REMOTE_HOST) | cut -d@ -f2)"

docker-ex-down:
	@if [ -z "$(REMOTE_HOST)" ]; then \
		echo "Error: REMOTE_HOST is not set. Example: make docker-ex-down REMOTE_HOST=user@192.168.1.50"; \
		exit 1; \
	fi
	@echo "==> Stopping Docker containers on $(REMOTE_HOST)..."
	ssh $(SSH_OPTS) $(REMOTE_HOST) "cd $(DEPLOY_DIR) && docker compose down"

suite_api_dev:
	uvicorn suite_api.main:app --host 0.0.0.0 --port 9000 --reload

ci:
	@chmod +x scripts/run_ci_local.sh
	@./scripts/run_ci_local.sh --all
	@$(MAKE) notices-check

notices:
	@python3 scripts/generate_third_party_notices.py

notices-check:
	@python3 scripts/generate_third_party_notices.py --check

clean-all:
	@chmod +x scripts/deep_clean.sh
	@./scripts/deep_clean.sh

release:
	@if [ -z "$(VERSION)" ]; then \
		echo "Error: VERSION is not set. Use 'make release VERSION=x.y.z'"; \
		exit 1; \
	fi
	@bash scripts/release.sh $(VERSION)

bump-version:
	@if [ -z "$(VERSION)" ]; then \
		echo "Error: VERSION is not set. Use 'make bump-version VERSION=x.y.z'"; \
		exit 1; \
	fi
	@chmod +x scripts/bump_all.py
	@python3 scripts/bump_all.py $(VERSION)

check-devices:
	@echo "==> Checking for connected devices..."
	@flutter devices | grep -E "connected device|wirelessly|•" || true
	@echo ""

macos-signing-check:
	@bash nmtk/installer/macos/sign-and-notarize.sh --check

WEBTOP_PORT ?= 3030

webtop-build:
	docker compose -f docker-compose.webtop.yml build

webtop-up:
	docker compose -f docker-compose.webtop.yml up -d --wait
	@WEBTOP_IP=$$(python3 -c "import socket; s=socket.socket(socket.AF_INET, socket.SOCK_DGRAM); s.connect(('8.8.8.8', 80)); print(s.getsockname()[0]); s.close()" 2>/dev/null || echo "localhost"); \
	echo "NMTK Desktop available at http://$$WEBTOP_IP:$(WEBTOP_PORT)"

webtop-down:
	docker compose -f docker-compose.webtop.yml down

webtop: webtop-build webtop-up

build-macos-dmg-signed:
	@BUILD_ARGS=(--dmg); \
	if [ -n "$${MACOS_SIGNING_IDENTITY:-}" ]; then BUILD_ARGS+=(--sign "$$MACOS_SIGNING_IDENTITY"); fi; \
	if [ -n "$${MACOS_SIGNING_IDENTITY:-}" ] && [ -n "$${APPLE_ID:-}" ] \
	  && { [ -n "$${APPLE_PASSWORD:-}" ] || [ -n "$${APPLE_APP_SPECIFIC_PASSWORD:-}" ]; } \
	  && [ -n "$${APPLE_TEAM_ID:-}" ]; then \
	  BUILD_ARGS+=(--notarize); \
	  export MACOS_NOTARIZE=true; \
	fi; \
	bash nmtk/installer/macos/build-standalone.sh "$${BUILD_ARGS[@]}"
