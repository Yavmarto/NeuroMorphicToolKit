# NeuroSim Code Review

Date: 2026-05-14 13:09 CEST

Reviewer: Codex

Scope: `Neurosim/` standalone module, with cross-checks against the suite-mounted `neurocnl/neurosim` package because the suite imports `neurosim` from `neurocnl` in normal root/neurocnl execution contexts.

## Executive Verdict

NeuroSim does not fully hold up as a general visual SNN simulator yet.

It does hold up better than a prototype in a narrow path: a one- or two-population LIF graph, especially the canonical sensory -> motor reflex arc, can be validated, previewed, swept, exported, and tested through a mostly coherent FastAPI backend. The Python test suite passes in the local Anaconda environment, and `ruff` plus `mypy` are clean.

The critical concern is semantic truthfulness. Several paths can report success while changing the intended graph meaning, ignoring important parameters, or returning mock data as if it were a real run. The highest-risk issues are:

- The repository contains two importable `neurosim` packages, and the one used depends on the current working directory.
- The NeuroCNL-backed "canonical" path accepts any two-node sensory/motor graph regardless of edge direction, then renders it as sensory -> motor.
- Graph `delay` is implemented as a Nengo low-pass synapse time constant, not an axonal/transmission delay.
- The local preview path claims it can preserve population-specific `threshold`, but the Nengo model builder never applies threshold.
- Parameter sweeps silently no-op invalid parameter paths and still complete.
- The SpiNNaker2 path returns zero-filled mock results as `completed` when the backend SDK is missing.

For a demo or exploratory canvas, this is salvageable. For a simulator whose output may inform hardware or scientific decisions, the current implementation needs hardening before it should be trusted.

## Review Inputs

Read:

- `AGENTS.md`
- `CODING_STYLE_GUIDE.md`
- `Neurosim/AGENTS.md`
- `Neurosim/CODING_STYLE_GUIDE.md`
- `Neurosim/pyproject.toml`
- `Neurosim/neurosim_spec.md`
- Key ADRs and docs under `Neurosim/docs/`
- Backend services, routers, contracts, component manifests, and tests under `Neurosim/neurosim/`
- Suite integration imports in `neurocnl/backend/app/main.py`
- Duplicate suite-mounted code under `neurocnl/neurosim/`

Commands run:

```bash
rtk uv run pytest neurosim/tests -q
```

Result: failed to resolve the uv environment because `neurosim[spinnaker2]` depends on `py-spinnaker2`, which uv could not find.

```bash
rtk /anaconda/anaconda3/bin/python3 -m pytest neurosim/tests -q
```

Result: `106 passed, 1 skipped, 8 warnings in 37.31s`.

```bash
rtk /anaconda/anaconda3/bin/python3 -m mypy neurosim
```

Result: `Success: no issues found in 47 source files`.

```bash
rtk /anaconda/anaconda3/bin/python3 -m ruff check neurosim
```

Result: `All checks passed!`.

## Findings

### P0. There are two `neurosim` packages, and import resolution changes by working directory

Evidence:

- From repo root, `import neurosim` resolved to `neurocnl/neurosim/__init__.py`.
- From `Neurosim/`, `import neurosim` resolved to `Neurosim/neurosim/__init__.py`.
- `neurocnl/backend/app/main.py:48-59` imports `neurosim.app.routers.*`.
- `neurocnl/backend/app/main.py:185-194` mounts those imported NeuroSim routers into the suite API.
- `Neurosim/neurosim/...` and `neurocnl/neurosim/...` are not identical. The `neurocnl/neurosim` copy includes newer canonical editor contracts and projection tests that the standalone `Neurosim/` copy does not.

Impact:

This is the biggest architecture risk in the review. A developer can run and fix tests under `Neurosim/` and still not change the code mounted by the suite. Conversely, suite behavior can improve or regress without the standalone module reflecting it. This makes review conclusions, test results, and production behavior ambiguous.

Recommendation:

Pick one owner for the importable `neurosim` package. Ideally, remove the duplicate package and make suite code depend on a single editable/local package. Until then, add an import-path guard or startup diagnostic that reports the resolved `neurosim.__file__`, and add CI jobs that test the exact package mounted by `neurocnl/backend/app/main.py`.

### P1. Canonical reflex-arc detection accepts reversed graphs and rewrites their meaning

Evidence:

- `Neurosim/neurosim/app/services/neurocnl_bridge.py:898-904` checks only that there are exactly two nodes, one edge, and node names include `sensory` and `motor`.
- `_resolve_reflex_arc()` at `Neurosim/neurosim/app/services/neurocnl_bridge.py:476-485` returns `graph.edges[0]` without checking source or target.
- `graph_to_canonical_cnl()` at `Neurosim/neurosim/app/services/neurocnl_bridge.py:461-473` always renders canonical sensory/motor lines when `can_use_neurocnl_generator()` is true.
- `build_connection_weight_sentence()` and `build_connection_delay_sentence()` at `Neurosim/neurosim/app/services/semantic_cnl.py:58-70` hard-code "connection from sensory neuron to motor neuron".

I verified a graph whose only edge is `motor -> sensory`; `can_use_neurocnl_generator()` returned `True`, and `graph_to_canonical_cnl()` emitted "connection from sensory neuron to motor neuron".

Impact:

This is a semantic inversion bug. Validation, preview support, and export support can bless a graph whose actual canvas topology is opposite the canonical text sent to NeuroCNL. That undermines the core promise of bidirectional canvas/CNL sync.

Recommendation:

Make the canonical predicate strict: exactly two LIF population nodes, roles exactly sensory and motor, exactly one static edge, and the edge must be sensory -> motor. The newer `neurocnl/neurosim/app/services/neurocnl_bridge.py:361-421` has a stricter `get_canonical_canvas_sync_issues()` helper that checks direction; port that guard into every path that calls `graph_to_canonical_cnl()`, not only live sync.

### P1. Edge delay is modeled as a synaptic filter, not as transmission delay

Evidence:

- Component docs define `delay` as "Time taken for a spike to reach the target" in `Neurosim/neurosim/components/synapses/static_synapse.json`.
- CNL generation renders "delay" in `Neurosim/neurosim/app/services/graph_to_cnl.py:80-86`.
- Local preview maps `delay` to `nengo.Connection(..., synapse=delay)` at `Neurosim/neurosim/app/services/preview_runner.py:102-104`.
- Python export does the same at `Neurosim/neurosim/app/routers/export.py:96-104`.

Impact:

In Nengo, `synapse` is a post-synaptic filtering model/time constant. It is not an axonal delay. So a user changing `delay` changes low-pass dynamics, not propagation latency. This can materially alter spike timing and voltage traces while presenting the parameter as a hardware-style delay.

Recommendation:

Rename this parameter in local Nengo paths to `synapse_tau` if filtering is intended, or implement/route real delay semantics separately. If true delay cannot be represented faithfully in Nengo, mark preview/export support approximate with an explicit warning and do not claim a faithful delay simulation.

### P1. Threshold is surfaced as a meaningful simulation parameter but ignored by local preview

Evidence:

- `threshold` is part of the LIF component manifest in `Neurosim/neurosim/components/neurons/lif_population.json`.
- `_uses_population_specific_preview_params()` treats `threshold`, `tau_ref`, and `tau_rc` as the parameters requiring local faithful preview at `Neurosim/neurosim/app/services/neurocnl_bridge.py:488-514`.
- `run_preview()` chooses the local model builder for that path at `Neurosim/neurosim/app/services/preview_runner.py:228-246`.
- `_build_ensemble()` applies `n_neurons`, `tau_rc`, and `tau_ref` only at `Neurosim/neurosim/app/services/preview_runner.py:40-56`. It never applies `threshold`.

Impact:

Threshold sweeps or threshold edits can appear supported while having no effect on local preview results. This is especially problematic because the code specifically identifies threshold as a reason to use the "faithful" local path.

Recommendation:

Either remove `threshold` from the set of local-preview-faithful parameters, or implement a neuron/model mapping where threshold genuinely affects dynamics. Add a regression test that two otherwise-identical graphs with different threshold values produce detectably different preview or are explicitly marked approximate/unsupported.

### P1. Parameter sweeps silently ignore invalid target paths and still complete

Evidence:

- `update_graph_parameter()` returns the unchanged graph for malformed paths at `Neurosim/neurosim/app/services/sweep_runner.py:43-47`.
- It also silently does nothing when a valid-looking node or edge id is missing at `Neurosim/neurosim/app/services/sweep_runner.py:51-60`.
- `run_sweep()` then runs every step and returns `completed` at `Neurosim/neurosim/app/services/sweep_runner.py:205-266`.
- `Neurosim/neurosim/tests/routers/test_sweep_lifecycle.py:58-82` acknowledges this gap but does not assert failure.

I verified these paths directly:

- `invalid.path` completed.
- `nodes.missing.tau_rc` completed.
- `edges.missing.weight` completed.

Impact:

Users can believe they swept a parameter while all simulations used the unchanged graph. This invalidates tuning results.

Recommendation:

Validate `parameter_path` at request time. Return 422 for malformed paths and failed/not-found for paths that do not resolve to exactly one mutable numeric parameter. Add tests for malformed path, missing node, missing edge, non-numeric parameter, and unsupported parameter.

### P1. SpiNNaker2 missing-dependency fallback reports completed zero data

Evidence:

- `SPINNAKER2_AVAILABLE` is false when import fails at `Neurosim/neurosim/app/backends/spinnaker2_backend.py:7-15`.
- `load()` logs that hardware features will be mocked at `Neurosim/neurosim/app/backends/spinnaker2_backend.py:44-45`.
- `run()` logs a mock run at `Neurosim/neurosim/app/backends/spinnaker2_backend.py:102-107`.
- `get_results()` returns empty spikes and zero voltage traces at `Neurosim/neurosim/app/backends/spinnaker2_backend.py:146-151`.
- The router returns `SimulationStatus.COMPLETED` at `Neurosim/neurosim/app/routers/spinnaker2.py:36-55`.

Impact:

This is dangerous for any hardware-facing workflow. A missing SDK or unavailable board can look like a successful simulation with quiet zero activity. That is not graceful degradation; it is a false success.

Recommendation:

Return a failed or degraded status with explicit `backend_support` metadata when `py-spinnaker2` is absent. Keep mock mode only behind an explicit test/dev flag, and include that flag in the response.

### P1. The product spec promises broad visual simulation, but runtime support intentionally fails closed beyond a tiny topology

Evidence:

- The spec describes drag-and-drop graph design, templates, multi-component libraries, preview, sweeps, and export in `Neurosim/neurosim_spec.md`.
- `neurocnl_bridge.py:3-8` documents that the NeuroCNL generator only supports a strictly defined single sensory -> motor reflex arc.
- `_topology_exceeds_reflex_arc()` at `Neurosim/neurosim/app/services/neurocnl_bridge.py:449-450` treats more than two nodes or more than one edge as unsupported.
- Preview and validation fail closed for those graphs at `Neurosim/neurosim/app/services/neurocnl_bridge.py:673-711`.

Impact:

Failing closed is honest for NeuroCNL fidelity, but it means the current implementation is not the workbench described by the spec. Most realistic graph-canvas designs cannot be simulated through the supported path.

Recommendation:

Clarify product status in README/spec/API responses: "canonical NeuroCNL-backed preview supports only sensory -> motor reflex arcs." If broader local-only preview is desired, separate it from canonical fidelity and label the output approximate.

### P2. Exporters generate unsafe or invalid output for ordinary identifiers/text

Evidence:

- Python export uses `node.id` directly as a Python variable at `Neurosim/neurosim/app/routers/export.py:84-91`.
- It interpolates labels and values directly into source at `Neurosim/neurosim/app/routers/export.py:84-105`.
- SVG export interpolates node names directly into XML text at `Neurosim/neurosim/app/routers/export.py:360-366`.
- NeuroML export interpolates `name` directly into XML attributes at `Neurosim/neurosim/app/routers/export.py:347-357`.

Impact:

Canvas ids like `sensor-1`, `1sensor`, or names containing quotes/angle brackets can produce invalid Python/XML/SVG. This is also an injection risk if exported artifacts are opened by other tools.

Recommendation:

Sanitize Python identifiers, escape XML/SVG text and attributes, and include round-trip/export tests with spaces, hyphens, quotes, `<`, `&`, and duplicate display names.

### P2. Async simulation lifecycle is only in-memory and lightly synchronized

Evidence:

- `SimulationJobStore` is a process-local dictionary at `Neurosim/neurosim/app/services/job_store.py:38-47`.
- There is no lock around job mutation at `Neurosim/neurosim/app/services/job_store.py:54-92`.
- Preview jobs are FastAPI background tasks at `Neurosim/neurosim/app/routers/preview.py:47-61`.
- Cancellation is cooperative and checked only between 100 ms chunks at `Neurosim/neurosim/app/services/preview_runner.py:252-276`.

Impact:

Jobs vanish on process restart, cannot be shared across workers, and may race under concurrent access. This is acceptable for local development but not durable enough for a production service or multi-worker deployment.

Recommendation:

Use the persistent job-store pattern already present elsewhere in the suite, or document NeuroSim jobs as single-process ephemeral. Add locks if keeping this in-memory store.

### P2. WebSocket streaming has weak error, disconnect, and cancellation behavior

Evidence:

- The WebSocket loop starts a worker thread via `anyio.to_thread.run_sync()` at `Neurosim/neurosim/app/routers/simulation_ws.py:85-100`.
- If the client disconnects during streaming, there is no cancellation token passed into `run_preview()`.
- Exceptions are reported with `print()` at `Neurosim/neurosim/app/routers/simulation_ws.py:59-60`, `95-96`, and `137-138`.

Impact:

Disconnected clients can leave simulations running. Errors bypass structured logging, and there is no job id that a caller can cancel or inspect later.

Recommendation:

Tie WebSocket simulations to job ids or explicit cancellation events, cancel on disconnect, and use structured logging instead of `print()`.

### P2. Request validation is inconsistent between preview and sweep

Evidence:

- `PreviewRequest.duration_ms` enforces `0 < duration_ms <= 500` at `Neurosim/neurosim/contracts/design_contracts.py:177-191`.
- `SweepRequest.simulation_duration_ms` has no equivalent validator at `Neurosim/neurosim/contracts/design_contracts.py:207-231`.
- `run_sweep()` only discovers invalid sweep duration when constructing a nested `PreviewRequest` at `Neurosim/neurosim/app/services/sweep_runner.py:224-227`.

Impact:

The sweep endpoint can accept a job and then fail later instead of rejecting invalid input up front. That gives a worse API contract and complicates frontend state handling.

Recommendation:

Reuse the preview duration validator for `simulation_duration_ms`, and reject invalid sweep requests with a normal 422.

### P2. Standalone frontend/build instructions are stale

Evidence:

- `Neurosim/neurosim_spec.md` describes a full Flutter frontend.
- `Neurosim/Makefile:5-18` assumes a `frontend/` directory and builds Flutter web.
- `Neurosim/neurosim/app/main.py:80-93` tries to serve `frontend/build/web`.
- There is no `Neurosim/frontend/` directory in this checkout.
- `Neurosim/README.md:17-23` now says the primary user journey is integrated into Studio/canvas rather than standalone.

Impact:

New contributors following `make dev` or the spec will hit missing directories. The documentation mixes the old standalone NeuroSim product shape with the current suite-integrated shape.

Recommendation:

Update `README.md`, `Makefile`, and `neurosim_spec.md` to match the current integrated reality. If standalone web is intentionally deprecated, remove or replace the stale `frontend` build path.

### P2. Dependency and tooling reproducibility is not reliable

Evidence:

- `rtk uv run pytest neurosim/tests -q` failed because the resolver tried to satisfy `neurosim[spinnaker2]`, whose `py-spinnaker2` dependency was unavailable.
- `Neurosim/pyproject.toml:33-35` declares the optional `spinnaker2` extra with `py-spinnaker2`.
- The tests passed only when using the existing Anaconda environment directly.
- `Neurosim/.pre-commit-config.yaml` passes `--config neurosim/pyproject.toml`, but the module root file is `Neurosim/pyproject.toml`, not `Neurosim/neurosim/pyproject.toml`.

Impact:

The project can be green on one machine and impossible to bootstrap in the standard uv workflow. CI or new developer setup may fail before code executes.

Recommendation:

Constrain `requires-python` to versions actually supported by all dependencies, do not resolve unavailable hardware extras in the default test environment, and fix pre-commit config paths relative to the intended invocation directory.

### P2. Components and templates are incomplete relative to the product surface

Evidence:

- Several component manifests are empty placeholders, including patterns, encoders, and advanced synapses. Loading components logs warnings for those files.
- `Neurosim/neurosim/app/services/components.py:95-127` skips invalid or empty manifests.
- The spec promises starter circuits and component categories under `Neurosim/neurosim_spec.md`, but the active component library is much smaller.

Impact:

The advertised workbench surface cannot be built from the current manifests. A frontend consuming `/components` or `/templates` will show missing categories or sparse capabilities.

Recommendation:

Either fill the manifests with valid component definitions or remove the placeholder files and adjust product docs/API expectations.

### P3. Project persistence is local, global, and under-specified

Evidence:

- `ProjectStore` defaults to `projects.db` in the process working directory at `Neurosim/neurosim/app/services/project_store.py:11-18`.
- The router creates/list/gets projects through a single global `_projects_store` at `Neurosim/neurosim/app/routers/projects.py:16-26`.
- There is no user/session namespace, no update endpoint, and no delete endpoint in the active router.

Impact:

This is okay for local prototypes, but it is not a multi-user or suite-grade persistence model. It can also create different databases depending on process cwd.

Recommendation:

Make the database path explicit and environment-configured, document single-user scope, and add user/project ownership before exposing this in a shared service.

### P3. Raw CNL repair is intentionally lossy, but the API does not make that loud enough

Evidence:

- `cnl_to_graph()` documents itself as lossy repair at `Neurosim/neurosim/app/services/cnl_to_graph.py:192-207`.
- It parses only a few regex sentence shapes at `Neurosim/neurosim/app/services/cnl_to_graph.py:15-31`.
- Unknown or unsupported lines are ignored at `Neurosim/neurosim/app/services/cnl_to_graph.py:228-262`.
- `/api/neurosim/parse-cnl` returns a `CanvasGraph`, not a response with warnings/errors, at `Neurosim/neurosim/app/routers/generation.py:31-57`.

Impact:

A caller can submit CNL that partially parses and receive a graph without knowing which semantics were discarded.

Recommendation:

Return a sync response with `warnings` and `ignored_lines`, or reserve raw repair for an explicitly named endpoint. Prefer canonical import contracts for any semantically meaningful flow.

## What Works Well

- Contracts are centralized in `neurosim/contracts/design_contracts.py`, and schema modules re-export from contracts rather than redefining shapes.
- Unknown node components are rejected or marked unsupported in support assessment.
- The code has a decent amount of router/service/property coverage compared with many early-stage modules.
- The current implementation fails closed for topologies outside the canonical NeuroCNL path, which is safer than pretending multi-node NeuroCNL synthesis exists.
- `ruff` and `mypy` are clean in the Anaconda environment.
- The canonical NeuroCNL handoff direction in `neurocnl` is conceptually sounder than raw regex repair.

## Test Coverage Gaps To Add

Add focused tests for:

- `can_use_neurocnl_generator()` rejects motor -> sensory direction.
- `graph_to_canonical_cnl()` cannot rewrite a reversed edge.
- `threshold` edits either affect preview results or mark support approximate/unsupported.
- `delay` semantics are explicitly tested as filter-vs-delay, or renamed.
- `update_graph_parameter()` rejects malformed and missing paths.
- Sweep endpoint returns 422 for invalid `simulation_duration_ms`.
- SpiNNaker2 missing SDK returns degraded/failed, not completed zero data.
- Python/SVG/NeuroML export escapes hostile names and sanitizes identifiers.
- Import resolution for the exact suite-mounted package is pinned in CI.
- `uv run pytest neurosim/tests -q` succeeds in a clean environment.

## Recommended Fix Order

1. Resolve the duplicate `neurosim` package ownership and import ambiguity.
2. Harden canonical graph validation: direction, component types, synapse type, ids, and edge role.
3. Fix or relabel preview semantics for `delay` and `threshold`.
4. Make parameter sweep path validation strict.
5. Change SpiNNaker2 fallback from completed mock results to explicit degraded/failed capability.
6. Repair the uv/pre-commit/tooling path so new developers and CI can reproduce the test run.
7. Update stale frontend/spec docs to match the suite-integrated product shape.
8. Add export escaping/sanitization and persistence scope hardening.

## Implementation Plan

This plan should be executed as a Tier 0 stabilization lane before broad NeuroSim feature work. The ordering is intentional: first make sure the suite edits and tests the same `neurosim` package, then make graph meaning truthful, then make simulation/export/job behavior honest.

### Phase 0: Confirm Ownership and Freeze the Write Set

Priority: P0

Goal: Make the implementation target unambiguous before code changes begin.

Write set:

- `Neurosim/neurosim/**`
- `neurocnl/neurosim/**`
- `neurocnl/backend/app/main.py`
- `suite_api/domains/neurosim/router.py`
- NeuroSim packaging/test docs
- Root task/docs references where needed

Steps:

1. Decide whether the canonical package lives under `Neurosim/neurosim` or `neurocnl/neurosim`.
2. Generate a file-level diff between both package copies.
3. Preserve newer canonical editor work currently present under `neurocnl/neurosim`, including canonical editor contracts, projection services, and tests.
4. Preserve standalone module docs and packaging from `Neurosim/` where still relevant.
5. Add a small runtime diagnostic or test helper that records `neurosim.__file__` for the suite-mounted API.
6. Add a test that imports `neurocnl.backend.app.main` and verifies the mounted NeuroSim router comes from the intended package path.

Verification:

```bash
rtk /anaconda/anaconda3/bin/python3 - <<'PY'
import neurosim
print(neurosim.__file__)
PY
```

```bash
rtk /anaconda/anaconda3/bin/python3 -m pytest neurosim/tests -q
```

Exit criteria:

- There is one documented package owner.
- Running from repo root, `neurocnl/`, and `Neurosim/` no longer changes the intended suite behavior.
- Developers know which tree to edit for suite-mounted NeuroSim fixes.

### Phase 1: Harden Canonical Canvas Semantics

Priority: P0

Goal: Prevent NeuroSim from accepting or generating canonical CNL that changes graph meaning.

Key files:

- `neurosim/app/services/neurocnl_bridge.py`
- `neurosim/app/services/semantic_cnl.py`
- `neurosim/app/services/graph_to_cnl.py`
- `neurosim/app/routers/generation.py`
- `neurosim/tests/services/test_neurocnl_bridge_bootstrap.py`
- `neurosim/tests/routers/test_generation.py`
- `neurosim/tests/routers/test_validation.py`

Steps:

1. Replace `can_use_neurocnl_generator()` with a strict canonical support function.
2. Require exactly two nodes and exactly one edge.
3. Require normalized node roles to be exactly `sensory` and `motor`.
4. Require both nodes to be `lif_population` unless a tested, documented canonical extension is introduced.
5. Require the only edge to point from sensory to motor.
6. Require the edge synapse type to be `static_synapse` or absent/defaulted to static.
7. Reject reversed motor -> sensory graphs with `canonical_connection_direction`.
8. Reject unsupported components and synapse models with structured support metadata.
9. Route `graph_to_canonical_cnl()` through this strict validator.
10. Make `/api/neurosim/generate-cnl`, `/validate`, `/preview`, `/sweep`, and `/export/*` use the same support judgment.

Tests to add:

- Reversed motor -> sensory edge is rejected by canonical support.
- Reversed motor -> sensory edge is not rendered as sensory -> motor CNL.
- Three-node graph remains unsupported with `topology_exceeds_reflex_arc`.
- Non-LIF sensory/motor graph is rejected or clearly approximate.
- Non-static synapse is rejected or clearly approximate.
- Canonical sensory -> motor graph still passes.

Verification:

```bash
rtk /anaconda/anaconda3/bin/python3 -m pytest neurosim/tests/routers/test_generation.py neurosim/tests/routers/test_validation.py neurosim/tests/test_neurocnl_integration.py -q
```

Exit criteria:

- No supported NeuroCNL-backed path can invert canvas direction.
- Canvas validation, CNL generation, preview support, sweep support, and export support agree on canonical eligibility.

### Phase 2: Fix Preview Fidelity for `delay` and `threshold`

Priority: P0

Goal: Stop presenting unimplemented simulation parameters as faithful.

Key files:

- `neurosim/app/services/preview_runner.py`
- `neurosim/app/services/neurocnl_bridge.py`
- `neurosim/components/neurons/lif_population.json`
- `neurosim/components/synapses/static_synapse.json`
- `neurosim/app/routers/export.py`
- preview/export tests

Decision A: `delay`

Current behavior maps graph `delay` to `nengo.Connection(..., synapse=delay)`, which is filtering, not axonal delay. Choose one path:

1. Rename local Nengo behavior to `synapse_tau` and keep `delay` out of faithful local Nengo simulation.
2. Implement actual delay semantics if a supported Nengo representation is selected and tested.
3. Mark non-zero delay approximate/unsupported for local preview and Python export.

Decision B: `threshold`

Current behavior includes `threshold` in support/fidelity decisions but does not apply it to the Nengo neuron model. Choose one path:

1. Implement a neuron model or parameter mapping where threshold affects preview dynamics.
2. Remove threshold from "faithful local preview" support and mark threshold-specific preview approximate/unsupported.

Tests to add:

- Changing threshold either changes preview behavior or returns explicit approximate/unsupported support metadata.
- Non-zero delay either changes actual delay semantics or returns explicit approximate/unsupported support metadata.
- Python export uses the same fidelity label as preview for delay/threshold.
- Existing tau_rc/tau_ref behavior remains covered.

Verification:

```bash
rtk /anaconda/anaconda3/bin/python3 -m pytest neurosim/tests/services/test_preview_runner.py neurosim/tests/routers/test_simulations.py neurosim/tests/routers/test_export.py -q
```

Exit criteria:

- NeuroSim never claims faithful preview/export for a parameter it ignores or models as a different physical concept.

### Phase 3: Make Sweep Paths Strict

Priority: P0

Goal: Prevent no-op sweeps from returning completed results.

Key files:

- `neurosim/app/services/sweep_runner.py`
- `neurosim/contracts/design_contracts.py`
- `neurosim/app/routers/sweep.py`
- `neurosim/tests/services/test_sweep_runner.py`
- `neurosim/tests/routers/test_sweep_lifecycle.py`

Steps:

1. Add a resolver that parses `nodes.<node_id>.<param>` and `edges.<edge_id>.<param>`.
2. Return a typed resolution result rather than silently returning the original graph.
3. Validate that the target element exists exactly once.
4. Validate that the target parameter is known for the node component or synapse type.
5. Validate that the target parameter is numeric and mutable.
6. Reject malformed paths at request validation time when possible.
7. Reject missing targets before queuing a background job.
8. Add a validator for `SweepRequest.simulation_duration_ms` matching `PreviewRequest.duration_ms`.

Tests to add:

- `invalid.path` returns 422 or failed before simulation.
- `nodes.missing.tau_rc` fails.
- `edges.missing.weight` fails.
- Sweeping `name` or other non-numeric parameters fails.
- Sweeping unsupported component parameters fails.
- `simulation_duration_ms <= 0` and `> 500` return 422.
- Valid node and edge numeric sweeps still complete.

Verification:

```bash
rtk /anaconda/anaconda3/bin/python3 -m pytest neurosim/tests/services/test_sweep_runner.py neurosim/tests/routers/test_sweep_lifecycle.py -q
```

Exit criteria:

- A completed sweep always proves that each step actually mutated the requested parameter.

### Phase 4: Make SpiNNaker2 Capability Truthful

Priority: P1

Goal: Stop returning completed all-zero mock data for missing hardware or SDK paths.

Key files:

- `neurosim/app/backends/spinnaker2_backend.py`
- `neurosim/app/routers/spinnaker2.py`
- `neurosim/tests/routers/test_spinnaker2.py`
- `Neurosim/docs/spinnaker2_integration_plan.md`

Steps:

1. Replace implicit mock fallback with explicit capability state.
2. When `py-spinnaker2` is missing, return failed/degraded response metadata, not completed results.
3. Add an opt-in mock mode for tests/dev only, for example via explicit request option or environment variable.
4. Include `backend_support` or equivalent metadata showing `missing_sdk`, `mock_mode`, or `hardware_unavailable`.
5. Ensure docs distinguish real hardware, SDK simulator, local mock, and unsupported states.

Tests to add:

- Missing SDK returns failed/degraded.
- Explicit mock mode returns completed only with visible mock metadata.
- Unknown run id still returns 404.
- Hardware exceptions do not collapse into completed zero data.

Verification:

```bash
rtk /anaconda/anaconda3/bin/python3 -m pytest neurosim/tests/routers/test_spinnaker2.py -q
```

Exit criteria:

- A caller cannot mistake missing SpiNNaker2 support for a successful simulation.

### Phase 5: Repair Reproducible Tooling

Priority: P1

Goal: Make the documented verification command work in a clean environment.

Key files:

- `Neurosim/pyproject.toml`
- `Neurosim/.pre-commit-config.yaml`
- CI/test docs
- optional dependency docs

Steps:

1. Constrain `requires-python` to versions the dependencies actually support.
2. Keep `spinnaker2` optional and out of default test resolution.
3. Remove or repair any dependency-group/default-extra behavior that forces `py-spinnaker2`.
4. Fix pre-commit config paths so they point at `Neurosim/pyproject.toml` from the intended invocation directory.
5. Document one canonical local verification command.
6. Add a CI check for that command if CI is in scope.

Verification:

```bash
rtk uv run pytest neurosim/tests -q
rtk uv run python -m mypy neurosim
rtk uv run ruff check neurosim
```

Exit criteria:

- The uv-based verification path works without relying on a pre-existing Anaconda environment.

### Phase 6: Sanitize Exporters

Priority: P1

Goal: Ensure exports are syntactically valid and not injection-prone.

Key files:

- `neurosim/app/routers/export.py`
- `neurosim/tests/routers/test_export.py`

Steps:

1. Add a Python identifier sanitizer for exported variable names.
2. Maintain a mapping from canvas node id to sanitized Python variable.
3. Escape string literals in generated Python.
4. Escape XML/SVG attributes and text nodes.
5. Decide how to handle duplicate display names and duplicate sanitized identifiers.
6. Add metadata comments that preserve original ids/names safely.

Tests to add:

- Node id `1-sensory node` exports runnable Python.
- Node name containing quotes exports valid Python.
- Node name containing `<`, `>`, `&`, and quotes exports valid SVG/NeuroML.
- Duplicate names do not collide.

Verification:

```bash
rtk /anaconda/anaconda3/bin/python3 -m pytest neurosim/tests/routers/test_export.py -q
```

Exit criteria:

- Export text is valid for ordinary user-provided ids and names.

### Phase 7: Make Runtime and Persistence Scope Explicit

Priority: P2

Goal: Prevent local-only runtime assumptions from looking production-grade.

Key files:

- `neurosim/app/services/job_store.py`
- `neurosim/app/routers/preview.py`
- `neurosim/app/routers/simulation_ws.py`
- `neurosim/app/services/project_store.py`
- `neurosim/app/routers/projects.py`
- README/API docs

Steps:

1. Decide whether NeuroSim jobs are explicitly local/ephemeral or should reuse the suite persistent job-store pattern.
2. If local/ephemeral, document that in API metadata and docs.
3. Add locking around job-store mutation if multi-threaded background execution remains.
4. Pass cancellation state into WebSocket simulations and stop work on disconnect.
5. Replace `print()` in WebSocket error paths with structured logging.
6. Make project database path explicit via configuration.
7. Document project persistence as single-user unless ownership/auth is implemented.

Tests to add:

- Cancelled WebSocket/preview work does not keep streaming as completed.
- Job cancellation state is respected.
- Project store uses configured path in tests.

Verification:

```bash
rtk /anaconda/anaconda3/bin/python3 -m pytest neurosim/tests/routers/test_simulation_ws.py neurosim/tests/routers/test_projects.py neurosim/tests/test_concurrency.py -q
```

Exit criteria:

- Runtime and persistence responses accurately state their durability and cancellation behavior.

### Phase 8: Reconcile Product Docs, Frontend Claims, and Component Manifests

Priority: P2

Goal: Make the public promise match the implementation.

Key files:

- `Neurosim/README.md`
- `Neurosim/Makefile`
- `Neurosim/neurosim_spec.md`
- `Neurosim/docs/api_documentation.md`
- `Neurosim/docs/spinnaker2_integration_plan.md`
- `neurosim/components/**`
- `neurosim/templates/**`

Steps:

1. Update README to state that NeuroSim is currently suite-integrated through Studio/canvas, not a standalone Flutter frontend in this checkout.
2. Replace or remove `make dev-web` if `frontend/` is not present.
3. Mark broad drag-and-drop visual SNN simulation as roadmap unless implementation catches up.
4. Fill or remove empty component/template placeholder files.
5. Align API docs with support metadata and fail-closed behavior.
6. Add "supported today" and "roadmap" sections to avoid over-claiming.

Verification:

```bash
rtk rg -n "frontend|flutter build|broad visual|SpiNNaker2|mock|approximate|unsupported" Neurosim/README.md Neurosim/Makefile Neurosim/neurosim_spec.md Neurosim/docs
```

Exit criteria:

- A new contributor can follow docs without hitting missing frontend directories or assuming unsupported graph simulation works.

### Full Stabilization Gate

Run after Phases 1-8, adjusted for the final package ownership decision:

```bash
rtk uv run pytest neurosim/tests -q
rtk uv run python -m mypy neurosim
rtk uv run ruff check neurosim
```

If NeuroSim remains suite-mounted through `neurocnl`, also run:

```bash
rtk uv run pytest neurocnl/neurosim/tests -q
rtk uv run pytest backend/tests/test_neurosim_handoff_router.py -q
```

For suite-visible contract changes, also run the root integration checks required by `AGENTS.md`:

```bash
rtk python3 -m pytest tests/integration/test_cross_module.py
rtk python3 -m pytest tests/integration/test_teensy_e2e.py
```

Final acceptance:

- No duplicate-package ambiguity remains.
- All canonical graph paths agree on support and direction.
- Preview/export support claims match actual simulated semantics.
- Sweeps cannot silently no-op.
- Hardware/mock/degraded states are explicit.
- Verification is reproducible from documented commands.
- Docs describe the product that exists, not the product that used to be planned.

## Bottom Line

The implementation is not random or careless; there is a real architecture trying to emerge. But the logic does not yet support the full product claims, and a few current success states are misleading. The safest interpretation is:

- Canonical sensory -> motor reflex arcs: mostly viable, with direction and parameter-fidelity fixes needed.
- General visual SNN simulation: not yet viable.
- Hardware-oriented confidence: not viable until mock/degraded states are made explicit.
- Suite integration: risky until the duplicate package/import-path problem is resolved.
