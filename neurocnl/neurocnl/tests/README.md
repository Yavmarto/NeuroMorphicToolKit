# neurocnl Tests

This directory contains unit and integration tests for the `neurocnl` module.

## Running Tests

To run all core `neurocnl` tests:
```bash
PYTHONPATH=. pytest neurocnl/tests/
```

By default, this excludes the backend smoke test. To include it:
```bash
NEUROCNL_RUN_BACKEND_SMOKE=1 PYTHONPATH=. pytest neurocnl/tests/
```

## Backend Smoke Test

The smoke test (`test_backend_smoke.py`) validates the full Studio backend flow by starting a real FastAPI server and exercising critical endpoints (templates, validation, simulation, jobs).

To run the smoke test locally:
```bash
NEUROCNL_RUN_BACKEND_SMOKE=1 PYTHONPATH=. pytest tests/test_backend_smoke.py
```

Ensure that all dependencies for both the backend and `neurocnl` are installed.
