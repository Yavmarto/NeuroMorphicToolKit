# Neurosim

Read first:
- `CODING_STYLE_GUIDE.md`
- `pyproject.toml`
- `frontend/pubspec.yaml`
- `frontend/analysis_options.yaml`
- `.pre-commit-config.yaml`
- `neurosim_spec.md`
- `docs/ADR-Gemini/`, `docs/ADR-Codex/`, `docs/ADR-claude/`

Constraints:
- `neurocnl/neurosim/` is the canonical NeuroSim source of truth. Make functional edits there first, then sync the mirrored `Neurosim/neurosim/` copy to keep standalone tests aligned.
- `neurosim/contracts/*.py` own the shared graph, canvas, simulation, and project payloads; update contracts and contract tests before changing router or service behavior.
- Treat graph import or export and preview payloads as cross-repo surfaces. Read `neurocnl`, `Neurochip`, `Neurohub`, or `Neurobench` before editing those boundaries.
- Keep simulation and preview logic in services, not in routers or widget code; the frontend should consume typed payloads rather than inventing alternate graph shapes.
- The canvas and preview stack must preserve stable ids, positions, and duration semantics across backend and frontend changes; change both sides together or not at all.
- Verify touched surfaces with `PYTHONPATH=. python -m pytest neurosim/tests/`, `python -m mypy neurosim`, and `cd frontend && flutter test`.

Do NOT:
- Rename graph or preview fields in only one layer.
- Move business logic into routers to satisfy a local test quickly.
- Change a shared simulation payload without reading the consumer or producer repo first.

## Shell mode

Primary screen uses `NmtkShellMode.studio`. Pass `mode: NmtkShellMode.studio` to `NmtkDesktopScaffold` (or `NmtkTopAppBar` in embedded mode). Do not use `.command` or `.instrument`.

The canvas itself (`InteractiveViewer`, `CustomPaint`, node/port/edge rendering) is untouchable — only the chrome around it is subject to UI migration. Panel content padding in canvas-adjacent panels is 16 px (instrument-compact), not the 24 px page default, because panel space is premium in a canvas IDE.


---

## Pipeline Agent Directives

This document provides guidance for AI agents working within the Neurosim module. It complements the global `CODING_STYLE_GUIDE.md`.

## Core Technology Stack
- **Backend:** Python 3.12, FastAPI, Pydantic V2.
- **Frontend:** Flutter (Web/Desktop), Riverpod for state management.
- **Integration:** Uses the `neurocnl` library for CNL generation, parsing, and local Nengo simulations.
- **Quality Tools:** Ruff (linting), MyPy (strict typing), Black (formatting), Hypothesis (property-based testing).

## Backend Guidelines
- **Contracts:** All core data models and API contracts must be defined or re-exported in `neurosim/contracts/design_contracts.py`.
- **Typing:** Strict type hinting is mandatory. Run `python -m mypy` from the root to verify.
- **Documentation:** Every public function, class, and method MUST have a Google-style docstring.
- **Testing:**
  - Unit/Integration tests: `neurosim/tests/services/` and `neurosim/tests/routers/`.
  - Property-based tests: `neurosim/tests/properties/`.
  - Run all with: `PYTHONPATH=. python -m pytest neurosim/tests/`.
- **Imports:** Use relative imports for internal module references (e.g., `from ..schemas import ...`).
- **Serialization:** Use `NIRJSONEncoder` from `neurosim/app/utils/serialization.py` for responses containing NIR data (NumPy arrays).

## Frontend Guidelines
- **State Management:** Use Riverpod. Prefer `Notifier` or `AsyncNotifier`.
- **Widgets:**
  - Follow the "Extract Widgets, Don't Extract Methods" principle.
  - UI should use standard Material 3 theming (`Theme.of(context)`).
- **Typing:** Avoid `dynamic`. Use strong models and `json_serializable`.
- **Canvas:** Coordinate translations for drag/zoom must use the `TransformationController` in `NetworkCanvas`.
- **Serialization:** Run `flutter pub run build_runner build --delete-conflicting-outputs` after model changes.

## Workflow & Verification
- **Progress Tracking:** Update `PROGRESS.md` after implementing significant user stories.
- **Validation:** Graph validation via `validationProvider` is mandatory for all canvas updates.
- **CI Compliance:** Ensure all changes pass the local pre-commit hooks (`.pre-commit-config.yaml`) before submission.

<directory_structure>
├── AGENTS.md
├── CHANGELOG.md
├── CODE_REVIEW.md
├── CODE_REVIEW_2026-05-14.md
├── Dockerfile
├── LICENSE
├── Makefile
├── Neurosim_shell_adapter
│   ├── LICENSE
│   ├── lib
│   │   ├── Neurosim_shell_adapter.dart
│   │   └── src
│   │       └── neurosim_shell_adapter.dart
│   ├── pubspec.lock
│   └── pubspec.yaml
├── PROGRESS.md
├── README.md
├── SECURITY.md
├── SECURITY_REVIEW.md
├── UI migration.md
├── docker-compose.yml
├── docs
│   ├── ADR-Codex
│   │   └── 0001-initial-architecture.md
│   ├── ADR-Gemini
│   │   ├── 0001-initial-architecture.md
│   │   ├── 0002-real-time-vs-batch-simulation.md
│   │   └── 0003-dynamic-component-manifests.md
│   ├── ADR-claude
│   │   ├── 0001-canvas-based-graph-model.md
│   │   ├── 0002-bidirectional-cnl-conversion.md
│   │   ├── 0003-websocket-simulation-streaming.md
│   │   ├── 0004-sqlite-json-project-persistence.md
│   │   ├── 0005-parameter-sweep-engine.md
│   │   ├── 0006-component-template-system.md
│   │   └── 0007-job-store-persistence.md
│   ├── api_documentation.md
│   ├── archive
│   │   └── 02-Apr-2026-status-Jules.md
│   ├── developer-guide
│   │   └── adding_new_component.md
│   ├── neurocnl_runtime_alignment.md
│   ├── spinnaker2_integration_plan.md
│   ├── unified-dev-pipeline
│   │   └── neurosim
│   │       ├── GUARDRAILS.md
│   │       └── module.json
│   └── user-guide
│       └── designing_your_first_snn.md
├── issues-archive
│   ├── 001-beta-complete-sweep-job-lifecycle-and-status-flow.md
│   ├── 001-beta-surface-neurocnl-fidelity-and-backend-support-in-neurosim.md
│   ├── 001-multi-node-graph-bridge.md
│   ├── 002-beta-fix-frontend-analyzer-hotspots-and-dynamic-usage.md
│   ├── 002-bidirectional-graph-cnl-sync.md
│   ├── 002-prod-end-to-end-suite-for-canvas-cnl-simulation-and-export.md
│   ├── 003-beta-add-sweep-submit-poll-results-e2e-smoke.md
│   ├── 003-beta-complete-neurocnl-runtime-alignment.md
│   ├── 003-frontend-ui-migration.md
│   ├── 007-beta-rate-limiting.md
│   ├── 008-beta-authentication-layer.md
│   ├── 009-beta-structured-logging.md
│   ├── 01-f811-redefined-names.md
│   ├── 010-beta-component-library-caching.md
│   ├── 011-beta-expanded-frontend-preview-visualization.md
│   ├── 012-beta-security-md-and-changelog-md.md
│   ├── 013-prod-end-to-end-integration-tests.md
│   ├── 014-prod-real-nengo-simulation-backend.md
│   ├── 015-prod-container-hardening.md
│   ├── 016-prod-performance-optimization.md
│   ├── 017-prod-user-documentation.md
│   ├── 018-cross-param-tau-ref-tau-rc-invariant.md
│   ├── 019-preview-schema-missing-duration-cap.md
│   ├── 02-plw0602-global-state.md
│   ├── 020-simulation-determinism-seed-parameter.md
│   ├── 021-nir-export-endpoint.md
│   ├── 022-cnl-roundtrip-loses-node-coordinates.md
│   ├── 023-rate-limiter-429-integration-test.md
│   ├── 024-scientific-notation-round-trip-precision.md
│   ├── 03-arg001-unused-router-args.md
│   ├── 04-g004-try401-logging.md
│   ├── 05-pt011-pytest-raises-match.md
│   ├── 06-pth-pathlib-modernization.md
│   ├── 07-sim117-nested-with.md
│   ├── 08-plc0206-era001-dict-and-deadcode.md
│   ├── 09-npy002-numpy-random.md
│   ├── 10-ann-type-hints.md
│   ├── 10-neurosim-shared-shell-theme-and-preview-panels.md
│   ├── 11-d417-docstring-args.md
│   ├── 11-neurosim-shell-adapter-and-project-restoration.md
│   ├── 12-neurosim-desktop-graph-canvas.md
│   ├── 12-plc0415-inline-imports.md
│   ├── 13-plr2004-magic-numbers.md
│   ├── 14-plr0915-oversized-functions.md
│   ├── sent-001-prod-neurocnl-pipeline-single-source-of-truth.md
│   ├── sent-001-spinncloud-spinnaker2-simulation-backend.md
│   ├── sent-003-prod-real-async-simulation-lifecycle-websocket-and-cancellation.md
│   ├── sent-004-beta-fix-frontend-backend-wiring-and-environment-defaults.md
│   └── sent-spinnaker2_simulation_integration.md
├── jobs.db
├── large_graph.json
├── logs
│   └── neurocnl.log
├── neurosim
│   ├── GUARDRAILS.md
│   ├── __init__.py
│   ├── _canonical_bootstrap.py
│   ├── app
│   │   ├── __init__.py
│   │   ├── backends
│   │   │   ├── __init__.py
│   │   │   └── spinnaker2_backend.py
│   │   ├── limiter.py
│   │   ├── main.py
│   │   ├── middleware
│   │   │   ├── __init__.py
│   │   │   └── logging.py
│   │   ├── routers
│   │   │   ├── __init__.py
│   │   │   ├── components.py
│   │   │   ├── custom_nodes.py
│   │   │   ├── export.py
│   │   │   ├── generation.py
│   │   │   ├── nir_canvas.py
│   │   │   ├── preview.py
│   │   │   ├── projects.py
│   │   │   ├── simulation_ws.py
│   │   │   ├── spinnaker2.py
│   │   │   ├── sweep.py
│   │   │   ├── templates.py
│   │   │   └── validation.py
│   │   ├── schemas
│   │   │   ├── __init__.py
│   │   │   ├── canvas.py
│   │   │   ├── components.py
│   │   │   ├── export.py
│   │   │   ├── preview.py
│   │   │   ├── projects.py
│   │   │   ├── runtime.py
│   │   │   ├── sweep.py
│   │   │   └── templates.py
│   │   ├── services
│   │   │   ├── __init__.py
│   │   │   ├── canonical_editor_projection.py
│   │   │   ├── cnl_to_graph.py
│   │   │   ├── components.py
│   │   │   ├── export_generators.py
│   │   │   ├── job_store.py
│   │   │   ├── nir_support.py
│   │   │   ├── preview_runner.py
│   │   │   ├── project_store.py
│   │   │   ├── spinnaker2_store.py
│   │   │   ├── sweep_runner.py
│   │   │   └── validation_service.py
│   │   └── utils
│   │       ├── __init__.py
│   │       └── logging.py
│   ├── components
│   │   ├── __init__.py
│   │   ├── encoders
│   │   │   ├── delta_encoder.json
│   │   │   ├── rate_encoder.json
│   │   │   └── temporal_encoder.json
│   │   ├── neurons
│   │   │   ├── adaptive_lif.json
│   │   │   └── lif_population.json
│   │   ├── patterns
│   │   │   ├── cpg_oscillator.json
│   │   │   ├── lateral_inhibition.json
│   │   │   ├── reflex_arc.json
│   │   │   └── winner_take_all.json
│   │   └── synapses
│   │       ├── pes_synapse.json
│   │       ├── static_synapse.json
│   │       └── stdp_synapse.json
│   ├── contracts
│   │   ├── __init__.py
│   │   ├── canonical_editor_contracts.py
│   │   ├── canvas_contracts.py
│   │   ├── design_contracts.py
│   │   ├── project_contracts.py
│   │   └── simulation_contracts.py
│   ├── templates
│   │   ├── __init__.py
│   │   ├── cpg_oscillator.json
│   │   └── reflex_arc.json
│   └── tests
│       ├── README.md
│       ├── __init__.py
│       ├── conftest.py
│       ├── properties
│       │   ├── __init__.py
│       │   └── test_design_properties.py
│       ├── routers
│       │   ├── __init__.py
│       │   ├── test_canvas_to_canonical.py
│       │   ├── test_components.py
│       │   ├── test_components_canvas_filter.py
│       │   ├── test_custom_nodes_router.py
│       │   ├── test_export.py
│       │   ├── test_generation_canonical.py
│       │   ├── test_main.py
│       │   ├── test_nir_to_cnl_endpoint.py
│       │   ├── test_projects.py
│       │   ├── test_rate_limiting.py
│       │   ├── test_simulation_ws.py
│       │   ├── test_simulations.py
│       │   ├── test_spinnaker2.py
│       │   ├── test_sweep_lifecycle.py
│       │   ├── test_tau_invariant.py
│       │   ├── test_templates.py
│       │   └── test_validation.py
│       ├── services
│       │   ├── __init__.py
│       │   ├── test_canonical_editor_projection.py
│       │   ├── test_cnl_precision.py
│       │   ├── test_components_custom.py
│       │   ├── test_graph_to_cnl.py
│       │   ├── test_neurocnl_bridge_bootstrap.py
│       │   ├── test_preview_custom_node.py
│       │   ├── test_preview_runner.py
│       │   └── test_sweep_runner.py
│       ├── test_concurrency.py
│       ├── test_contracts.py
│       ├── test_integration.py
│       ├── test_neurocnl_integration.py
│       ├── test_preview_validation.py
│       ├── test_router_generation_endpoints.py
│       ├── test_simulation_integration.py
│       └── test_sweep_smoke_e2e.py
├── neurosim.egg-info
│   ├── PKG-INFO
│   ├── SOURCES.txt
│   ├── dependency_links.txt
│   ├── requires.txt
│   └── top_level.txt
├── neurosim_spec.md
├── projects.db
├── pyproject.toml
├── ruff_all_types.txt
├── ruff_debug.toml
├── ruff_errors.txt
├── ruff_errors_all.txt
├── ruff_everything.txt
├── ruff_full.txt
├── server.log
├── uv.lock
└── verify-contracts-local.sh
</directory_structure>

## Remote Testing Configuration

For dev, `REMOTE_HOST=dev@<dev-host>` can be used. For example, when the agent wants to test run the app, you can use `<dev-host>` as the server address.
