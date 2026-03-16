# Unified Merge & Maintenance Plan
**Created:** 2026-03-15
**Supersedes:** `integration_plan_backend.md`, `integration_plan_frontend.md`, `Maintenance_update.md`
**Scope:** neurocnl (Python library + FastAPI backend + Flutter frontend), Neuro-Dream-Hand, servo_control

---

## Executive Summary

This plan unifies three separate documents — backend integration, frontend integration, and maintenance — into a single execution-ordered sequence. Every task from the original three plans is preserved, merged where overlapping, and reordered so that dependencies are respected.

**Guiding principle:** Clean foundation first, then integrate, then extend the frontend, then polish.

**Architecture decision:** The Neuro-Dream-Hand HTTP surface is built as **new routers inside the existing neurocnl FastAPI backend** (not a separate service). This avoids CORS/proxy complexity and gives a single OpenAPI schema. The frontend plan's "Phase 1 — Build NDH REST API" is therefore absorbed into the backend integration phases.

---

## Conflict Resolutions

| Conflict | Resolution |
|---|---|
| Frontend plan proposes a separate NDH FastAPI service (`Neuro-Dream-Hand/api/`) | **Rejected.** NDH endpoints are added as routers in the neurocnl backend. Single process, single origin, single OpenAPI spec. |
| Frontend plan defines `/api/ndh/*` prefix; backend plan defines `/api/prosthetic/*` | **Use `/api/prosthetic/*`** — more descriptive, avoids abbreviation. |
| Frontend plan lists 12 NDH endpoints; backend plan lists 4 | **Merge.** Backend plan's 4 endpoints are the MVP. Frontend plan's extras (controller/step, energy, quantize, hardware/*) are added as a follow-up phase. |
| Maintenance TASK-07 (background simulation) overlaps with backend Phase 3 (prosthetic simulate also needs background tasks) | **Merge.** Build the generic job system once (TASK-07), then reuse it for prosthetic endpoints. |
| Maintenance TASK-17 (go_router) and frontend Phase 2a (NavigationRail) both restructure navigation | **Merge.** go_router is the mechanism; NavigationRail is the UI. Do them together. |
| Maintenance TASK-16 (improve /health) and backend Phase 6 (/api/prosthetic/health) | **Merge.** Extend /health once: include nengo + neurocnl + optional MuJoCo availability. Add a separate `/api/prosthetic/health` only for MuJoCo-specific checks. |
| Maintenance TASK-18 (externalize API URL) and frontend Phase 2e (new API client methods) | **Sequence.** Externalize URL first, then add NDH methods to the client. |

---

## Phase 0 — Foundation: Code Quality & Build Hygiene
> **Goal:** Establish a clean, linted, typed, tested baseline before adding any new code. Everything in this phase is maintenance work that de-risks integration.

---

### TASK-01 · Neuro-Dream-Hand: Migrate setup.py to pyproject.toml
*(Was: Maintenance TASK-11)*

**Priority:** Critical (blocks adding NDH as a backend dependency)
**Effort:** Small

**Spec:**
Migrate `setup.py` to a PEP 517/518 `pyproject.toml` using `hatchling` as the build backend.

The new `pyproject.toml` must include:
- `[build-system]` with `hatchling`
- `[project]` with all metadata (name, version, description, requires-python, dependencies)
- `[project.optional-dependencies]` for `video`, `hardware`, `loihi`, `physics` extras
  - Move `mujoco>=3.1.0` into `[project.optional-dependencies.physics]` so the backend can install without MuJoCo
- `[project.scripts]` for `neurodreamhand-sweep` and `neurodreamhand-plot` CLI entry points
- `[tool.pytest.ini_options]`

Delete `setup.py` and `setup.cfg` (if present) after migration.

**Acceptance Criteria:**
- `pip install -e .` succeeds using only `pyproject.toml`.
- `pip install -e ".[physics]"` additionally installs MuJoCo.
- `neurodreamhand-sweep --help` and `neurodreamhand-plot --help` work.
- `setup.py` is deleted.

**Files Affected:**
```
Neuro-Dream-Hand/pyproject.toml   <- rewrite
Neuro-Dream-Hand/setup.py         <- delete
Neuro-Dream-Hand/setup.cfg        <- delete if present
```

---

### TASK-02 · Both Python Projects: Add ruff Linter + Formatter
*(Was: Maintenance TASK-05)*

**Priority:** Critical
**Effort:** Small

**Spec:**
Add `ruff` as the unified linter + formatter for both Python projects.

Add to both `pyproject.toml` files:
```toml
[tool.ruff]
target-version = "py311"
line-length = 100
select = ["E", "F", "W", "I", "UP", "B", "C4", "SIM", "T201"]
ignore = ["E501"]

[tool.ruff.format]
quote-style = "double"
indent-style = "space"
```

Note: `T201` rule (no `print`) is included — this subsumes Maintenance TASK-12 (replace print with logging). Fix all `print()` calls in library code by replacing with `logging` calls during the lint fix pass.

Add module-level loggers in each file:
```python
import logging
logger = logging.getLogger(__name__)
```

Do **not** configure the root logger inside library code. Configure `logging.basicConfig()` only in CLI entry points and test config.

Fix all existing violations before merging.

**Acceptance Criteria:**
- `ruff check .` returns 0 violations in both projects.
- `ruff format --check .` returns 0 reformatting needed.
- No `print()` calls remain in `neurodreamhand/` or `neurocnl/neurocnl/` library code.
- Log level is controllable via `--verbose` CLI flag.

**Files Affected:**
```
Neuro-Dream-Hand/pyproject.toml
neurocnl/pyproject.toml
Neuro-Dream-Hand/neurodreamhand/**/*.py   <- replace print -> logger + lint fixes
neurocnl/neurocnl/**/*.py                 <- replace print -> logger + lint fixes
Neuro-Dream-Hand/scripts/*.py             <- configure basicConfig at entry
neurocnl/neurocnl/simulation/run_simulation.py <- configure basicConfig
```

---

### TASK-03 · Both Python Projects: Add mypy Type Checking
*(Was: Maintenance TASK-06)*

**Priority:** Critical
**Effort:** Medium

**Spec:**
Add `mypy` static type checking to both projects.

Add to both `pyproject.toml`:
```toml
[tool.mypy]
python_version = "3.11"
strict = false
warn_return_any = true
warn_unused_ignores = true
ignore_missing_imports = true
disallow_untyped_defs = true
```

Fix all type errors. For third-party libraries without stubs (nengo, mujoco), add `# type: ignore[import-untyped]` where needed.

**Acceptance Criteria:**
- `mypy neurodreamhand/` and `mypy neurocnl/` both exit with code 0.
- All untyped function definitions are annotated.

**Files Affected:**
```
Neuro-Dream-Hand/pyproject.toml
neurocnl/pyproject.toml
Neuro-Dream-Hand/neurodreamhand/**/*.py   <- add/fix type annotations
neurocnl/neurocnl/**/*.py                 <- add/fix type annotations
```

---

### TASK-04 · neurocnl: Add TypedDict for Parser Output
*(Was: Maintenance TASK-09)*

**Priority:** Critical (blocks pipeline collapse and integration)
**Effort:** Small

**Spec:**
`cnl_parser.py` returns raw `dict` objects. Define a `TypedDict` to make the shape explicit:

```python
# neurocnl/cnl/types.py
from typing import TypedDict

class ParsedSentence(TypedDict):
    concept: str
    subject: str
    action: str
    verb: str
    negated: bool
    condition: str | None
    raw: str
```

Update `cnl_parser.py` to return `list[ParsedSentence]`.
Update all consumers (`layer1_validator.py`, `layer2_validator.py`, `nengo_generator.py`, `assertion_generator.py`) to type their inputs as `list[ParsedSentence]`.

**Acceptance Criteria:**
- `mypy neurocnl/` passes with `ParsedSentence` typed throughout.
- No `dict` return types remain in the parser public API.
- Existing parser tests still pass.

**Files Affected:**
```
neurocnl/neurocnl/cnl/types.py                        <- new
neurocnl/neurocnl/cnl/cnl_parser.py                   <- return ParsedSentence
neurocnl/neurocnl/layers/layer1_validator.py
neurocnl/neurocnl/layers/layer2_validator.py
neurocnl/neurocnl/generation/nengo_generator.py
neurocnl/neurocnl/generation/assertion_generator.py
```

---

### TASK-05 · neurocnl: Collapse Duplicate Pipeline Orchestration
*(Was: Maintenance TASK-10)*

**Priority:** Critical (must happen before integration adds more pipeline consumers)
**Effort:** Small

**Spec:**
`neurocnl/simulation/run_simulation.py` (CLI) and `backend/app/routers/simulate.py` (API) both implement parse -> validate -> generate -> simulate. This DRY violation will worsen when prosthetic endpoints add more pipeline consumers.

1. Create `neurocnl/neurocnl/pipeline.py` with:
   ```python
   def run_pipeline(spec_text: str, backend: str = "nengo", verbose: bool = False) -> PipelineResult
   ```
2. Define `PipelineResult` as a dataclass with fields: `parsed`, `validation`, `network`, `simulation`, `assertions`, `errors`.
3. Refactor `run_simulation.py` to call `run_pipeline()`.
4. Refactor the simulate router / `neurocnl_bridge.py` to call `run_pipeline()`.

**Acceptance Criteria:**
- No duplicated orchestration logic remains.
- `pipeline.py` has tests via `test_pipeline.py`.
- CLI and API behavior unchanged.

**Files Affected:**
```
neurocnl/neurocnl/pipeline.py                         <- new
neurocnl/neurocnl/simulation/run_simulation.py         <- refactor
neurocnl/backend/app/routers/simulate.py               <- refactor
neurocnl/backend/app/services/neurocnl_bridge.py       <- simplify
neurocnl/neurocnl/tests/test_pipeline.py               <- new
```

---

### TASK-06 · Flutter: Add analysis_options.yaml
*(Was: Maintenance TASK-03)*

**Priority:** Critical
**Effort:** Small

**Spec:**
Create `neurocnl/frontend/analysis_options.yaml` extending `flutter_lints`:

```yaml
include: package:flutter_lints/flutter.yaml

analyzer:
  strong-mode:
    implicit-casts: false
    implicit-dynamic: false
  errors:
    missing_return: error
    dead_code: warning
    unused_import: warning
    unnecessary_null_comparison: warning

linter:
  rules:
    - prefer_const_constructors
    - prefer_const_literals_to_create_immutables
    - avoid_print
    - always_declare_return_types
    - annotate_overrides
    - prefer_single_quotes
    - sort_pub_dependencies
```

Fix all existing violations before merging.

**Acceptance Criteria:**
- `flutter analyze` returns 0 errors and 0 warnings.
- `avoid_print` rule catches and forces removal of any `print()` calls in `lib/`.

**Files Affected:**
```
neurocnl/frontend/analysis_options.yaml   <- new
neurocnl/frontend/lib/**/*.dart           <- fix violations
neurocnl/frontend/pubspec.yaml            <- add flutter_lints if not present
```

---

### TASK-07 · neurocnl Backend: Add FastAPI Endpoint Tests
*(Was: Maintenance TASK-04)*

**Priority:** Critical
**Effort:** Medium

**Spec:**
Create `neurocnl/backend/tests/` with a test suite for every router using FastAPI `TestClient`.

Test files:
- `test_parse_router.py` — POST `/api/parse` with valid spec, invalid spec, empty body.
- `test_validate_router.py` — POST `/api/validate` with valid parsed spec, spec with invariant violations.
- `test_generate_router.py` — POST `/api/generate` with valid validated spec, unvalidated spec (expect 422).
- `test_simulate_router.py` — POST `/api/simulate` with a minimal valid spec; mock Nengo sim.
- `test_export_router.py` — POST `/api/export` for both `nengo` and `loihi` format targets.
- `test_templates_router.py` — GET `/api/templates` returns a non-empty list.
- `test_health.py` — GET `/health` returns 200.

Each test must assert status code, response body shape, and error responses for malformed input.

**Acceptance Criteria:**
- `pytest backend/tests/ -v` passes with 0 failures.
- At least 2 tests per router (happy path + error path).
- Nengo simulation is mocked so the test suite runs in < 5 seconds.

**Files Affected:**
```
neurocnl/backend/tests/
  conftest.py
  test_parse_router.py
  test_validate_router.py
  test_generate_router.py
  test_simulate_router.py
  test_export_router.py
  test_templates_router.py
  test_health.py
```

---

### TASK-08 · Flutter: Add Widget & Unit Tests
*(Was: Maintenance TASK-01)*

**Priority:** Critical
**Effort:** Medium

**Spec:**
Create `neurocnl/frontend/test/` with three test suites:

1. **Unit tests** for Riverpod providers (mock `ApiClient` using `mocktail`):
   - `spec_provider_test.dart`, `parse_result_provider_test.dart`, `validation_provider_test.dart`, `network_provider_test.dart`

2. **Widget tests** for core widgets:
   - `pipeline_bar_test.dart`, `template_gallery_test.dart`, `simulation_dashboard_test.dart`

3. **Model tests** (`fromJson` round-trips):
   - `parsed_spec_test.dart`, `network_graph_test.dart`, `simulation_result_test.dart`

**Acceptance Criteria:**
- `flutter test` passes with 0 failures.
- At least 1 test per provider, 1 per widget, 1 `fromJson` round-trip per model.
- `flutter test --coverage` reports >= 60% line coverage on `lib/`.

**Files Affected:**
```
neurocnl/frontend/test/
  unit/providers/*.dart
  widget/widgets/*.dart
  model/models/*.dart
neurocnl/frontend/pubspec.yaml   <- add mocktail, flutter_test
```

---

### TASK-09 · CI: Unified Workflows for All Projects
*(Was: Maintenance TASK-02 + TASK-05/06 CI parts)*

**Priority:** Critical
**Effort:** Small

**Spec:**
Create (or update) GitHub Actions workflows:

**`.github/workflows/python_ci.yml`** — runs on push/PR to `main`:
1. `actions/checkout`
2. `actions/setup-python@v5` (Python 3.11)
3. `pip install -e ".[dev]"` for both projects
4. `ruff check . && ruff format --check .`
5. `mypy neurodreamhand/` / `mypy neurocnl/`
6. `pytest --cov --cov-report=xml`
7. Upload coverage artifact

**`.github/workflows/flutter_ci.yml`** — runs on push/PR to `main`:
1. `actions/checkout`
2. `subosito/flutter-action@v2`
3. `flutter pub get`
4. `flutter analyze`
5. `flutter test --coverage`
6. `flutter build web --release`
7. Upload `coverage/lcov.info`

**Acceptance Criteria:**
- All steps pass on a clean checkout.
- A PR introducing a lint violation, type error, or test failure causes CI to fail.
- Both workflows are syntactically valid YAML.

**Files Affected:**
```
.github/workflows/python_ci.yml    <- new or update
.github/workflows/flutter_ci.yml   <- new
```

---

## Phase 1 — Backend Architecture & Resilience
> **Goal:** Harden the existing backend before bolting on new endpoints.

---

### TASK-10 · Backend: Offload Simulation to Background Task + Job System
*(Was: Maintenance TASK-07. Also provides the job infrastructure reused by prosthetic endpoints.)*

**Priority:** High
**Effort:** Medium

**Spec:**
The `/api/simulate` endpoint runs Nengo synchronously. Refactor to async with a reusable job system (this system will also be used by `POST /api/prosthetic/simulate` and `POST /api/prosthetic/sleep` later).

1. Create `backend/app/services/job_store.py` — an in-memory job registry:
   ```python
   class JobStore:
       def create(self) -> str: ...          # returns uuid job_id
       def set_running(self, job_id): ...
       def set_complete(self, job_id, result): ...
       def set_failed(self, job_id, error): ...
       def get(self, job_id) -> JobStatus: ...
   ```
2. Change `POST /api/simulate` to return HTTP 202 with `{ "job_id": "<uuid>", "status": "queued" }`.
3. Run simulation in `loop.run_in_executor(None, run_pipeline, params)`.
4. Add `GET /api/jobs/{job_id}` — returns `{ "status": "queued|running|complete|failed", "result": ..., "error": ... }`.
5. Add configurable timeout (default 60s). Exceeded -> `"failed"` with timeout error.

**Acceptance Criteria:**
- `POST /api/simulate` returns 202 immediately (< 100 ms).
- `GET /api/jobs/{job_id}` returns the full result once complete.
- Timeout produces `{ "status": "failed", "error": "simulation timeout" }`.
- Tests updated for the two-step flow.

**Files Affected:**
```
neurocnl/backend/app/services/job_store.py        <- new
neurocnl/backend/app/schemas/jobs.py              <- new: JobStatus, JobResponse
neurocnl/backend/app/routers/jobs.py              <- new: GET /api/jobs/{job_id}
neurocnl/backend/app/routers/simulate.py          <- refactor to async
neurocnl/backend/app/main.py                      <- mount jobs router
neurocnl/backend/tests/test_simulate_router.py    <- update
```

---

### TASK-11 · Backend: Add request_id Middleware
*(Was: Maintenance TASK-08)*

**Priority:** High
**Effort:** Small

**Spec:**
Add middleware that:
1. Reads `X-Request-ID` from incoming request header (or generates `uuid4`).
2. Attaches to `request.state.request_id`.
3. Adds `X-Request-ID` to response headers.

Update all Pydantic response schemas to include `request_id: str | None = None`.
Populate in each router from `request.state.request_id`.

**Acceptance Criteria:**
- Every response body contains `request_id`.
- Every response has `X-Request-ID` header.
- Client-sent `X-Request-ID` is echoed back.
- All router tests verify `request_id` presence.

**Files Affected:**
```
neurocnl/backend/app/middleware/request_id.py    <- new
neurocnl/backend/app/main.py                     <- add middleware
neurocnl/backend/app/schemas/*.py                <- add request_id
neurocnl/backend/app/routers/*.py                <- populate request_id
neurocnl/backend/tests/                          <- update assertions
```

---

### TASK-12 · Backend: Improve /health Endpoint
*(Was: Maintenance TASK-16 + Backend Integration Phase 6 health check, merged)*

**Priority:** High
**Effort:** Small

**Spec:**
Extend `/health` to verify runtime dependencies and report optional capabilities:

```python
@app.get("/health")
async def health():
    result = {
        "status": "ok",
        "neurocnl_version": neurocnl.__version__,
        "timestamp": datetime.utcnow().isoformat(),
    }
    try:
        import nengo
        result["nengo_version"] = nengo.__version__
    except ImportError:
        result["status"] = "degraded"
        result["nengo_available"] = False

    try:
        import mujoco
        result["mujoco_available"] = True
        result["mujoco_version"] = mujoco.__version__
    except ImportError:
        result["mujoco_available"] = False

    return result
```

Return 503 if Nengo is unavailable (core dependency). MuJoCo being absent is not degraded — it's optional.

**Acceptance Criteria:**
- `GET /health` returns 200 with `nengo_version`, `neurocnl_version`, `mujoco_available`.
- If Nengo is missing, returns 503 with `"status": "degraded"`.
- Tests cover both 200 and 503 cases.

**Files Affected:**
```
neurocnl/backend/app/main.py (or routers/health.py)
neurocnl/backend/tests/test_health.py
```

---

### TASK-13 · Frontend: Externalize API Base URL
*(Was: Maintenance TASK-18)*

**Priority:** High
**Effort:** Small

**Spec:**
Replace the hardcoded API base URL in `services/api_client.dart` with `--dart-define` config:

```dart
// lib/config/app_config.dart
class AppConfig {
  static const apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:8000',
  );
}
```

Update `api_client.dart` to use `AppConfig.apiBaseUrl`.
Update `frontend/Dockerfile`:
```dockerfile
RUN flutter build web --release \
  --dart-define=API_BASE_URL=${API_BASE_URL:-http://localhost:8000}
```

**Acceptance Criteria:**
- `flutter build web --dart-define=API_BASE_URL=https://api.example.com` produces a build pointing to the correct host.
- Default build points to `http://localhost:8000`.
- No hardcoded URLs remain in `lib/`.

**Files Affected:**
```
neurocnl/frontend/lib/config/app_config.dart    <- new
neurocnl/frontend/lib/services/api_client.dart
neurocnl/frontend/Dockerfile
neurocnl/docker-compose.yml
```

---

## Phase 2 — Backend Integration: Prosthetic Endpoints
> **Goal:** Expose Neuro-Dream-Hand capabilities through the neurocnl backend. No frontend changes yet.

---

### TASK-14 · Backend: Add neurodreamhand Dependency + Shared Infrastructure
*(Was: Backend Integration Phase 1)*

**Priority:** High
**Effort:** Small

**Spec:**
1. Add `neurodreamhand` to `backend/requirements.txt`:
   ```
   neurodreamhand>=0.1.0   # or -e ../../Neuro-Dream-Hand
   ```
   Use optional MuJoCo install:
   ```
   mujoco>=3.1.0; extra == "physics"
   ```

2. Add `neurodreamhand` to FastAPI lifespan context in `backend/app/main.py`:
   ```python
   import neurodreamhand  # validates install at startup
   ```

3. Create `backend/app/routers/prosthetic/` package (empty `__init__.py`).

4. Update `docker-compose.yml` to add a `physics` service profile that installs MuJoCo.

5. Create `docker/Dockerfile.physics` extending the base backend image with MuJoCo.

**Acceptance Criteria:**
- `pip install -r requirements.txt` includes neurodreamhand.
- Backend starts without MuJoCo (import is guarded).
- `docker compose --profile physics up` starts with MuJoCo available.

**Files Affected:**
```
neurocnl/backend/requirements.txt
neurocnl/backend/app/main.py
neurocnl/backend/app/routers/prosthetic/__init__.py   <- new
neurocnl/docker/Dockerfile.physics                     <- new
neurocnl/docker-compose.yml
```

---

### TASK-15 · Backend: CNL Template Expansion
*(Was: Backend Integration Phase 2)*

**Priority:** High
**Effort:** Small

**Spec:**
Expose Neuro-Dream-Hand's `.cnl` specs through the existing `/api/templates` endpoint.

1. Copy `Neuro-Dream-Hand/cnl-specs/reflex_arc.cnl` and `sleep_arc.cnl` into `neurocnl/backend/app/templates/`.
2. Update `backend/app/routers/templates.py` to include two new entries:
   ```python
   {
     "id": "prosthetic_reflex",
     "name": "Prosthetic Reflex Arc",
     "category": "advanced",
     "description": "Slip-velocity PD reflex controller for prosthetic hand grip stabilization",
     "spec": <contents of reflex_arc.cnl>
   },
   {
     "id": "prosthetic_sleep",
     "name": "Prosthetic Sleep Consolidation",
     "category": "advanced",
     "description": "Offline PES replay network for memory consolidation during sleep phases",
     "spec": <contents of sleep_arc.cnl>
   }
   ```

**Acceptance Criteria:**
- `GET /api/templates` returns 8 templates (6 existing + 2 new).
- New templates are parseable by `/api/parse`.
- `test_templates_router.py` updated.

**Files Affected:**
```
neurocnl/backend/app/templates/prosthetic_reflex.cnl   <- new (copied)
neurocnl/backend/app/templates/prosthetic_sleep.cnl    <- new (copied)
neurocnl/backend/app/routers/templates.py
neurocnl/backend/tests/test_templates_router.py
```

---

### TASK-16 · Backend: Drop Test Simulation Endpoint
*(Was: Backend Integration Phase 3)*

**Priority:** High
**Effort:** Medium

**Spec:**
Expose `MuJoCoBridge.run_drop_test()` via REST.

**New endpoint:** `POST /api/prosthetic/simulate`

**Request schema** (`backend/app/schemas/prosthetic.py`):
```python
class ProstheticSimRequest(BaseModel):
    spec: str
    gripper_type: Literal["pinch", "tripod"] = "pinch"
    drop_height: float = 0.15
    duration: float = 2.0
    n_neurons: int = 50
    use_sleep_weights: bool = False
    seed: int = 0
```

**Response schema:**
```python
class ProstheticSimResult(BaseModel):
    success: bool
    grip_history: list[float]
    slip_vz_history: list[float]
    object_z_history: list[float]
    stopping_distance_m: float
    frames: list[str] | None       # base64 PNG if render=True
    wall_time_seconds: float
```

**Service:** `backend/app/services/prosthetic_runner.py`
```python
def run_drop_test(req: ProstheticSimRequest) -> ProstheticSimResult:
    # 1. Parse + validate CNL spec via neurocnl pipeline
    # 2. Load neuron params via neurodreamhand.core.cnl_integration
    # 3. Instantiate SNNController
    # 4. Instantiate MuJoCoBridge (PinchBridge or TripodBridge)
    # 5. Run bridge.run_drop_test()
    # 6. Return result
```

**Router:** `backend/app/routers/prosthetic/simulate.py`
- Duration capped at `MAX_DURATION = 10.0`.
- Uses the job system from TASK-10: if `duration > 5.0`, returns 202 + job_id; client polls `GET /api/jobs/{job_id}`.
- If `duration <= 5.0`, runs synchronously and returns result directly.

**Acceptance Criteria:**
- `POST /api/prosthetic/simulate` with a valid spec returns grip/slip/object histories.
- Long simulations return 202 and are retrievable via job polling.
- MuJoCo unavailability returns 503 with clear error.
- Tests with mocked MuJoCo pass.

**Files Affected:**
```
neurocnl/backend/app/routers/prosthetic/simulate.py    <- new
neurocnl/backend/app/schemas/prosthetic.py              <- new
neurocnl/backend/app/services/prosthetic_runner.py      <- new
neurocnl/backend/app/main.py                            <- mount router
neurocnl/backend/tests/test_prosthetic_simulate.py      <- new
```

---

### TASK-17 · Backend: Sleep Training Endpoint
*(Was: Backend Integration Phase 4)*

**Priority:** High
**Effort:** Medium

**Spec:**
Expose `SleepOptimizer` via REST.

**New endpoint:** `POST /api/prosthetic/sleep`

**Request:**
```python
class SleepTrainRequest(BaseModel):
    spec: str
    memory_buffer: list[dict]     # [{"slip_vz": float, "grip": float, "error": float}, ...]
    n_epochs: int = 10
    homeostasis_factor: float = 0.01
```

**Response:**
```python
class SleepTrainResult(BaseModel):
    loss_curve: list[float]
    n_epochs: int
    final_loss: float
    learned_weights: list[list[float]]    # serialized decoder matrix
```

**Service:** `backend/app/services/sleep_runner.py`
- Uses job system from TASK-10 for long training runs.

**Acceptance Criteria:**
- `POST /api/prosthetic/sleep` with spec + memory buffer returns loss curve and learned weights.
- Long training (> 10 epochs) runs as background job.
- Tests with mocked SleepOptimizer pass.

**Files Affected:**
```
neurocnl/backend/app/routers/prosthetic/sleep.py     <- new
neurocnl/backend/app/services/sleep_runner.py         <- new
neurocnl/backend/app/schemas/prosthetic.py            <- add SleepTrainRequest/Result
neurocnl/backend/tests/test_prosthetic_sleep.py       <- new
```

---

### TASK-18 · Backend: Hardware Export Endpoint
*(Was: Backend Integration Phase 5)*

**Priority:** High
**Effort:** Small

**Spec:**
Expose `CrossbarExporter` for HDF5 weight export.

**New endpoint:** `POST /api/prosthetic/export/crossbar`

**Request:**
```python
class CrossbarExportRequest(BaseModel):
    learned_weights: list[list[float]]     # from SleepTrainResult
    bit_width: int = 8                     # 4 or 8
    format: Literal["hdf5", "json"] = "json"
```

**Response:**
- `format="json"`: returns quantized weight matrix + quantization stats inline.
- `format="hdf5"`: returns file download (`application/x-hdf5`).

**Acceptance Criteria:**
- JSON export returns quantized weights with stats.
- HDF5 export returns a downloadable file.
- Tests cover both formats.

**Files Affected:**
```
neurocnl/backend/app/routers/prosthetic/export.py    <- new
neurocnl/backend/app/schemas/prosthetic.py           <- add CrossbarExportRequest
neurocnl/backend/tests/test_prosthetic_export.py     <- new
```

---

### TASK-19 · Backend: Extended Prosthetic Endpoints (Energy, Quantization, Hardware)
*(Was: Frontend Integration Phase 1 extra endpoints not covered by backend plan)*

**Priority:** Medium
**Effort:** Medium

**Spec:**
Add the remaining endpoints needed by the frontend's Analysis and Hardware screens:

| Endpoint | Method | Purpose |
|---|---|---|
| `/api/prosthetic/energy` | POST | Run energy profiling on a CNL spec |
| `/api/prosthetic/quantize` | POST | Weight quantization analysis (4-8 bit) |
| `/api/prosthetic/hardware/serial` | GET | List available serial ports |
| `/api/prosthetic/hardware/connect` | POST | Open serial connection to Teensy |
| `/api/prosthetic/hardware/disconnect` | POST | Close serial connection |
| `/api/prosthetic/hardware/stream` | GET (SSE) | Stream live hardware sensor data |

**Implementation notes:**
- Energy profiling wraps `neurodreamhand.analytics.energy_profiler`.
- Quantization wraps `neurodreamhand.analytics.quantization`.
- Hardware endpoints wrap `neurodreamhand.hardware.serial_bridge` and `emg_streamer`.
- SSE streaming uses `sse-starlette`.
- Serial port config reads from environment variables (see TASK-22).

**Acceptance Criteria:**
- All endpoints return correct schemas.
- Hardware endpoints return 503 when no device is connected (mocked in tests).
- SSE stream sends correctly formatted events.

**Files Affected:**
```
neurocnl/backend/app/routers/prosthetic/analysis.py    <- new
neurocnl/backend/app/routers/prosthetic/hardware.py    <- new
neurocnl/backend/app/services/energy_service.py        <- new
neurocnl/backend/app/services/hardware_service.py      <- new
neurocnl/backend/app/schemas/prosthetic.py             <- add schemas
neurocnl/backend/requirements.txt                      <- add sse-starlette
neurocnl/backend/tests/test_prosthetic_analysis.py     <- new
neurocnl/backend/tests/test_prosthetic_hardware.py     <- new
```

---

### TASK-20 · Backend: Mount All Routers + OpenAPI Tags
*(Was: Backend Integration Phase 6)*

**Priority:** High (must follow TASK-16 through TASK-19)
**Effort:** Small

**Spec:**
Update `backend/app/main.py` to mount all prosthetic routers:

```python
from app.routers.prosthetic import simulate as prosthetic_sim
from app.routers.prosthetic import sleep as prosthetic_sleep
from app.routers.prosthetic import export as prosthetic_export
from app.routers.prosthetic import analysis as prosthetic_analysis
from app.routers.prosthetic import hardware as prosthetic_hardware

app.include_router(prosthetic_sim.router,      prefix="/api/prosthetic", tags=["prosthetic"])
app.include_router(prosthetic_sleep.router,     prefix="/api/prosthetic", tags=["prosthetic"])
app.include_router(prosthetic_export.router,    prefix="/api/prosthetic", tags=["prosthetic"])
app.include_router(prosthetic_analysis.router,  prefix="/api/prosthetic", tags=["prosthetic"])
app.include_router(prosthetic_hardware.router,  prefix="/api/prosthetic", tags=["prosthetic"])
```

**Final API Surface:**
```
# Existing (neurocnl)
GET  /health
GET  /api/templates
POST /api/parse
POST /api/validate
POST /api/generate
POST /api/simulate
POST /api/export
GET  /api/jobs/{job_id}

# New (prosthetic)
POST /api/prosthetic/simulate
POST /api/prosthetic/sleep
POST /api/prosthetic/export/crossbar
POST /api/prosthetic/energy
POST /api/prosthetic/quantize
GET  /api/prosthetic/hardware/serial
POST /api/prosthetic/hardware/connect
POST /api/prosthetic/hardware/disconnect
GET  /api/prosthetic/hardware/stream
```

**Acceptance Criteria:**
- All routers are mounted and accessible.
- OpenAPI docs at `/docs` show prosthetic endpoints grouped under `prosthetic` tag.
- Integration test hits each endpoint with TestClient.

**Files Affected:**
```
neurocnl/backend/app/main.py
```

---

## Phase 3 — Frontend Integration: New Screens & Navigation
> **Goal:** Extend the Flutter app to consume the new prosthetic backend endpoints.

---

### TASK-21 · Frontend: Add go_router + NavigationRail
*(Was: Maintenance TASK-17 + Frontend Integration Phase 2a, merged)*

**Priority:** High
**Effort:** Medium

**Spec:**
Replace implicit navigation with `go_router` and add a persistent side NavigationRail:

```
NavigationRail (left sidebar)
  |-- Studio          <- existing neurocnl IDE (unchanged)
  |-- Deploy          <- new: prosthetic control panel
  |-- Hardware        <- new: live hardware monitor
  |-- Analysis        <- new: energy, quantization, fault injection
```

On mobile, this becomes a bottom navigation bar.

1. Add `go_router: ^14.0.0` to `pubspec.yaml`.
2. Define `AppRouter` in `lib/routing/app_router.dart` with routes:
   - `/` -> `StudioScreen`
   - `/deploy` -> `DeployScreen`
   - `/hardware` -> `HardwareScreen`
   - `/analysis` -> `AnalysisScreen`
   - `/demo/:templateId` -> `StudioScreen` with pre-loaded template
3. Replace `Navigator.push()` calls with `context.go()`.
4. Add 404 error screen.
5. NavigationRail shows Deploy/Hardware/Analysis grayed out unless `/health` reports `mujoco_available: true`.

**Acceptance Criteria:**
- `flutter analyze` passes.
- Deep links work: `/demo/slip_reflex` pre-loads template.
- Back button behavior unchanged.
- Navigation items are conditionally enabled based on health check.

**Files Affected:**
```
neurocnl/frontend/pubspec.yaml
neurocnl/frontend/lib/routing/app_router.dart       <- new
neurocnl/frontend/lib/app.dart                      <- NavigationRail + router
neurocnl/frontend/lib/screens/**/*.dart             <- replace Navigator calls
```

---

### TASK-22 · Frontend: New Models + API Client Extension
*(Was: Frontend Integration Phase 2e-f)*

**Priority:** High
**Effort:** Medium

**Spec:**
Add Dart models and API client methods for all prosthetic endpoints.

**New models** (`lib/models/`):
```
ndh_health.dart              # mujoco_available, version
controller_session.dart
simulation_frame.dart        # joint_angles[], spike_data, timestamp
sensor_frame.dart            # EMG channels, EEG bands, proximity
learn_config.dart            # mode, duration, learning_rate
learn_result.dart            # weight_deltas, loss_curve
energy_report.dart           # per_ensemble_pj, total_pj
quantization_report.dart     # bit_widths[], accuracy_drops[]
```

**New API client methods** (added to `services/api_client.dart`):
```dart
Future<ProstheticSimResult> prostheticSimulate(ProstheticSimRequest req)
Future<SleepTrainResult> prostheticSleep(SleepTrainRequest req)
Future<dynamic> prostheticExportCrossbar(CrossbarExportRequest req)
Future<EnergyReport> prostheticEnergy(String spec)
Future<QuantizationReport> prostheticQuantize(String spec, List<int> bits)
Future<List<String>> listSerialPorts()
Future<void> connectHardware(String port, int baudRate)
Future<void> disconnectHardware()
Stream<SensorFrame> streamHardware()         // SSE
Future<JobStatus> getJobStatus(String jobId)  // for polling async jobs
```

Add `web_socket_channel: ^2.4.0` to `pubspec.yaml` for SSE streams.

**Acceptance Criteria:**
- All models have `fromJson` / `toJson` with round-trip tests.
- API client methods correctly call backend endpoints.
- SSE stream properly deserializes `SensorFrame` events.

**Files Affected:**
```
neurocnl/frontend/lib/models/*.dart              <- new files
neurocnl/frontend/lib/services/api_client.dart   <- extend
neurocnl/frontend/pubspec.yaml                   <- add web_socket_channel
neurocnl/frontend/test/model/*.dart              <- new tests
```

---

### TASK-23 · Frontend: New Providers
*(Was: Frontend Integration Phase 2c)*

**Priority:** High
**Effort:** Medium

**Spec:**
Create Riverpod providers following the existing `AsyncNotifier` / `riverpod_annotation` pattern:

```
lib/providers/
  ndh_controller_provider.dart       # SNNController session state
  simulation_stream_provider.dart    # SSE stream for MuJoCo frames
  hardware_provider.dart             # Serial connection state + live sensor data
  learning_provider.dart             # Learning mode config + trigger + results
  analysis_provider.dart             # Energy / quantization results
```

Each provider:
- Exposes loading/error/data states.
- Uses the extended `ApiClient` from TASK-22.
- Handles job polling for async operations (simulate, sleep).

**Acceptance Criteria:**
- All providers compile and pass unit tests with mocked ApiClient.
- Loading/error/data state transitions are tested.

**Files Affected:**
```
neurocnl/frontend/lib/providers/*.dart     <- new files
neurocnl/frontend/test/unit/providers/*.dart  <- new tests
```

---

### TASK-24 · Frontend: Deploy Screen
*(Was: Frontend Integration Phase 2b — Deploy Screen)*

**Priority:** High
**Effort:** Medium

**Spec:**
Create `screens/deploy_screen.dart` with tabs:

- **Simulation** — Launch MuJoCo + Nengo co-simulation from the CNL spec currently open in Studio. Shows streamed video feed (MJPEG frames from backend) alongside a live spike raster (reuse `SimulationDashboard` widget).
- **Learning** — Configure and trigger learning: select mode (STDP / PES / OCL), set duration, view weight delta heatmap after training.
- **Export** — Loihi 2 HDF5 export, Nengo code export.

**New widgets:**
- `MujocoStreamView` — renders MJPEG frames from SSE stream.
- `LearningConfigPanel` — reuses `ParameterExplorer` pattern for learning mode selection.

**Acceptance Criteria:**
- Simulation tab streams frames and shows spike raster when backend is available.
- Learning tab triggers training and displays loss curve.
- Export tab downloads HDF5 file.
- All tabs show appropriate loading/error states.
- Widget tests pass.

**Files Affected:**
```
neurocnl/frontend/lib/screens/deploy_screen.dart         <- new
neurocnl/frontend/lib/widgets/mujoco_stream_view.dart    <- new
neurocnl/frontend/lib/widgets/learning_config_panel.dart <- new
```

---

### TASK-25 · Frontend: Hardware Screen
*(Was: Frontend Integration Phase 2b — Hardware Screen)*

**Priority:** Medium
**Effort:** Medium

**Spec:**
Create `screens/hardware_screen.dart`:

- Serial port selector (dropdown from `/api/prosthetic/hardware/serial`)
- Connect / Disconnect button
- Live sensor stream panel: EMG channels, EEG bands, proximity, tactile — scrolling time-series charts (reuse spike chart widget pattern)
- Motor output panel: servo positions (commanded vs actual)
- Emergency stop button

**New widgets:**
- `SensorTimeSeriesChart` — reuses `SimulationDashboard` spike chart logic.
- `SerialPortSelector` — reuses `TemplateGallery` dropdown pattern.

**Acceptance Criteria:**
- Port selector populates from backend.
- Connect/Disconnect toggles state correctly.
- Live stream renders sensor data as time-series.
- Emergency stop sends disconnect immediately.
- Widget tests pass.

**Files Affected:**
```
neurocnl/frontend/lib/screens/hardware_screen.dart              <- new
neurocnl/frontend/lib/widgets/sensor_time_series_chart.dart     <- new
neurocnl/frontend/lib/widgets/serial_port_selector.dart         <- new
```

---

### TASK-26 · Frontend: Analysis Screen
*(Was: Frontend Integration Phase 2b — Analysis Screen)*

**Priority:** Medium
**Effort:** Medium

**Spec:**
Create `screens/analysis_screen.dart` with tabs:

- **Energy Profiling** — Bar chart of pJ/spike per ensemble; total energy estimate.
- **Quantization** — Run 4/6/8-bit weight quantization; show accuracy vs bit-width tradeoff curve.
- **Fault Injection** — Configure dead neurons / stuck-at faults; compare simulation output before and after.

**New widgets:**
- `EnergyBarChart` — reuses `ParseResultsTable` layout pattern.
- `QuantizationCurveChart` — reuses `NetworkGraphView` canvas wrapper.

**Acceptance Criteria:**
- Energy profiling shows per-ensemble breakdown.
- Quantization shows accuracy vs bit-width curve.
- Fault injection shows before/after comparison.
- Widget tests pass.

**Files Affected:**
```
neurocnl/frontend/lib/screens/analysis_screen.dart             <- new
neurocnl/frontend/lib/widgets/energy_bar_chart.dart            <- new
neurocnl/frontend/lib/widgets/quantization_curve_chart.dart    <- new
```

---

### TASK-27 · Frontend: Extended Pipeline Bar
*(Was: Frontend Integration Phase 3)*

**Priority:** Medium
**Effort:** Small

**Spec:**
Extend the `PipelineBar` widget from:
```
Parse -> Validate -> Generate -> Simulate
```
to:
```
Parse -> Validate -> Generate -> Simulate -> Deploy -> Hardware
```

The last two steps are grayed out unless the health check reports `mujoco_available: true`. Clicking Deploy navigates to `/deploy`; clicking Hardware navigates to `/hardware`.

**Acceptance Criteria:**
- Pipeline bar shows 6 steps.
- Deploy/Hardware steps are disabled when MuJoCo is unavailable.
- Clicking enabled Deploy/Hardware navigates correctly.
- Widget tests updated.

**Files Affected:**
```
neurocnl/frontend/lib/widgets/pipeline_bar.dart
neurocnl/frontend/test/widget/widgets/pipeline_bar_test.dart
```

---

### TASK-28 · Frontend: Template Gallery Deep Link to Hardware Config
*(Was: Frontend Integration Phase 4)*

**Priority:** Medium
**Effort:** Small

**Spec:**
When a user selects a template (e.g., `emg_gripper`) in the `TemplateGallery`, populate not just the CNL editor but also pre-fill the Deploy screen's hardware config:
- Serial baud rate
- EMG channel count
- Learning mode default
- Simulation duration

Store template-to-hardware-config mapping as a static map in the template model.

**Acceptance Criteria:**
- Selecting `emg_gripper` template pre-fills Deploy screen with correct EMG config.
- Selecting `prosthetic_reflex` pre-fills correct simulation params.
- Pre-fill values are overridable by the user.

**Files Affected:**
```
neurocnl/frontend/lib/widgets/template_gallery.dart
neurocnl/frontend/lib/models/template.dart
neurocnl/frontend/lib/providers/ndh_controller_provider.dart
```

---

## Phase 4 — Security, Infrastructure & Polish
> **Goal:** Harden for production readiness.

---

### TASK-29 · Docker: Add Non-Root USER
*(Was: Maintenance TASK-13)*

**Priority:** Medium
**Effort:** Small

**Spec:**
Both Dockerfiles run as root. Fix:

Backend Dockerfile:
```dockerfile
RUN addgroup --system app && adduser --system --ingroup app app
USER app
```

Frontend Dockerfile: use `nginxinc/nginx-unprivileged` as base.

**Acceptance Criteria:**
- `docker inspect <container> | grep User` shows non-root.
- Both containers start and serve traffic correctly.
- `docker-compose up` works end-to-end.

**Files Affected:**
```
neurocnl/backend/Dockerfile
neurocnl/frontend/Dockerfile
```

---

### TASK-30 · Backend: Rate Limit /api/simulate and Prosthetic Endpoints
*(Was: Maintenance TASK-14, expanded scope)*

**Priority:** Medium
**Effort:** Small

**Spec:**
Add `slowapi` rate limiting:

- `/api/simulate`: 10/minute per IP
- `/api/prosthetic/simulate`: 10/minute per IP
- `/api/prosthetic/sleep`: 5/minute per IP
- `/api/prosthetic/export/crossbar`: 20/minute per IP

Return HTTP 429 with `Retry-After` header on violation.

**Acceptance Criteria:**
- Rate limits enforced per-endpoint.
- 429 responses include `Retry-After` header.
- Tests verify 429 behavior.

**Files Affected:**
```
neurocnl/backend/app/main.py
neurocnl/backend/app/routers/simulate.py
neurocnl/backend/app/routers/prosthetic/*.py
neurocnl/backend/requirements.txt              <- add slowapi
neurocnl/backend/tests/test_rate_limit.py      <- new
```

---

### TASK-31 · Neuro-Dream-Hand: Externalize Serial Port Config
*(Was: Maintenance TASK-15)*

**Priority:** Medium
**Effort:** Small

**Spec:**
Move serial port path and baud rate to environment variables:

```python
import os
SERIAL_PORT = os.environ.get("NDH_SERIAL_PORT", "/dev/ttyACM0")
SERIAL_BAUD = int(os.environ.get("NDH_SERIAL_BAUD", "115200"))
```

Add `.env.example`:
```
NDH_SERIAL_PORT=/dev/ttyACM0
NDH_SERIAL_BAUD=115200
NDH_MUJOCO_GL=egl
NDH_LOG_LEVEL=INFO
```

Add `.env` to `.gitignore`.

**Acceptance Criteria:**
- `serial_bridge.py` reads port/baud from environment.
- `.env.example` committed; `.env` gitignored.
- Tests pass without setting env vars (defaults used).

**Files Affected:**
```
Neuro-Dream-Hand/neurodreamhand/hardware/serial_bridge.py
Neuro-Dream-Hand/neurodreamhand/hardware/emg_streamer.py
Neuro-Dream-Hand/.env.example          <- new
Neuro-Dream-Hand/.gitignore
```

---

### TASK-32 · Add pip-compile Lockfiles
*(Was: Maintenance TASK-19)*

**Priority:** Low
**Effort:** Small

**Spec:**
Add `pip-tools` lockfiles for reproducible installs.

Rename `requirements.txt` -> `requirements.in` (source), generate `requirements.txt` (lockfile) via `pip-compile`.

Add CI check:
```yaml
- name: Check lockfile
  run: pip-compile --dry-run requirements.in | diff - requirements.txt
```

**Acceptance Criteria:**
- `pip install -r requirements.txt` produces identical environment across machines.
- CI fails if lockfile is out of sync.

**Files Affected:**
```
Neuro-Dream-Hand/requirements.in        <- rename
Neuro-Dream-Hand/requirements.txt       <- regenerated
neurocnl/backend/requirements.in        <- new
neurocnl/backend/requirements.txt       <- regenerated
.github/workflows/python_ci.yml        <- add check
```

---

### TASK-33 · Add Coverage Reporting to CI
*(Was: Maintenance TASK-20)*

**Priority:** Low
**Effort:** Small

**Spec:**
Add `pytest-cov` to both Python projects. Upload coverage XML via `codecov/codecov-action@v4`. Set `fail_under = 60` as a warning threshold.

**Acceptance Criteria:**
- Coverage XML uploaded on every CI run.
- Coverage below 60% triggers CI warning.

**Files Affected:**
```
Neuro-Dream-Hand/pyproject.toml
neurocnl/pyproject.toml
.github/workflows/python_ci.yml
```

---

### TASK-34 · Add SECURITY.md to Both Projects
*(Was: Maintenance TASK-21)*

**Priority:** Low
**Effort:** Very Small

**Spec:**
Create `SECURITY.md` in each project root with supported versions, vulnerability reporting instructions, expected response time, and out-of-scope items.

**Acceptance Criteria:**
- `SECURITY.md` exists in both roots.
- GitHub security tab detects the policy.

**Files Affected:**
```
Neuro-Dream-Hand/SECURITY.md   <- new
neurocnl/SECURITY.md           <- new
```

---

## Execution Order & Dependency Graph

```
PHASE 0 — Foundation (Code Quality)
  TASK-01 (NDH pyproject.toml)  ─────────────────────────────────────┐
  TASK-02 (ruff + logging) ──────────────────────────────────────┐   |
  TASK-03 (mypy) ── depends on TASK-02 ─────────────────────┐   |   |
  TASK-04 (TypedDict) ── depends on TASK-03 ────────────┐   |   |   |
  TASK-05 (pipeline collapse) ── depends on TASK-04 ─┐  |   |   |   |
  TASK-06 (Flutter analysis_options) ──── parallel ───┤  |   |   |   |
  TASK-07 (Backend tests) ── depends on TASK-05 ─────┤  |   |   |   |
  TASK-08 (Flutter tests) ── depends on TASK-06 ─────┤  |   |   |   |
  TASK-09 (CI workflows) ── depends on TASK-02..08 ──┘  |   |   |   |
                                                         |   |   |   |
PHASE 1 — Backend Architecture                          |   |   |   |
  TASK-10 (job system) ── depends on TASK-07 ────────┤  |   |   |   |
  TASK-11 (request_id) ────── parallel ──────────────┤  |   |   |   |
  TASK-12 (health endpoint) ── parallel ─────────────┤  |   |   |   |
  TASK-13 (externalize API URL) ── parallel ─────────┘  |   |   |   |
                                                         |   |   |   |
PHASE 2 — Backend Integration                           |   |   |   |
  TASK-14 (add NDH dep) ── depends on TASK-01,10 ───┐   |   |   |   |
  TASK-15 (templates) ── depends on TASK-14 ────────┤   |   |   |   |
  TASK-16 (prosthetic/simulate) ── depends on 14 ───┤   |   |   |   |
  TASK-17 (prosthetic/sleep) ── depends on 16 ──────┤   |   |   |   |
  TASK-18 (prosthetic/export) ── depends on 17 ─────┤   |   |   |   |
  TASK-19 (energy/hardware endpoints) ── depends 14 ┤   |   |   |   |
  TASK-20 (mount all routers) ── depends on 15-19 ──┘   |   |   |   |
                                                         |   |   |   |
PHASE 3 — Frontend Integration                          |   |   |   |
  TASK-21 (go_router + NavRail) ── depends on 13,20 ┐   |   |   |   |
  TASK-22 (models + API client) ── depends on 20 ───┤   |   |   |   |
  TASK-23 (providers) ── depends on 22 ─────────────┤   |   |   |   |
  TASK-24 (Deploy screen) ── depends on 23 ─────────┤   |   |   |   |
  TASK-25 (Hardware screen) ── depends on 23 ── parallel with 24   |
  TASK-26 (Analysis screen) ── depends on 23 ── parallel with 24  |
  TASK-27 (pipeline bar) ── depends on 21 ──────────┤   |   |   |   |
  TASK-28 (template deep link) ── depends on 23 ────┘   |   |   |   |
                                                         |   |   |   |
PHASE 4 — Security & Polish                             |   |   |   |
  TASK-29 (Docker non-root) ───── independent ──────┐   |   |   |   |
  TASK-30 (rate limiting) ── depends on TASK-20 ────┤   |   |   |   |
  TASK-31 (serial port env vars) ── depends on 01 ──┤   |   |   |   |
  TASK-32 (pip-compile lockfiles) ── independent ───┤   |   |   |   |
  TASK-33 (coverage reporting) ── depends on 09 ────┤   |   |   |   |
  TASK-34 (SECURITY.md) ── independent ─────────────┘   |   |   |   |
```

---

## Parallelism Opportunities

Tasks that can run **concurrently** within each phase:

| Phase | Parallel Groups |
|---|---|
| **Phase 0** | {TASK-01} \|\| {TASK-02 -> TASK-03 -> TASK-04 -> TASK-05} \|\| {TASK-06 -> TASK-08}. TASK-07 starts after TASK-05. TASK-09 waits for all. |
| **Phase 1** | {TASK-10} \|\| {TASK-11} \|\| {TASK-12} \|\| {TASK-13} — all independent. |
| **Phase 2** | TASK-14 first. Then {TASK-15} \|\| {TASK-16} \|\| {TASK-19}. TASK-17 after 16. TASK-18 after 17. TASK-20 last. |
| **Phase 3** | {TASK-21} \|\| {TASK-22} first. Then TASK-23. Then {TASK-24} \|\| {TASK-25} \|\| {TASK-26} \|\| {TASK-27}. TASK-28 last. |
| **Phase 4** | All tasks are independent — full parallelism. |

---

## What NOT to Change

- **Neuro-Dream-Hand CLI scripts** (`scripts/step*.py`) — keep as standalone tutorials; do not port to API.
- **Existing `StudioScreen`** and its 5 tabs — stable, do not refactor as part of integration.
- **neurocnl core library** (`neurocnl/neurocnl/`) — remains general-purpose and physics-agnostic (except TypedDict and pipeline collapse from Phase 0).
- **Neuro-Dream-Hand library internals** — only a thin API wrapper is added on top.
- **servo_control Arduino project** — managed separately.
- **EMG / serial bridge hardware** — exposed via API but not restructured internally.
- **Publication analytics** (`analytics/telemetry.py`) — keep as offline post-processing.

---

## Task Summary Table

| # | Task | Project | Priority | Effort | Phase | Supersedes |
|---|------|---------|----------|--------|-------|------------|
| 01 | NDH: Migrate to pyproject.toml | NDH | Critical | Small | 0 | Maint-11 |
| 02 | Both Python: ruff + logging | Both Python | Critical | Small | 0 | Maint-05, Maint-12 |
| 03 | Both Python: mypy | Both Python | Critical | Medium | 0 | Maint-06 |
| 04 | neurocnl: TypedDict for parser | Library | Critical | Small | 0 | Maint-09 |
| 05 | neurocnl: Collapse pipeline | Library + Backend | Critical | Small | 0 | Maint-10 |
| 06 | Flutter: analysis_options.yaml | Frontend | Critical | Small | 0 | Maint-03 |
| 07 | Backend: API endpoint tests | Backend | Critical | Medium | 0 | Maint-04 |
| 08 | Flutter: Widget & unit tests | Frontend | Critical | Medium | 0 | Maint-01 |
| 09 | CI: Unified workflows | CI/CD | Critical | Small | 0 | Maint-02, Maint-05/06 CI |
| 10 | Backend: Job system + async sim | Backend | High | Medium | 1 | Maint-07 |
| 11 | Backend: request_id middleware | Backend | High | Small | 1 | Maint-08 |
| 12 | Backend: Improve /health | Backend | High | Small | 1 | Maint-16 + BE-Phase6 health |
| 13 | Frontend: Externalize API URL | Frontend | High | Small | 1 | Maint-18 |
| 14 | Backend: Add NDH dependency | Backend | High | Small | 2 | BE-Phase1 |
| 15 | Backend: CNL template expansion | Backend | High | Small | 2 | BE-Phase2 |
| 16 | Backend: Prosthetic simulate | Backend | High | Medium | 2 | BE-Phase3 |
| 17 | Backend: Sleep training | Backend | High | Medium | 2 | BE-Phase4 |
| 18 | Backend: Hardware export | Backend | High | Small | 2 | BE-Phase5 |
| 19 | Backend: Energy/quantize/hardware | Backend | Medium | Medium | 2 | FE-Phase1 extras |
| 20 | Backend: Mount routers + OpenAPI | Backend | High | Small | 2 | BE-Phase6 |
| 21 | Frontend: go_router + NavRail | Frontend | High | Medium | 3 | Maint-17 + FE-Phase2a |
| 22 | Frontend: Models + API client | Frontend | High | Medium | 3 | FE-Phase2e-f |
| 23 | Frontend: Providers | Frontend | High | Medium | 3 | FE-Phase2c |
| 24 | Frontend: Deploy screen | Frontend | High | Medium | 3 | FE-Phase2b (Deploy) |
| 25 | Frontend: Hardware screen | Frontend | Medium | Medium | 3 | FE-Phase2b (Hardware) |
| 26 | Frontend: Analysis screen | Frontend | Medium | Medium | 3 | FE-Phase2b (Analysis) |
| 27 | Frontend: Extended pipeline bar | Frontend | Medium | Small | 3 | FE-Phase3 |
| 28 | Frontend: Template deep link | Frontend | Medium | Small | 3 | FE-Phase4 |
| 29 | Docker: Non-root USER | Infra | Medium | Small | 4 | Maint-13 |
| 30 | Backend: Rate limiting | Backend | Medium | Small | 4 | Maint-14 |
| 31 | NDH: Externalize serial config | NDH | Medium | Small | 4 | Maint-15 |
| 32 | pip-compile lockfiles | Both Python | Low | Small | 4 | Maint-19 |
| 33 | Coverage reporting | Both Python | Low | Small | 4 | Maint-20 |
| 34 | SECURITY.md | Both | Low | Very Small | 4 | Maint-21 |

---

## Traceability: Original Plan -> This Plan

| Original Document | Original Item | Mapped To |
|---|---|---|
| **Maintenance** TASK-01 | Flutter widget/unit tests | TASK-08 |
| **Maintenance** TASK-02 | Flutter CI workflow | TASK-09 |
| **Maintenance** TASK-03 | Flutter analysis_options | TASK-06 |
| **Maintenance** TASK-04 | Backend API tests | TASK-07 |
| **Maintenance** TASK-05 | ruff + CI | TASK-02 |
| **Maintenance** TASK-06 | mypy + CI | TASK-03 |
| **Maintenance** TASK-07 | Background simulation | TASK-10 |
| **Maintenance** TASK-08 | request_id middleware | TASK-11 |
| **Maintenance** TASK-09 | TypedDict parser output | TASK-04 |
| **Maintenance** TASK-10 | Collapse pipeline | TASK-05 |
| **Maintenance** TASK-11 | pyproject.toml migration | TASK-01 |
| **Maintenance** TASK-12 | Replace print with logging | TASK-02 (merged) |
| **Maintenance** TASK-13 | Docker non-root | TASK-29 |
| **Maintenance** TASK-14 | Rate limiting | TASK-30 |
| **Maintenance** TASK-15 | Serial port config | TASK-31 |
| **Maintenance** TASK-16 | Improve /health | TASK-12 (merged) |
| **Maintenance** TASK-17 | go_router | TASK-21 (merged) |
| **Maintenance** TASK-18 | Externalize API URL | TASK-13 |
| **Maintenance** TASK-19 | pip-compile lockfiles | TASK-32 |
| **Maintenance** TASK-20 | Coverage reporting | TASK-33 |
| **Maintenance** TASK-21 | SECURITY.md | TASK-34 |
| **Backend** Phase 1 | Shared infrastructure | TASK-14 |
| **Backend** Phase 2 | Template expansion | TASK-15 |
| **Backend** Phase 3 | Drop test endpoint | TASK-16 |
| **Backend** Phase 4 | Sleep training endpoint | TASK-17 |
| **Backend** Phase 5 | Hardware export endpoint | TASK-18 |
| **Backend** Phase 6 | Router registration | TASK-20 |
| **Frontend** Phase 1 | Build NDH REST API | Rejected (absorbed into backend integration) |
| **Frontend** Phase 2a | Navigation restructure | TASK-21 (merged with go_router) |
| **Frontend** Phase 2b | Deploy/Hardware/Analysis screens | TASK-24, TASK-25, TASK-26 |
| **Frontend** Phase 2c | Providers | TASK-23 |
| **Frontend** Phase 2d | Widgets | Distributed across TASK-24, 25, 26 |
| **Frontend** Phase 2e | API client extension | TASK-22 |
| **Frontend** Phase 2f | Models | TASK-22 |
| **Frontend** Phase 3 | Pipeline bar extension | TASK-27 |
| **Frontend** Phase 4 | Template deep link | TASK-28 |
