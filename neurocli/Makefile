.PHONY: install verify test lint typecheck

install:
	pip install -e ".[dev]" -q

verify: install lint typecheck test

test:
	python -m pytest tests/ -q

lint:
	ruff check neurocli/

typecheck:
	mypy neurocli/ --ignore-missing-imports
