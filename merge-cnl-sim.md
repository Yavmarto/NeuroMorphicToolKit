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
"canvas_store": await ProjectStore.ping(),   # add to health dict
"canvas_components": len(await load_components()) > 0,
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

In the desktop NavigationRail (and mobile BottomNavigationBar), add a "Canvas" destination between
Studio and Deploy. Update the index-to-route mapping accordingly. The exact widget file is
`neurocnl/frontend/lib/app.dart` or wherever the navigation destinations are defined.

### 5e — Update `pubspec.yaml`

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
