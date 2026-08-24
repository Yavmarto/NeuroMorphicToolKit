.PHONY: install verify test lint format-check typecheck

install:
	python -m pip install -e ".[dev]" -q

verify: install lint format-check typecheck test

test:
	env -u PYTEST_ADDOPTS PYTEST_DISABLE_PLUGIN_AUTOLOAD=1 python -m pytest tests/ -q

lint:
	ruff check neurocli/ tests/

format-check:
	ruff format --check neurocli/ tests/

typecheck:
	mypy neurocli/ --ignore-missing-imports
