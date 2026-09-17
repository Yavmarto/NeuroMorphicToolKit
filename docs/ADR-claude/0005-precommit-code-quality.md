# ADR 0005: Pre-commit and Code Quality Enforcement

## Status
Accepted

## Context
The monorepo contains Python backends, Flutter/Dart frontends, YAML configuration, and shell scripts across 10+ modules. Consistent code quality requires automated enforcement, but different languages need different tools and some modules have stricter requirements than others.

## Decision
A root-level `.pre-commit-config.yaml` enforces code quality via: Ruff for Python linting (replacing flake8/pylint), mypy for strict type checking on core pipeline modules (neurocnl, Neuro-Dream-Hand), Black and isort for Python formatting, Flutter analyze for Dart code, and standard hooks for trailing whitespace and YAML validation. CI runs these same checks but with `continue-on-error: true` for some modules during migration periods.

## Consequences
- **Positive:** Pre-commit hooks catch quality issues before they enter version control; a single config file governs all modules for consistency.
- **Negative:** `continue-on-error: true` in CI undermines enforcement for modules still being migrated; mypy strict mode is only enforced on core modules, leaving peripheral code with weaker type safety.
