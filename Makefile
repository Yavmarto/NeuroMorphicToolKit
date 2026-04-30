.PHONY: release help dev dev-a dev-i dev-native clean-all bump-version ci suite_api_dev

# OS detection for Flutter device targeting
OS := $(shell uname)
ifeq ($(OS), Darwin)
  FLUTTER_DEVICE = macos
else ifeq ($(OS), Linux)
  FLUTTER_DEVICE = linux
else
  FLUTTER_DEVICE = windows
endif


help:
	@echo "NeuroMorphicToolkit (NMTK) Build System"
	@echo ""
	@echo "Usage:"
	@echo "  make dev                      - Run suite_api and the native launcher"
	@echo "  make dev-a                    - Run suite_api and the launcher on Android"
	@echo "  make dev-i                    - Run suite_api and the launcher on iOS"
	@echo "  make dev-native               - Run the native launcher control API and Flutter app"
	@echo "  make suite_api_dev            - Start unified suite_api backend on port 9000 (with reload)"
	@echo "  make release VERSION=x.y.z    - Run the full release automation pipeline"
	@echo "  make bump-version VERSION=x.y.z - Synchronize all versions across the monorepo"
	@echo "  make clean-all                - Deep clean the entire monorepo"
	@echo ""

dev:
	@echo "==> Ensuring port 9000 is free..."
	@lsof -ti:9000 | xargs kill -9 2>/dev/null || true
	@uvicorn suite_api.main:app --port 9000 --reload & \
	SUITE_API_PID=$$!; \
	trap 'kill $$SUITE_API_PID 2>/dev/null || true' EXIT INT TERM; \
	./scripts/run_dev.sh --flutter-device "$(FLUTTER_DEVICE)"

dev-a:
	@echo "==> Ensuring port 9000 is free..."
	@lsof -ti:9000 | xargs kill -9 2>/dev/null || true
	@uvicorn suite_api.main:app --port 9000 --reload & \
	SUITE_API_PID=$$!; \
	trap 'kill $$SUITE_API_PID 2>/dev/null || true' EXIT INT TERM; \
	./scripts/run_dev.sh --flutter-device "android"

dev-i:
	@echo "==> Ensuring port 9000 is free..."
	@lsof -ti:9000 | xargs kill -9 2>/dev/null || true
	@uvicorn suite_api.main:app --port 9000 --reload & \
	SUITE_API_PID=$$!; \
	trap 'kill $$SUITE_API_PID 2>/dev/null || true' EXIT INT TERM; \
	./scripts/run_dev.sh --flutter-device "ios"

dev-native:
	@chmod +x scripts/run_dev.sh
	@./scripts/run_dev.sh --flutter-device "$(FLUTTER_DEVICE)"

suite_api_dev:
	uvicorn suite_api.main:app --port 9000 --reload

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
