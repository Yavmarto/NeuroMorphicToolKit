# NeuroHub Smoke Tests

This directory contains the end-to-end smoke tests for NeuroHub.

## Purpose
The smoke tests verify the core orchestration paths against a real, network-bound NeuroHub instance, ensuring that project management and suite-wide activity tracking are functioning correctly.

## Coverage
The smoke test (`neurohub/tests/test_smoke.py`) covers:
1. **Project Creation**: Verifies that new projects can be successfully initialized.
2. **Member Management**: Verifies that project members can be added and updated.
3. **Workflow Orchestration**: Verifies that multi-step workflows can be created and tracked.
4. **Activity Monitoring**: Verifies that suite-wide activity logs are correctly aggregated.

## Running Locally
To run the smoke tests locally, you can use the provided orchestration script:

```bash
./scripts/run_smoke_test.sh
```

This script will:
- Start a mock suite server on port 8082.
- Initialize a local SQLite database for the backend.
- Start the NeuroHub backend on port 8005.
- Configure the backend to point to the mock suite.
- Execute the smoke tests.
- Clean up all processes and temporary files.

## Running in CI
The smoke tests are executed as part of the `NeuroHub CI` workflow. The CI environment uses the same orchestration script to ensure consistency between local development and production-like environments.

## Diagnosis
If a smoke test fails:
- Check `backend.log` for backend-specific errors (API failures, DB issues).
- Check `mock_server.log` for issues with simulated suite apps.
- Verify environment variables like `NEUROHUB_URL` and `NEUROHUB_API_KEY` are correctly set.
