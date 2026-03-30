.PHONY: release help dev build-submodules clean-all

help:
	@echo "NeuroMorphicToolkit (NMTK) Build System"
	@echo ""
	@echo "Usage:"
	@echo "  make dev                      - Build all submodules and run the launcher"
	@echo "  make build-submodules          - Build all submodule web frontends"
	@echo "  make release VERSION=x.y.z    - Run the full release automation pipeline"
	@echo "  make clean-all                - Deep clean the entire monorepo"
	@echo ""

build-submodules:
	@bash scripts/build_all_frontends.sh

dev: build-submodules
	@cd nmtk/neuro_toolkit && flutter run -d macos

clean-all:
	@chmod +x scripts/deep_clean.sh
	@./scripts/deep_clean.sh

release:
	@if [ -z "$(VERSION)" ]; then \
		echo "Error: VERSION is not set. Use 'make release VERSION=x.y.z'"; \
		exit 1; \
	fi
	@bash scripts/release.sh $(VERSION)
