# Neurosim Backend Tests

This directory contains the backend test suite for Neurosim.

## Running Tests

### Standard Tests
To run all standard unit and integration tests:
```bash
python -m pytest neurosim/tests/ -p no:nengo
```

### E2E Smoke Tests
The E2E smoke tests run the full pipeline using a real backend process.

To run the parameter sweep smoke test:
```bash
python -m pytest neurosim/tests/test_sweep_smoke_e2e.py -p no:nengo
```

**Expected Duration:** ~5-10 seconds.

## Test Types
- `test_contracts.py`: Validates Pydantic models and API contracts.
- `test_integration.py`: High-level integration tests for the full pipeline.
- `test_simulation_integration.py`: Tests for real simulation runs (Nengo).
- `test_sweep_smoke_e2e.py`: E2E smoke test using a real `uvicorn` process.
- `routers/`: Unit tests for API endpoints.
- `services/`: Unit tests for backend services.
