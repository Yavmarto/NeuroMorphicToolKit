# Merge Plan: neurocnl + Neurosim → NeuroStudio

## Context

`Neurosim` imports `neurocnl` as a direct Python library dependency, not over HTTP like every other
module in the suite. This breaks the microservice model the rest of the architecture uses and
creates silent version-coupling: a breaking internal change to `neurocnl` fails `Neurosim` at import
time, not at a versioned API boundary. Beyond the coupling, both modules describe the same user
task — designing a spiking neural network — just through different UX modes: text-based (CNL
editor) and visual (drag-and-drop canvas). There is no meaningful domain boundary between them.

The result of the merge is a single submodule (`neurocnl/`) whose Python library stays named
`neurocnl`, whose FastAPI service now serves both the CNL pipeline and the canvas API at port 8000,
and whose Flutter frontend gains a canvas tab alongside the existing studio tab. Externally, all
HTTP endpoints are preserved. Port 8001 is retired. The `Neurosim` git submodule is archived and
removed from `.gitmodules`.

**Display name in launcher:** "NeuroStudio"  
**Git directory:** unchanged — `neurocnl/`  
**Python package:** unchanged — `neurocnl` (library) + `neurosim` sub-package (moved inside)  
**Port:** 8000 (Neurosim's port 8001 retired)

## Status Update — 2026-05-01 (second pass)

Completed in this pass:

- Phase 1 backend move is started and functionally in place: the Python package, contracts,
  components, templates, and tests from `Neurosim/neurosim/**` now exist under
  `neurocnl/neurosim/**`.
- A compatibility shim now exists at `neurocnl/neurosim/app/main.py` so existing
  `neurosim.app.main` imports resolve to the merged FastAPI app during the transition.
- Phase 2 is implemented: `neurocnl/neurosim/app/services/neurocnl_bridge.py` now imports
  `neurocnl` directly and no longer does dynamic `sys.path` or module bootstrapping.
- Phase 3 is partially implemented: `neurocnl/backend/app/main.py` now includes the Neurosim
  routers, uses a shared limiter that honours `X-Forwarded-For`, accepts both
  `CORS_ALLOWED_ORIGINS` and `ALLOWED_ORIGINS`, restores a root fallback when the frontend is
  absent, extends `/health` with canvas status, and now initializes and closes a shared
  `ProjectStore` during app lifespan.
- Phase 4 is partially implemented: `neurocnl/pyproject.toml` now includes `watchdog`, adds
  `neurosim/tests` to pytest discovery, and enables strict mypy for `neurosim.contracts.*`.
- Phase 5 is started: the current Neurosim Flutter app has been copied into
  `neurocnl/frontend/lib/canvas_app/**` as an embedded subtree, the shared `neurocnl` router now
  exposes `/canvas`, `/canvas/projects`, `/canvas/sweep`, and `/canvas/export`, the outer shell
  now includes a Canvas destination, the canonical canvas route/shell entry files now live under
  `neurocnl/frontend/lib/screens/canvas/**` and `neurocnl/frontend/lib/routing/canvas/**`, and
  the copied canvas API client now defaults to the merged backend at port 8000 (or the current
  web origin). The follow-on normalization passes are now also landed: canvas models now live
  under `neurocnl/frontend/lib/models/canvas/**`, canvas providers under
  `neurocnl/frontend/lib/providers/canvas/**`, shared canvas services under
  `neurocnl/frontend/lib/services/**`, the shared canvas utility helper under
  `neurocnl/frontend/lib/utils/canvas_component_utils.dart`, the remaining canvas-specific widgets
  under `neurocnl/frontend/lib/widgets/canvas/**`, and the embedded NeuroSim shell bootstrap under
  `neurocnl/frontend/lib/routing/canvas/neurosim_app.dart`. The old
  `neurocnl/frontend/lib/canvas_app/**` subtree has now been removed. The inherited canvas typing
  debt that previously blocked `flutter analyze` has also been reduced materially: the dead
  handwritten duplicate graph model is gone, the relocated canvas API client now performs typed
  JSON decoding, the canvas shell adapter imports only the canonical routing files, and the
  remaining analyzer output is now fully clean: `cd neurocnl/frontend && flutter analyze` now
  passes with no findings after the follow-on lint and test-surface cleanup. The shared widget
  smoke coverage for the merged canvas surface is also now broader than the original
  `/canvas/export` check: `neurocnl/frontend/test/widget_test.dart` now exercises the base
  `/canvas` route plus `/canvas/projects` and `/canvas/sweep` inside the shared shell. The
  route/workspace validation is also now deeper than smoke level: the full
  `cd neurocnl/frontend && flutter test` suite is green again, the stale API-client path
  expectations are corrected, and the merged canvas restoration surface now has direct unit
  coverage for `NeurosimRestorationSnapshot` and `NeurosimWorkspaceController` round-trips and
  persisted session hydration. Project workflow validation is also broader than before: the
  merged canvas project browser now has direct widget coverage for listing a saved project,
  loading its details, and pushing its graph into the shared canvas provider through
  `ProjectScreen`.
- Phase 6 is started: the launcher manifest now removes `Neurosim` as a first-class module,
  renames the `neurocnl` entry to `NeuroStudio`, rewrites persisted legacy `Neurosim`
  workspace sessions to `neurocnl` canvas sessions during launcher-control normalization, and
  keeps old launcher-native Neurosim entry points alive as compatibility aliases into
  `neurocnl`'s `/canvas` routes.
- Phase 7 is started: NeuroHub suite-config defaults and suite-client defaults now alias
  `"neurosim"` to the merged backend at port 8000, and the root cross-module integration default
  now points `NEUROSIM_URL` at `http://neurocnl:8000`.
- Phase 6b and follow-on root cleanup are now materially advanced: the active root validation,
  CI, release, integration, and chaos scripts no longer treat `Neurosim` as a standalone service
  or Docker image; monitoring no longer scrapes or tails a separate `neurosim` container; and the
  desktop installer bundles no longer package the standalone `Neurosim/` tree.
- Consumer cleanup outside NeuroHub is now materially advanced: NeuroBench now defaults
  `NEUROSIM_API_URL` to the merged `neurocnl` canvas endpoint, the launcher-side
  `neurosim_feature` package now imports its shell adapter from `neurocnl/frontend`, and active
  root audit / contract workflows no longer schedule a standalone Neurosim verification lane.
- Phase 9 root retirement is now started in-repo: `.gitmodules` no longer registers a standalone
  `Neurosim` submodule, the checked-out `Neurosim/` tree has been removed from the parent repo,
  and active root documentation, verification scripts, suite_api defaults, and GitHub templates
  no longer direct operators toward a separate `Neurosim` checkout or port 8001 service.
- Launcher compatibility coverage is now extended for the merged workspace contract: root
  launcher-control tests now assert that persisted legacy `Neurosim` workspace sessions are
  normalized to the `neurocnl` module id and that old deep links like `/projects` and `/export`
  are rewritten onto the merged `/canvas/*` route family during load and session creation.

Additional work completed in this pass:

- **Handoff port and route fixed**: `neurocnl/frontend/lib/services/neurosim_handoff.dart` now
  targets port 8000 (was 8001) and the `/canvas` route (was `/`). Both `buildDeepLink` and
  `buildTarget` emit correct merged-backend URLs. The corresponding test assertion in
  `test/services/neurosim_handoff_test.dart` is updated and a new path assertion for `/canvas` is
  added.
- **Studio `moduleId` updated**: `studio_screen.dart` now calls `openModuleInHost` with
  `moduleId: 'neurocnl'` (was `'Neurosim'`). The launcher's `'Neurosim'` compatibility alias
  remains for any external callers, but the canonical module id is now used at the call site.
- **Export workflow coverage added**: `test/screens/canvas/export_screen_test.dart` now covers
  the CNL-format export (fully local, no HTTP), widget rendering with the format dropdown and
  submit button, and the preflight-then-export flow for a non-CNL format (python) via a direct
  `ExportNotifier` provider test with a mocked HTTP client.
- **Sweep provider workflow coverage added**: `test/providers/canvas/sweep_provider_test.dart`
  covers four cases: synchronous completed sweep, async job-poll loop (queued → running →
  completed), failed sweep with `backendSupport.verdict = 'unsupported'`, and `reset()` clearing
  all state.
- **Save-project workflow coverage added**: `test/screens/canvas/project_screen_test.dart` now
  includes a second test that opens the "Save Current Design" dialog, enters a project name,
  confirms, and verifies the `POST /api/neurosim/projects` call receives the correct name.
- Full `cd neurocnl/frontend && flutter test` suite is green at 121 tests (up from 113).

## Status Update — 2026-05-01 (third pass — D2/D3 completion)

D2 (CNL ↔ Canvas Live Bidirectional Sync, issue #13) and D3 (Run-Sim Play Button, issue #14) are
now fully implemented and tested. Issues 13 and 14 are archived to `neurocnl/issues-archive/`.
`docs/execution-order.md` is updated: Phase D is marked complete.

Changes in this pass:

- **`studio_view_mode_provider.dart`** (NEW): `StudioViewMode` enum, `StudioSyncState`, and
  `StudioViewModeNotifier` `StateNotifierProvider` for the CNL/Canvas toggle.
- **`studio_screen.dart`** (D2+D3):
  - Two `ref.listen` blocks for bidirectional debounced sync (CNL→canvas and canvas→CNL).
  - `_syncingCnlToCanvas` / `_syncingCanvasToCnl` bool flags prevent feedback loops.
  - `_FileTabStrip` extended with `_ViewModeToggle` (sync spinner, error icon, two
    `_ToggleSegment` buttons with keys `cnl-view-toggle` and `canvas-view-toggle`).
  - Editor workspace now renders `IndexedStack([CnlEditor(), NetworkCanvas()])` indexed by mode.
  - `_RunButton` replaced with `_PlayStopButton` (`SingleTickerProviderStateMixin`; pulsing
    `CircularProgressIndicator` when running; animation only starts when `isRunning` is true).
  - `CallbackShortcuts` + `Focus(autofocus: true, skipTraversal: true)` for `Cmd+Enter` / `Ctrl+Enter`.
- **`pipeline_provider.dart`**: `cancelSimulation()` method added.
- **l10n** (`app_en.arb`, `app_localizations.dart`, `app_localizations_en.dart`): 5 new strings:
  `cnlViewToggle`, `canvasViewToggle`, `syncing`, `stopSimulation`, `fixErrorsFirst`.
- **Tests**:
  - `test/screens/studio_screen_test.dart`: 5 new tests covering toggle visibility, toggle state
    change, play button disabled state, stop-icon when running, and `Cmd+Enter` shortcut.
  - `test/widget_test.dart` and `test/pipeline_integration_test.dart`: updated to use `play-icon`
    key instead of `find.text('Run Preview')` / `ElevatedButton` lookups.
- Full `cd neurocnl/frontend && flutter test` suite: **126/126 green** (up from 121).

Not done yet:

- Some non-critical legacy references still remain in historical docs and archive material.
- Deeper Studio→Canvas import handoff integration test (covering the full navigation path from
  Studio editor through `openModuleInHost` into the canvas route) is still absent.

Validation completed for this pass:

- `rtk venv/bin/python -m pytest neurosim/tests/services/test_neurocnl_bridge_bootstrap.py neurosim/tests/routers/test_main.py neurosim/tests/routers/test_rate_limiting.py backend/tests/test_cors_config.py backend/tests/test_health.py -q`
- `rtk venv/bin/python -m pytest neurosim/tests/routers/test_components.py neurosim/tests/routers/test_projects.py -q`
- `rtk venv/bin/python -m pytest neurosim/tests/routers/test_projects.py backend/tests/test_health.py -q`
- `cd neurocnl/frontend && flutter pub get`
- `cd neurocnl/frontend && flutter test test/widget_test.dart --plain-name "Canvas export route renders inside the shared shell"`
- `cd neurocnl/frontend && flutter test test/widget_test.dart --plain-name "Canvas export route renders inside the shared shell"` (re-run after moving canvas route/shell entry files into `screens/canvas/**` and `routing/canvas/**`)
- `cd neurocnl/frontend && flutter test test/widget_test.dart`
- `cd neurocnl/frontend && flutter test test/widget_test.dart` (re-run after moving the remaining
  canvas bootstrap and widget files out of `canvas_app/**`)
- `cd neurocnl/frontend && flutter test test/widget_test.dart` (re-run after fixing the remaining
  canvas strict-typing and JSON-decoding errors)
- `cd neurocnl/frontend && flutter test test/widget_test.dart` (re-run after final analyzer and
  lint cleanup)
- `cd neurocnl/frontend && flutter test test/widget_test.dart` (re-run after broadening merged
  canvas route coverage for `/canvas`, `/canvas/projects`, and `/canvas/sweep`)
- `cd neurocnl/frontend && flutter test test/services/api_client_test.dart test/services/api_client_fault_injection_test.dart test/routing/neurosim_workspace_controller_test.dart`
- `cd neurocnl/frontend && flutter test test/screens/canvas/project_screen_test.dart`
- `cd neurocnl/frontend && flutter test`
- `bash scripts/run_launcher_guardrails.sh`
- `rtk python3 -m pytest tests/test_launcher_control_service.py -q`
- `rtk python3 -m pytest Neurohub/neurohub/tests/test_suite_client.py Neurohub/neurohub/tests/test_config_service.py -q`
- `bash scripts/validate_docker_compose.sh`
- `cd nmtk/neuro_toolkit && flutter pub get`
- `cd nmtk/neuro_toolkit && flutter test test/catalog_test.dart test/cross_module_navigation_test.dart`
- `cd nmtk/neuro_toolkit && flutter test test/ui_integration_test.dart test/tool_view_test.dart`
- `cd nmtk/packages/neurosim_feature && flutter test`

Validation completed for this pass (continued):

- `cd neurocnl/frontend && flutter test test/services/neurosim_handoff_test.dart test/services/neurosim_handoff_coordinator_test.dart`
- `cd neurocnl/frontend && flutter test test/screens/canvas/project_screen_test.dart`
- `cd neurocnl/frontend && flutter test test/screens/canvas/export_screen_test.dart`
- `cd neurocnl/frontend && flutter test test/providers/canvas/sweep_provider_test.dart`
- `cd neurocnl/frontend && flutter test` (full suite — 121 tests, all green)

Validation attempted but not yet green:

- `cd Neurobench/neurobench && pytest tests/test_benchmark_runner_hardware.py -q`
  `fastapi` is declared in `Neurobench/neurobench/pyproject.toml` but is not installed in the
  local interpreter. Run `cd Neurobench && poetry install` to resolve, then retry.

---

## Goals

- Remove the direct library-import coupling between Neurosim and neurocnl.
- Serve both the CNL pipeline (`/api/*`) and canvas API (`/api/neurosim/*`) from one process at
  port 8000.
- Unify the two Flutter frontends into a single two-tab app under one build.
- Retire port 8001 and the Neurosim submodule without breaking any existing consumer HTTP
  contracts.

## Non-Goals

- Rename or refactor the `neurocnl` Python library API. All public symbols stay as-is.
- Touch Neurochip, Neurobench, Neurosense, Neurohub, or Neuro-Dream-Hand beyond the minimum
  config/URL updates each requires.
- Change any HTTP endpoint paths; all routes remain at their existing prefixes.

---

## Architecture Before / After

### Before

```
neurocnl/   port 8000   backend/app/main.py   uvicorn: backend.app.main:app
Neurosim/   port 8001   neurosim/app/main.py  uvicorn: neurosim.app.main:app
                          ↑ imports neurocnl as pip dependency
```

### After

```
neurocnl/   port 8000   backend/app/main.py   uvicorn: backend.app.main:app
              ├── all existing /api/* routes
              └── neurosim/ sub-package (moved in) → all /api/neurosim/* routes
```

---

## Phase 0 — Preparation

1. Verify both services pass their tests at current HEAD before touching anything.

   ```bash
   # In neurocnl/
   PYTHONPATH=. pytest neurocnl/tests/ backend/tests/ -v
   cd frontend && flutter test

   # In Neurosim/
   PYTHONPATH=. python -m pytest neurosim/tests/ -v
   cd frontend && flutter test
   ```

2. Confirm the Neurosim submodule is on a clean commit (no uncommitted changes):

   ```bash
   git submodule status
   cd Neurosim && git status
   ```

3. Create a working branch: `git checkout -b merge/neurostudio`.

---

## Phase 1 — Move the `neurosim` Python package into `neurocnl/`

Copy the entire `neurosim` Python package from the Neurosim submodule into the `neurocnl`
directory. The package keeps its name (`neurosim`) so all import paths inside it remain valid with
the single exception of `neurocnl_bridge.py` (handled in Phase 2).

```
Neurosim/neurosim/                     →  neurocnl/neurosim/
  app/
    routers/
      components.py                    keep as-is
      export.py                        keep as-is
      generation.py                    keep as-is
      preview.py                       keep as-is
      projects.py                      keep as-is
      simulation_ws.py                 keep as-is
      spinnaker2.py                    keep as-is
      sweep.py                         keep as-is
      templates.py                     rename import alias (see Phase 3)
      validation.py                    rename import alias (see Phase 3)
    schemas/
      *.py                             keep as-is
    services/
      components.py                    keep as-is
      cnl_to_graph.py                  keep as-is
      graph_to_cnl.py                  keep as-is
      job_store.py                     keep as-is
      neurocnl_bridge.py               REWRITE (Phase 2)
      preview_runner.py                keep as-is
      project_store.py                 keep as-is
      semantic_cnl.py                  keep as-is
      sweep_runner.py                  keep as-is
    backends/
      spinnaker2_backend.py            keep as-is
    utils/
      logging.py                       keep as-is
    middleware/
      logging.py                       keep — neurosim's middleware is kept separate;
                                       the combined main.py will use neurocnl's middleware
                                       stack for the unified app but neurosim's own can
                                       remain for the isolated router tests.
    limiter.py                         keep as-is
    __init__.py                        keep as-is
  contracts/
    design_contracts.py                keep as-is
    canvas_contracts.py                keep as-is
    project_contracts.py               keep as-is
    simulation_contracts.py            keep as-is
    __init__.py                        keep as-is
  components/
    **/*                               keep as-is (all JSON/py component definitions)
  templates/
    *.json                             keep as-is (starter circuits)
  tests/
    routers/                           keep as-is
    services/                          keep as-is
    properties/                        keep as-is
  app/main.py                          compatibility shim to merged backend app
  __init__.py                          keep as-is
```

**What NOT to copy from Neurosim:**
- `Neurosim/neurosim/app/main.py` — not needed; will use neurocnl's combined main.py.
- `Neurosim/Dockerfile`, `Neurosim/docker-compose.yml` — retired.
- `Neurosim/frontend/` — handled separately in Phase 5.
- `Neurosim/pyproject.toml`, `Neurosim/AGENTS.md`, `Neurosim/README.md` — retired; the neurocnl
  equivalents absorb relevant content.

---

## Phase 2 — Replace `neurocnl_bridge.py` with direct imports

File to rewrite: `neurocnl/neurosim/app/services/neurocnl_bridge.py`

The current bridge uses dynamic `sys.path` manipulation to import neurocnl because the two
packages lived in separate directories. After the move they are siblings under the same Python
path, so the bridge becomes a thin direct-import shim. Rewrite it to:

```python
# neurocnl/neurosim/app/services/neurocnl_bridge.py
"""
Direct bridge to the neurocnl library (now co-located in the same package tree).
Exposes the same interface as the old dynamic-import bridge so all callers
(validation.py, preview.py, sweep.py, export.py) require zero changes.
"""
from neurocnl.cnl.cnl_parser import parse, ParseError          # was: dynamic import
from neurocnl.ir import lower_to_ir, LoweringError              # was: dynamic import
from neurocnl.planner import (                                   # was: dynamic import
    plan_backend_support,
    plan_akida_exportability,
    plan_pynq_exportability,
)
from neurocnl.layers.layer1_invariants import ALL_INVARIANTS    # was: dynamic import
from neurocnl.generation.nengo_generator import generate        # was: dynamic import


def assess_validation_support(graph):
    """Unchanged call signature — used by neurosim/app/routers/validation.py."""
    ...  # implementation using direct imports above


def validate_semantics(parameters: dict):
    """Unchanged call signature — used by neurosim/app/routers/validation.py."""
    ...


def assess_preview_support(graph):
    """Unchanged call signature — used by neurosim/app/routers/preview.py."""
    ...


def assess_sweep_support(payload):
    """Unchanged call signature — used by neurosim/app/routers/sweep.py."""
    ...


def assess_export_support(graph, export_format: str):
    """Unchanged call signature — used by neurosim/app/routers/export.py."""
    ...
```

The existing function signatures and return types must stay identical so that the four routers
(`validation.py`, `preview.py`, `sweep.py`, `export.py`) need no changes.

---

## Phase 3 — Add neurosim routers to the combined `main.py`

File to edit: `neurocnl/backend/app/main.py`

The neurosim routers already use `/api/neurosim/` path prefixes, so they do not conflict with any
of neurocnl's existing `/api/*` routes. Add them after the existing router registrations.

### Import block to add (below existing router imports)

```python
# --- NeuroSim canvas routers (merged from Neurosim submodule) ---
from neurosim.app.routers import components as sim_components
from neurosim.app.routers import export as sim_export
from neurosim.app.routers import generation as sim_generation
from neurosim.app.routers import preview as sim_preview
from neurosim.app.routers import projects as sim_projects
from neurosim.app.routers import simulation_ws as sim_ws
from neurosim.app.routers import spinnaker2 as sim_spinnaker2
from neurosim.app.routers import sweep as sim_sweep
from neurosim.app.routers.templates import router as sim_templates_router
from neurosim.app.routers.validation import router as sim_validation_router
from neurosim.app.services.project_store import ProjectStore
```

Note: `templates` and `validation` are aliased at the router level to avoid shadowing
neurocnl's existing `templates` and `validate` imports.

### `include_router` calls to add (below existing includes)

```python
# NeuroSim canvas routes — all prefixed /api/neurosim/* so no path conflicts
app.include_router(sim_components.router)
app.include_router(sim_export.router)
app.include_router(sim_generation.router)
app.include_router(sim_preview.router)
app.include_router(sim_projects.router)
app.include_router(sim_ws.router)
app.include_router(sim_spinnaker2.router)
app.include_router(sim_sweep.router)
app.include_router(sim_templates_router)
app.include_router(sim_validation_router)
```

### Lifespan update

Add ProjectStore initialization to the existing lifespan function (alongside the current job store
and neurocnl import checks):

```python
async with asynccontextmanager(lifespan):
    # existing: job_store init, stale job recovery ...
    await ProjectStore.initialize()   # add this
    yield
    # existing: drain, cleanup ...
    await ProjectStore.close()        # add this
```

Implementation note: the lifecycle hook is now present as an async wrapper around the existing
synchronous SQLite store. `ProjectStore.initialize()` primes the shared default store during
startup, `ProjectStore.close()` clears it on shutdown, and `/health` still uses `ping()` for the
lightweight readiness probe.

### CORS update

Neurosim's `main.py` set `ALLOWED_ORIGINS` from environment. The combined app should honour both
env vars or consolidate to `CORS_ALLOWED_ORIGINS` (neurocnl's existing var). Update the CORS
section to accept both names, defaulting to `"*"`:

```python
cors_origins = os.getenv("CORS_ALLOWED_ORIGINS", os.getenv("ALLOWED_ORIGINS", "*")).split(",")
```

### Health endpoint update

Extend the existing `GET /health` response to include neurosim component status:

```python
"canvas_store": ProjectStore().ping(),   # add to health dict
"canvas_components": len(load_components()) > 0,
```

---

## Phase 4 — Update `neurocnl/pyproject.toml`

### Remove

- `neurocnl` from dependencies (it is now part of the same package, not an external dep). The
  original neurocnl `pyproject.toml` never listed itself as a dependency; this is the line to
  remove from Neurosim's list when merging, which means it simply doesn't appear in the combined
  file.

### Add (merge Neurosim's deps into neurocnl's)

The following are in Neurosim's `pyproject.toml` but not in neurocnl's:

```toml
[tool.poetry.dependencies]
watchdog = ">=3.0"          # file monitoring (used by project_store hot-reload)

[tool.poetry.extras]
spinnaker2 = ["py-spinnaker2"]   # add to existing extras section
```

`nengo`, `numpy`, `fastapi`, `uvicorn`, `pydantic`, `slowapi`, `nir` are already present in
neurocnl's deps — no duplication needed.

### Update package metadata

```toml
[tool.poetry]
name = "neurocnl"
description = "NeuroStudio — CNL compiler and visual SNN design suite"
# version stays at 0.6.0 (or bump to 0.7.0 to signal the merge)
```

### Update test paths

```toml
[tool.pytest.ini_options]
testpaths = ["neurocnl", "backend/tests", "neurosim/tests"]
```

### Update mypy module list

Add `neurosim.contracts.*` to the strict mypy modules list alongside the existing
`neurocnl.contracts.*`.

---

## Phase 5 — Merge the Flutter frontends

The neurocnl frontend gains a "Canvas" section. Neurosim's four screens become sub-routes under
`/canvas`. The neurosim frontend's API client is updated to point at port 8000 instead of 8001.

### 5a — Copy files into `neurocnl/frontend/lib/`

Status: materially implemented. The old copied Neurosim subtree under
`neurocnl/frontend/lib/canvas_app/**` has now been eliminated. The top-level screen entry points
live at `neurocnl/frontend/lib/screens/canvas/**`, the route restoration / shell controller files
at `neurocnl/frontend/lib/routing/canvas/**`, the embedded NeuroSim shell app at
`neurocnl/frontend/lib/routing/canvas/neurosim_app.dart`, the canvas models under
`neurocnl/frontend/lib/models/canvas/**`, the canvas providers under
`neurocnl/frontend/lib/providers/canvas/**`, the copied API client at
`neurocnl/frontend/lib/services/canvas_api_client.dart`, the shared canvas helper at
`neurocnl/frontend/lib/utils/canvas_component_utils.dart`, and the canvas-specific widgets at
`neurocnl/frontend/lib/widgets/canvas/**`. The remaining follow-up is code-quality cleanup rather
than more path normalization.

```
Neurosim/frontend/lib/screens/canvas_screen.dart     → neurocnl/frontend/lib/screens/canvas/canvas_screen.dart
Neurosim/frontend/lib/screens/export_screen.dart     → neurocnl/frontend/lib/screens/canvas/export_screen.dart
Neurosim/frontend/lib/screens/project_screen.dart    → neurocnl/frontend/lib/screens/canvas/project_screen.dart
Neurosim/frontend/lib/screens/sweep_screen.dart      → neurocnl/frontend/lib/screens/canvas/sweep_screen.dart

Neurosim/frontend/lib/providers/canvas_provider.dart      → neurocnl/frontend/lib/providers/canvas/
Neurosim/frontend/lib/providers/component_provider.dart   → neurocnl/frontend/lib/providers/canvas/
Neurosim/frontend/lib/providers/export_provider.dart      → neurocnl/frontend/lib/providers/canvas/
  (rename to canvas_export_provider.dart to avoid shadowing neurocnl's export_provider.dart)
Neurosim/frontend/lib/providers/neurochip_handoff_provider.dart → neurocnl/frontend/lib/providers/canvas/
Neurosim/frontend/lib/providers/project_provider.dart     → neurocnl/frontend/lib/providers/canvas/
Neurosim/frontend/lib/providers/simulation_provider.dart  → neurocnl/frontend/lib/providers/canvas/
Neurosim/frontend/lib/providers/sweep_provider.dart       → neurocnl/frontend/lib/providers/canvas/
Neurosim/frontend/lib/providers/sync_provider.dart        → neurocnl/frontend/lib/providers/canvas/
Neurosim/frontend/lib/providers/validation_provider.dart  → neurocnl/frontend/lib/providers/canvas/

Neurosim/frontend/lib/services/api_client.dart        → neurocnl/frontend/lib/services/canvas_api_client.dart
  (rename to avoid shadowing neurocnl's api_client.dart)
Neurosim/frontend/lib/services/import_cnl_payload.dart → neurocnl/frontend/lib/services/
Neurosim/frontend/lib/services/neurochip_handoff.dart   → neurocnl/frontend/lib/services/
Neurosim/frontend/lib/services/open_external_url*.dart  → neurocnl/frontend/lib/services/
  (only if not already present in neurocnl/frontend/lib/services/)

Neurosim/frontend/lib/models/canvas.dart              → neurocnl/frontend/lib/models/canvas/
Neurosim/frontend/lib/models/canvas_graph.dart        → neurocnl/frontend/lib/models/canvas/
Neurosim/frontend/lib/models/component.dart           → neurocnl/frontend/lib/models/canvas/
Neurosim/frontend/lib/models/neurochip_network.dart   → neurocnl/frontend/lib/models/canvas/
Neurosim/frontend/lib/models/preview.dart             → neurocnl/frontend/lib/models/canvas/
Neurosim/frontend/lib/models/project.dart             → neurocnl/frontend/lib/models/canvas/
Neurosim/frontend/lib/models/sweep.dart               → neurocnl/frontend/lib/models/canvas/
Neurosim/frontend/lib/models/validation.dart          → neurocnl/frontend/lib/models/canvas/

Neurosim/frontend/lib/widgets/network_canvas.dart            → neurocnl/frontend/lib/widgets/canvas/
Neurosim/frontend/lib/widgets/simulation_control_panel.dart  → neurocnl/frontend/lib/widgets/canvas/
Neurosim/frontend/lib/widgets/spike_raster_plot.dart         → neurocnl/frontend/lib/widgets/canvas/
Neurosim/frontend/lib/widgets/time_series_chart.dart         → neurocnl/frontend/lib/widgets/canvas/
Neurosim/frontend/lib/widgets/cnl_editor.dart                → neurocnl/frontend/lib/widgets/canvas/
  (rename to canvas_cnl_editor.dart to avoid shadowing neurocnl's cnl_editor.dart)
Neurosim/frontend/lib/widgets/export_dialog.dart             → neurocnl/frontend/lib/widgets/canvas/
Neurosim/frontend/lib/widgets/property_panel.dart            → neurocnl/frontend/lib/widgets/canvas/
Neurosim/frontend/lib/widgets/component_library_sidebar.dart → neurocnl/frontend/lib/widgets/canvas/
Neurosim/frontend/lib/widgets/backend_support_banner.dart    → neurocnl/frontend/lib/widgets/canvas/

Neurosim/frontend/lib/utils/canvas_component_utils.dart  → neurocnl/frontend/lib/utils/
```

### 5b — Update `canvas_api_client.dart` base URL

Status: implemented in `neurocnl/frontend/lib/services/canvas_api_client.dart`. The copied client
now prefers the current web origin and otherwise defaults to `http://localhost:8000`, with no
remaining 8001 fallback.

Change the default port from `8001` to `8000` and remove all references to `localhost:8001`:

```dart
// canvas_api_client.dart — base URL resolution (after)
String _resolveBaseUrl({String? override}) {
  if (override != null) return override.trimRight('/');
  const env = String.fromEnvironment('API_BASE_URL', defaultValue: '');
  if (env.isNotEmpty) return env.trimRight('/');
  // Web: use current origin
  if (kIsWeb) {
    final uri = Uri.base;
    if (uri.host == 'localhost') return 'http://localhost:8000';  // was 8001
    return uri.origin;
  }
  return 'http://localhost:8000';  // was 8001
}
```

The path prefix `/api/neurosim` in every method call remains unchanged.

### 5c — Add canvas routes to `app_router.dart`

Status: implemented in `neurocnl/frontend/lib/routing/app_router.dart` using
`CanvasHostScreen` plus the canonical `screens/canvas/**` and `routing/canvas/**` files to
bootstrap the embedded canvas app with `NeurosimRestorationSnapshot` state for the `/canvas`,
`/canvas/projects`, `/canvas/sweep`, and `/canvas/export` entry points.

In `neurocnl/frontend/lib/routing/app_router.dart`, add four new routes. Keep them under a
`/canvas` parent so they are clearly scoped:

```dart
GoRoute(
  path: '/canvas',
  name: 'canvas',
  builder: (context, state) => const CanvasScreen(),
  routes: [
    GoRoute(
      path: 'projects',
      name: 'canvas-projects',
      builder: (context, state) => const ProjectScreen(),
    ),
    GoRoute(
      path: 'sweep',
      name: 'canvas-sweep',
      builder: (context, state) => const SweepScreen(),
    ),
    GoRoute(
      path: 'export',
      name: 'canvas-export',
      builder: (context, state) => const CanvasExportScreen(),
    ),
  ],
),
```

### 5d — Add "Canvas" to the navigation rail

Status: implemented in the shared shell destination list in
`neurocnl/frontend/lib/routing/app_router.dart`.

In the desktop NavigationRail (and mobile BottomNavigationBar), add a "Canvas" destination between
Studio and Deploy. Update the index-to-route mapping accordingly. The exact widget file is
`neurocnl/frontend/lib/app.dart` or wherever the navigation destinations are defined.

### 5e — Update `pubspec.yaml`

Status: implemented in `neurocnl/frontend/pubspec.yaml` with `json_annotation`, `shadcn_ui`, and
`json_serializable` added so the embedded canvas subtree can build inside the `neurocnl`
frontend package.

Add to `neurocnl/frontend/pubspec.yaml`:

```yaml
dependencies:
  json_annotation: ^4.9.0   # used by Neurosim canvas models

dev_dependencies:
  build_runner: ^2.4.15
  json_serializable: ^6.9.4
```

---

## Phase 6 — Update module registry, Docker, and build scripts

### 6a — `nmtk/neuro_toolkit/assets/modules.json`

Status: partially implemented. The `Neurosim` manifest entry is removed and the `neurocnl`
launcher label/description now read as `NeuroStudio`, but the underlying launcher runtime
strategy remains the current suite-web embedding model (`port: 9000`, `startStrategy: none`)
rather than the older direct-uvicorn shape assumed in the original plan text.

Remove the Neurosim entry entirely. Update the neurocnl entry's display name:

```json
{
  "id": "neurocnl",
  "name": "NeuroStudio",
  "description": "CNL compiler and visual SNN design suite",
  "port": 8000,
  "uvicornTarget": "backend.app.main:app",
  "hasFrontend": true,
  "installStrategy": "pip",
  "startStrategy": "uvicorn",
  "localDeps": ["Neuro-Dream-Hand/"],
  "remoteUrl": "https://api.github.com/repos/Completed-Spoon-6/neurocnl"
}
```

After removing the Neurosim entry, run the launcher doctor to confirm no fatal counts:

```bash
python3 scripts/launcher_control_service.py --doctor --json
```

Update the launcher Dart model (`nmtk/neuro_toolkit/lib/models/module.dart`) and any launcher tests
that assert on the count or ids of entries in `modules.json`.

Additional compatibility work completed in this pass:

- `nmtk/neuro_toolkit/lib/routing/router.dart` now maps `/module/neurosim` to
  `NeurocnlShell(initialLocation: '/canvas...')`.
- `nmtk/neuro_toolkit/lib/workspace/native_surface_registry.dart` now treats legacy
  `WorkspaceSession.moduleId == "Neurosim"` as a compatibility alias to `neurocnl`.
- `nmtk/launcher_control/server.py` now rewrites persisted legacy `Neurosim` workspace sessions to
  `neurocnl` plus `/canvas` deep links during workspace normalization, which was required to make
  launcher doctor pass after manifest removal.

### 6b — Root `docker-compose.yml`

Remove the `neurosim` service block entirely. Update the `neurocnl` service's health check URL if
it currently hard-codes port 8000 (it already does — no change needed there).

Remove `neurosim` from Neurohub's `depends_on` block:

```yaml
# neurohub service — depends_on: remove neurosim entry
depends_on:
  neurocnl:
    condition: service_healthy
  neurochip:
    condition: service_healthy
  neurobench:
    condition: service_healthy
  neurosense:
    condition: service_healthy
  # neurosim: REMOVED
```

Remove `NEUROSIM_URL` from Neurohub's environment block (see Phase 7a for the Neurohub-side
change that aliases the old key).

### 6c — `scripts/build_all_frontends.sh`

Remove `Neurosim:8001` from `MODULE_LIST`. The neurocnl entry already handles the combined
frontend:

```bash
MODULE_LIST="neurocnl:8000 Neurochip:8002 Neurobench:8003 Neurosense:8004 Neurohub:8005"
# Neurosim:8001 removed
```

No other changes needed — the combined frontend is still built with
`--dart-define=API_BASE_URL="http://$API_HOST:8000"`.

### 6d — `monitoring/prometheus/prometheus.yml`

Remove the `neurosim:8000` target from the scrape config:

```yaml
static_configs:
  - targets:
      - 'neurocnl:8000'
      # 'neurosim:8000'  REMOVED
      - 'neurochip:8002'
      ...
```

### 6e — `monitoring/promtail/promtail-config.yml`

The regex `(neurocnl|neurosim|...)` can stay as-is — promtail will simply never match `neurosim`
container logs since the container no longer exists. Or remove `neurosim` from the alternation to
keep it tidy.

### 6f — `neurocnl/backend/Dockerfile`

The existing Dockerfile installs the `neurocnl` package. After the merge the `neurosim` sub-package
lives in the same tree and is installed automatically — no change needed. Verify by running:

```bash
docker build -t neurostudio-test ./neurocnl/backend/ && \
docker run --rm neurostudio-test python -c "import neurosim; print('ok')"
```

---

## Phase 7 — Update consumers

### 7a — `Neurohub/neurohub/app/services/suite_client.py`

Status: partially implemented. NeuroHub now defaults both `neurosim` and `neurocnl` to
 `http://localhost:8000`, and `SuiteConfig.neurosim_url` now also defaults to
 `http://localhost:8000`.

The suite client routes requests to modules by name. `"neurosim"` is still a valid workflow step
in existing saved workflows (e.g. `app: "neurosim"`, `endpoint: "/api/neurosim/preview"`).
Add an alias so existing workflows do not break:

```python
# suite_client.py — in DEFAULT_URLS, replace:
DEFAULT_URLS = {
    "neurocnl": "http://localhost:8000",
    "neurosim": "http://localhost:8001",   # OLD
    ...
}

# Replace with:
DEFAULT_URLS = {
    "neurocnl":  "http://localhost:8000",
    "neurosim":  "http://localhost:8000",  # alias — canvas routes now served by neurocnl
    ...
}
```

Same change in `Neurohub/neurohub/app/schemas/config.py`:

```python
# Before:
neurosim_url: str = "http://localhost:8001"

# After:
neurosim_url: str = "http://localhost:8000"   # canvas routes moved to neurocnl
```

Do NOT remove `"neurosim"` from `valid_modules` in
`Neurohub/neurohub/contracts/orchestration_contracts.py` — existing serialized workflows may still
reference it and should continue to route correctly.

### 7b — `Neurobench/neurobench/app/config.py`

```python
# Before:
neurosim_api_url: str = Field(
    default="http://neurosim-backend:8001/execute", alias="NEUROSIM_API_URL"
)

# After:
neurosim_api_url: str = Field(
    default="http://neurocnl-backend:8000/api/neurosim/preview",
    alias="NEUROSIM_API_URL",
)
```

Update the env var comment (or the `NEUROSIM_API_URL` docker-compose entry) to document the new
default. The HTTP call in `benchmark_runner.py` is unchanged — it just calls whatever URL is
configured.

### 7c — `Neurobench/neurobench/app/services/benchmark_runner.py`

This file directly imports `from neurocnl.simulation.run_simulation import run_pipeline`. After the
merge, this import still works because the `neurocnl` package is unchanged. No code changes needed.

### 7d — `Neuro-Dream-Hand/neurodreamhand/core/cnl_integration.py`

This file imports directly from `neurocnl.cnl.cnl_parser` and `neurocnl.layers.layer1_invariants`.
These symbols are unchanged. No code changes needed.

### 7e — `scripts/ci/lib.sh`

Remove any step that installs or tests the Neurosim package separately. If there is a step like
`pip install ./Neurosim && pytest Neurosim/neurosim/tests/`, remove it — those tests now run under
the neurocnl pytest config (Phase 4).

### 7f — `scripts/run_comprehensive_tests.sh`

Remove `--cov=neurosim` from the coverage args — the `neurosim` sub-package is now covered under
the `neurocnl` directory tree. The coverage will still include it because pytest traverses the
`neurocnl/neurosim/` path.

---

## Phase 8 — Update tests

### 8a — `tests/integration/test_cross_module.py`

Status: partially implemented. The root integration default for `NEUROSIM_URL` now points at
`http://neurocnl:8000`.

The test calls these endpoints to verify the neurocnl → Neurosim integration:

- `POST http://{NEUROCNL_URL}:8000/api/parse` — unchanged (still neurocnl)
- `POST http://{NEUROSIM_URL}:8001/api/neurosim/parse-cnl` — URL changes to port 8000

Update the `NEUROSIM_URL` env var default:

```python
NEUROSIM_URL = os.getenv("NEUROSIM_URL", "http://localhost:8000")  # was 8001
```

The endpoint paths themselves (`/api/neurosim/parse-cnl`, `/api/neurosim/preview`,
`/api/neurosim/export/c`) are unchanged.

Also update the Neurohub orchestration test: the `neurosim` app still appears in workflow steps —
no change needed there since Neurohub now aliases it to port 8000.

### 8b — Neurosim's router and service tests

The `Neurosim/neurosim/tests/` directory was moved to `neurocnl/neurosim/tests/` in Phase 1. The
tests use `TestClient(app)` where `app` is imported from `neurosim.app.main`. After the move this
import resolves correctly because `neurosim` is now a sub-package of the `neurocnl` directory tree.

Run them via the updated testpath in `pyproject.toml`:

```bash
PYTHONPATH=. pytest neurosim/tests/ -v
```

### 8c — neurocnl frontend tests

Add smoke tests for the four new canvas routes. At minimum, add to
`neurocnl/frontend/test/screens_smoke_test.dart`:

```dart
testWidgets('canvas screen renders', (tester) async {
  await tester.pumpWidget(buildTestApp(initialRoute: '/canvas'));
  expect(find.byType(CanvasScreen), findsOneWidget);
});
```

---

## Phase 9 — Archive and remove the Neurosim submodule

Once all tests pass on the merge branch:

1. Tag the final commit of the Neurosim submodule for archival:

   ```bash
   cd Neurosim
   git tag archive/pre-merge-$(date +%Y%m%d) HEAD
   git push origin archive/pre-merge-$(date +%Y%m%d)
   ```

2. Remove the submodule registration from the parent repo:

   ```bash
   git submodule deinit -f Neurosim
   git rm -f Neurosim
   rm -rf .git/modules/Neurosim
   ```

3. Remove the entry from `.gitmodules`.

4. Commit:

   ```bash
   git add .gitmodules
   git commit -m "Remove Neurosim submodule — merged into neurocnl as NeuroStudio"
   ```

---

## Consumers Affected — Summary

| File | Change |
|---|---|
| `nmtk/neuro_toolkit/assets/modules.json` | Remove Neurosim entry; update neurocnl display name |
| `nmtk/neuro_toolkit/lib/models/module.dart` | Update if it hard-codes module count or ids |
| `nmtk/neuro_toolkit/test/*` | Update assertions on module list count |
| `docker-compose.yml` | Remove `neurosim` service; remove from neurohub `depends_on` |
| `Neurohub/neurohub/app/services/suite_client.py` | Alias `"neurosim"` to port 8000 |
| `Neurohub/neurohub/app/schemas/config.py` | Update `neurosim_url` default to port 8000 |
| `Neurobench/neurobench/app/config.py` | Update `NEUROSIM_API_URL` default |
| `scripts/build_all_frontends.sh` | Remove `Neurosim:8001` from MODULE_LIST |
| `scripts/run_comprehensive_tests.sh` | Remove `--cov=neurosim` (now covered under neurocnl) |
| `tests/integration/test_cross_module.py` | Change `NEUROSIM_URL` default from 8001 → 8000 |
| `monitoring/prometheus/prometheus.yml` | Remove `neurosim:8000` scrape target |
| `.gitmodules` | Remove Neurosim entry |

---

## Risks and Mitigations

**Risk: neurosim SQLite project store path**  
The current `project_store.py` likely writes to a relative path. After the move the working
directory depends on where uvicorn is started. Audit `project_store.py` for hardcoded relative
paths and replace with `Path(__file__).parent / "data" / "projects.db"` or an env var.

**Risk: neurosim limiter isolation**  
Neurosim's `limiter.py` uses a custom `get_client_ip` function that favours `X-Forwarded-For` for
test isolation. The combined app uses neurocnl's `PrometheusMiddleware` and `slowapi` limiter.
Keep neurosim's limiter instance separate (it already references its own router-level instance) —
no action needed unless rate-limit tests fail, in which case ensure the test client passes the
correct `X-Forwarded-For` header.

**Risk: Neurobench's `NEUROSIM_API_URL` points to `/execute`**  
The old Neurobench config defaulted to `http://neurosim-backend:8001/execute`. The canvas API has
no `/execute` endpoint — the closest is `/api/neurosim/preview`. Update the default and ensure
Neurobench's `_run_neurosim()` method interprets the response correctly for the preview schema.

**Risk: Neurohub saved workflows with `app: "neurosim"` in database**  
Existing workflow rows in the SQLite/Postgres database reference `"neurosim"` as the app name.
The alias in `suite_client.py` handles runtime routing, but if Neurohub validates `app` values on
read, ensure `"neurosim"` is still in `valid_modules` (Phase 7a covers this).

**Risk: Docker network hostname resolution**  
After removing the `neurosim` Docker service, any container that resolves the hostname `neurosim`
will fail. Audit all `docker-compose.yml` env vars for `http://neurosim:*` references and replace
with `http://neurocnl:8000`. The only confirmed reference is Neurohub's `NEUROSIM_URL`.

---

## Verification Checklist

Run these in order on the `merge/neurostudio` branch before merging:

```bash
# 1. Python library still importable and tests pass
cd neurocnl
PYTHONPATH=. pytest neurocnl/tests/ backend/tests/ neurosim/tests/ -v --cov=neurocnl --cov=neurosim

# 2. Type checking
mypy neurocnl/ neurosim/

# 3. Lint
ruff check .

# 4. Verify the bridge removed dynamic imports — grep must return nothing
grep -r "sys.path" neurosim/

# 5. Verify all neurosim routes load in the combined app
uvicorn backend.app.main:app --port 8000 &
curl -s http://localhost:8000/health | jq .
curl -s http://localhost:8000/api/neurosim/components | jq .total
curl -s http://localhost:8000/api/templates | jq .  # neurocnl route still works
kill %1

# 6. Flutter frontend tests
cd frontend && flutter test

# 7. Launcher doctor — must report fatalCount: 0
cd ..
python3 scripts/launcher_control_service.py --doctor --json

# 8. Integration tests against live services
python3 -m pytest tests/integration/test_cross_module.py -v
python3 -m pytest tests/integration/test_teensy_e2e.py -v

# 9. Full launcher guardrails
bash scripts/run_launcher_guardrails.sh --with-integration

# 10. Confirm Neurosim submodule is gone
ls Neurosim  # should: no such file
git submodule status  # should: no Neurosim entry
```
