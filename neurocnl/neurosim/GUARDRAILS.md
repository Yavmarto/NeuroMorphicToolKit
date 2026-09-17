# Neurosim Guardrails

This document defines strict rules and constraints to ensure the architectural integrity, performance, and stability of the Neurosim module.

## Architectural Guardrails
- **Import Style:** All internal backend imports MUST use relative paths (e.g., `from ..services import ...`). Absolute imports for submodules within `neurosim/` are forbidden to maintain portable testability.
- **Contract Stability:** Do not modify `neurosim/contracts/design_contracts.py` without verifying all consumers across the FastAPI backend (`neurosim/app/routers`) and the Flutter frontend models. These contracts represent the shared data language.
- **Separation of Concerns:** Business logic and heavy computations MUST reside in `neurosim/app/services/`. FastAPI routers should only handle request parsing, dependency injection, and response formatting.
- **No Shared State:** The backend must remain stateless. All project state must be managed via client-side `CanvasGraph` and persisted through the projects API.

## Performance & Safety Guardrails
- **Preview Constraints:** Real-time simulation previews (via `/api/neurosim/preview`) must be capped at 500ms of simulation time to ensure sub-2-second responsiveness.
- **Validation Optimization:** Graph validation rules must remain synchronous and highly optimized. Avoid blocking calls to external services during validation.
- **Sweep Limits:** Parameter sweeps are limited to a maximum of 20 steps per batch to prevent server-side resource exhaustion.
- **Resource Caps:** All simulation jobs (previews and sweeps) must adhere to defined resource limits, capping node counts and data collection scales to prevent Out-Of-Memory (OOM) failures on the backend.

## Data Guardrails
- **Invariant Enforcement:** Never bypass Layer 1 validation when generating CNL from a `CanvasGraph`. The generated spec must always be syntactically and semantically valid according to CNL spec constraints.
- **Parameter Validation:** All node and edge parameters MUST be validated against the `min`/`max` bounds defined in their respective `ParameterDef` JSON schemas.
- **Scientific Notation:** Parameter parsing (especially in `cnl_to_graph`) must support scientific notation to maintain compatibility with standard engineering constants (e.g., `1e-3`).

## Maintenance Guardrails
- **Artifact Management:** Do NOT commit `__pycache__`, `.egg-info`, `.pytest_cache`, `.mypy_cache`, `.hypothesis/`, or Flutter build artifacts (`build/`).
- **Dependency Integrity:** All new dependencies must be justified and added to `pyproject.toml` or `pubspec.yaml` with strict version constraints.
- **Pydantic V2 Usage:** Use `model_dump()` for serializing nested Pydantic models to avoid validation errors during request instantiation.
