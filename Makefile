.PHONY: release help dev dev-a dev-i dev-web dev-native clean-all bump-version ci suite_api_dev check-devices docker docker-a docker-i docker-physics docker-hardware docker-all docker-ex docker-ex-m docker-ex-a docker-ex-i docker-ex-down

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
	@echo "  make docker-physics           - Run backend + physics worker in Docker and native launcher"
	@echo "  make docker-hardware          - Run backend + hardware workers in Docker and native launcher"
	@echo "  make docker-all               - Run backend + all active profiles/containers in Docker and native launcher"
	@echo "  make docker-ex REMOTE_HOST=user@ip - Deploy backend to a remote server using SSH and Docker"
	@echo "  make docker-ex-m REMOTE_HOST=user@ip - Deploy to remote and run frontend on macOS"
	@echo "  make docker-ex-a REMOTE_HOST=user@ip - Deploy to remote and run frontend on Android"
	@echo "  make docker-ex-i REMOTE_HOST=user@ip - Deploy to remote and run frontend on iOS"
	@echo "  make docker-ex-down REMOTE_HOST=user@ip - Stop and remove remote Docker containers"
	@echo "  make suite_api_dev            - Start unified suite_api backend on port 9000 (with reload)"
	@echo "  make release VERSION=x.y.z    - Run the full release automation pipeline"
	@echo "  make bump-version VERSION=x.y.z - Synchronize all versions across the monorepo"
	@echo "  make clean-all                - Deep clean the entire monorepo"
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

docker-physics:
	@./scripts/run_dev.sh --docker --profile physics --flutter-device "$(FLUTTER_DEVICE)"

docker-hardware:
	@./scripts/run_dev.sh --docker --profile hardware --flutter-device "$(FLUTTER_DEVICE)"

docker-all:
	@./scripts/run_dev.sh --docker --profile all --flutter-device "$(FLUTTER_DEVICE)"

# Deployment variables (can be overridden on command line)
REMOTE_HOST ?= 
DEPLOY_DIR ?= ~/nmtk-deploy
DOCKER_EX_SERVICES ?= suite_api lava-backend

docker-ex:
	@if [ -z "$(REMOTE_HOST)" ]; then \
		echo "Error: REMOTE_HOST is not set. Example: make docker-ex REMOTE_HOST=user@192.168.1.50"; \
		exit 1; \
	fi
	@echo "==> Syncing source code to $(REMOTE_HOST)..."
	ssh $(REMOTE_HOST) "mkdir -p $(DEPLOY_DIR)"
	rsync -avz --exclude '.git' --exclude '.env' --exclude 'venv' --exclude '.venv' --exclude '__pycache__' --exclude 'node_modules' . $(REMOTE_HOST):$(DEPLOY_DIR)
	@echo "==> Starting Docker containers on $(REMOTE_HOST)..."
	ssh $(REMOTE_HOST) "cd $(DEPLOY_DIR) && docker compose up --build --wait -d lava-backend && NEUROCNL_LAVA_WORKER_URL=http://lava-backend:8012 docker compose up --build -d suite_api"
	@echo "==> Backend deployed. Access it at http://$$(echo $(REMOTE_HOST) | cut -d@ -f2):9000"

docker-ex-m: docker-ex
	@./scripts/run_dev.sh --flutter-device macos --remote-host "$$(echo $(REMOTE_HOST) | cut -d@ -f2)"

docker-ex-a: docker-ex
	@$(MAKE) check-devices
	@echo "==> Using Android device: $(ANDROID_DEVICE)"
	@./scripts/run_dev.sh --flutter-device "$(ANDROID_DEVICE)" --remote-host "$$(echo $(REMOTE_HOST) | cut -d@ -f2)"

docker-ex-i: docker-ex
	@$(MAKE) check-devices
	@echo "==> Using iOS device: $(IOS_DEVICE)"
	@./scripts/run_dev.sh --flutter-device "$(IOS_DEVICE)" --remote-host "$$(echo $(REMOTE_HOST) | cut -d@ -f2)"

docker-ex-down:
	@if [ -z "$(REMOTE_HOST)" ]; then \
		echo "Error: REMOTE_HOST is not set. Example: make docker-ex-down REMOTE_HOST=user@192.168.1.50"; \
		exit 1; \
	fi
	@echo "==> Stopping Docker containers on $(REMOTE_HOST)..."
	ssh $(REMOTE_HOST) "cd $(DEPLOY_DIR) && docker compose down"

suite_api_dev:
	uvicorn suite_api.main:app --host 0.0.0.0 --port 9000 --reload

ci:
	@chmod +x scripts/run_ci_local.sh
	@./scripts/run_ci_local.sh --all

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
