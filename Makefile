.PHONY: release help

help:
	@echo "NeuroMorphicToolkit (NMTK) Build System"
	@echo ""
	@echo "Usage:"
	@echo "  make release VERSION=x.y.z    - Run the full release automation pipeline"
	@echo ""

release:
	@if [ -z "$(VERSION)" ]; then \
		echo "Error: VERSION is not set. Use 'make release VERSION=x.y.z'"; \
		exit 1; \
	fi
	@bash scripts/release.sh $(VERSION)
