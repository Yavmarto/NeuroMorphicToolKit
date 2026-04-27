.PHONY: release help dev dev-web dev-native build-submodules rebuild-submodules build-interactive clean-all build-all bump-version ci suite_api_dev

MODULES = neurocnl Neurosim Neurochip Neurobench Neurosense Neurohub
PORT_neurocnl = 8000
PORT_Neurosim = 8001
PORT_Neurochip = 8002
PORT_Neurobench = 8003
PORT_Neurosense = 8004
PORT_Neurohub = 8005

# OS detection for Flutter device targeting
OS := $(shell uname)
ifeq ($(OS), Darwin)
  FLUTTER_DEVICE = macos
else ifeq ($(OS), Linux)
  FLUTTER_DEVICE = linux
else
  FLUTTER_DEVICE = windows
endif

# Shared UI core dependency
UI_CORE_FILES = $(shell find nmtk_ui_core/lib -type f) nmtk_ui_core/pubspec.yaml

help:
	@echo "NeuroMorphicToolkit (NMTK) Build System"
	@echo ""
	@echo "Usage:"
	@echo "  make dev                      - Build all submodules and run the launcher"
	@echo "  make dev-native               - Run launcher in fully native mode (no web builds)"
	@echo "  make dev -w                  - Also build/serve the launcher web app on your LAN"
	@echo "  make dev-web                 - Same as 'make dev -w'"
	@echo "  make suite_api_dev            - Start unified suite_api backend on port 9000 (with reload)"
	@echo "  make build-submodules         - Build all submodule web frontends (only if changed)"
	@echo "  make rebuild-submodules       - Force rebuild all submodule web frontends"
	@echo "  make build-interactive        - Interactively select modules to build"
	@echo "  make release VERSION=x.y.z    - Run the full release automation pipeline"
	@echo "  make bump-version VERSION=x.y.z - Synchronize all versions across the monorepo"
	@echo "  make clean-all                - Deep clean the entire monorepo"
	@echo ""

# Legacy target for backward compatibility, now only builds what's changed
build-submodules: $(addprefix build-,$(MODULES))

rebuild-submodules:
	@chmod +x scripts/build_module.sh
	@for mod in $(MODULES); do \
		case "$$mod" in \
			neurocnl) port="$(PORT_neurocnl)" ;; \
			Neurosim) port="$(PORT_Neurosim)" ;; \
			Neurochip) port="$(PORT_Neurochip)" ;; \
			Neurobench) port="$(PORT_Neurobench)" ;; \
			Neurosense) port="$(PORT_Neurosense)" ;; \
			Neurohub) port="$(PORT_Neurohub)" ;; \
			*) echo "Unknown module $$mod"; exit 1 ;; \
		esac; \
		./scripts/build_module.sh "$$mod" "$$port"; \
	done

build-interactive:
	@chmod +x scripts/select_modules.sh
	@./scripts/select_modules.sh

dev:
	@chmod +x scripts/build_module.sh scripts/run_dev.sh
	@case " $(MAKEFLAGS) " in \
		*" --print-directory "*|*" w "*) \
			./scripts/run_dev.sh --flutter-device "$(FLUTTER_DEVICE)" --with-web ;; \
		*) \
			./scripts/run_dev.sh --flutter-device "$(FLUTTER_DEVICE)" ;; \
	esac

dev-web:
	@chmod +x scripts/build_module.sh scripts/run_dev.sh
	@./scripts/run_dev.sh --flutter-device "$(FLUTTER_DEVICE)" --with-web

dev-native:
	@chmod +x scripts/run_dev.sh
	@./scripts/run_dev.sh --flutter-device "$(FLUTTER_DEVICE)" --native-only

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

# Dependency rules for each module
define BUILD_RULE
build-$(1): $(1)/frontend/build/web/index.html

$(1)/frontend/build/web/index.html: $(shell find $(1)/frontend/lib -type f 2>/dev/null) $(1)/frontend/pubspec.yaml $(UI_CORE_FILES)
	@chmod +x scripts/build_module.sh
	@./scripts/build_module.sh $(1) $(PORT_$(1))
	@touch $(1)/frontend/build/web/index.html
endef

$(foreach mod,$(MODULES),$(eval $(call BUILD_RULE,$(mod))))
