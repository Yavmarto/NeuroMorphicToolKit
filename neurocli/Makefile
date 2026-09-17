.PHONY: install verify test lint format-check typecheck

install:
	uv sync --extra dev -q

verify: install lint format-check typecheck test

test:
	env -u PYTEST_ADDOPTS PYTEST_DISABLE_PLUGIN_AUTOLOAD=1 uv run python -m pytest tests/ -q

lint:
	uv run ruff check neurocli/ tests/

format-check:
	uv run ruff format --check neurocli/ tests/

typecheck:
	uv run mypy neurocli/ --ignore-missing-imports
