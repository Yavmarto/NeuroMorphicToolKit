# T4-5: Add root-level pre-commit hooks

- **Problem:** neurocnl and Neurohub have per-module pre-commit configs. No root-level enforcement exists.
- **Fix:** Create root `.pre-commit-config.yaml` with ruff, mypy, and flutter analyze hooks scoped to relevant paths.
- **Effort:** 0.5 day
