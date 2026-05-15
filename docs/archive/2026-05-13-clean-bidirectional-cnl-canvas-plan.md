# Clean Bidirectional CNL-Canvas Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the current lossy `CNL <-> Canvas` sync with one canonical editor document so CNL edits and canvas edits become two projections of the same underlying semantic model.

**Architecture:** Introduce a typed canonical editor contract backed by `NetworkIR` semantics and round-trip metadata, then project that contract into the NeuroSim canvas view model and back through typed patch operations instead of regex repair. Keep honest degradation: unsupported or advisory-only semantics must remain attached to the canonical document and visible in the UI, never silently dropped.

**Tech Stack:** Python 3 backend services, FastAPI routers, `pydantic` contracts, `neurocnl` IR/NIR document helpers, Flutter, Riverpod, NeuroSim canvas contracts, repo docs and regression tests.

---

## Scope

Write set for the implementation this plan describes:

- `neurocnl/neurocnl/**`
- `neurocnl/neurosim/**`
- `neurocnl/frontend/**`
- `docs/**` only where semantic ownership, support boundaries, or editor invariants become user-visible

Out of scope for the first implementation:

- multi-module launcher changes
- hardware/runtime execution work
- broad visual redesign of the canvas UI
- expanding the supported semantic subset beyond what `NetworkIR` and the current NIR bridge can already represent honestly

## Problem Statement

The current implementation is not a clean bidirectional system:

1. The frontend canvas edits a NeuroSim `CanvasGraph`, not a canonical NIR or IR-backed document.
2. Canvas-to-CNL sync is intentionally strict and only accepts a canonical two-node sensory-to-motor reflex arc.
3. CNL-to-canvas sync uses `cnl_to_graph(...)`, which is explicitly documented as a lossy local repair path.
4. UI-side debounce regressions have been addressed, but semantic round-trip fidelity has not.
5. The app currently mixes three shapes:
   - CNL text
   - `NetworkIR` and NIR-backed generation results
   - NeuroSim `CanvasGraph`

The result is predictable drift: view synchronization can be stable while semantic synchronization is not.

## Target Invariant

After this refactor, the Studio must obey one invariant:

> Inside the app, one canonical editor document owns semantic truth. CNL text and canvas state are derived views of that document, and every user edit is applied back to that same document through typed transformations.

Implications:

- CNL edits compile into the canonical document.
- Canvas edits mutate the canonical document through typed operations.
- Export and generate read from the canonical document.
- Unsupported semantics remain attached as annotations or diagnostics.
- The canvas may refuse to edit unsupported semantics, but it may not silently erase them.

## Proposed Canonical Model

Introduce a new editor-owned contract with three responsibilities:

1. Semantic payload:
   - `NetworkIR`-equivalent populations, connections, timing, weights, and supported advisory metadata.
2. View payload:
   - canvas layout metadata such as positions, visibility, and viewport.
3. Fidelity payload:
   - structured annotations for:
     - executable semantics
     - advisory semantics
     - unsupported semantics
     - blocked canvas mutations

Recommended shape:

- backend canonical contract:
  - `neurocnl/neurosim/contracts/canonical_editor_contracts.py`
- frontend mirror model:
  - `neurocnl/frontend/lib/models/canonical_editor_document.dart`

This model is not a raw `nir.NIRGraph` and not the existing NeuroSim `CanvasGraph`. It is the editor document that preserves enough semantic intent to project honestly to both CNL and canvas.

## File Structure

### New files

- `neurocnl/neurosim/contracts/canonical_editor_contracts.py`
  - typed editor document, canvas projection model, fidelity annotations, mutation requests
- `neurocnl/neurosim/app/services/canonical_editor_projection.py`
  - `CNL -> canonical`, `canonical -> canvas`, `canvas mutation -> canonical`, `canonical -> CNL`
- `neurocnl/neurosim/tests/services/test_canonical_editor_projection.py`
  - backend round-trip and degradation tests
- `neurocnl/frontend/lib/models/canonical_editor_document.dart`
  - frontend mirror of the canonical editor contract
- `neurocnl/frontend/lib/providers/canonical_editor_provider.dart`
  - Riverpod owner of the canonical document
- `neurocnl/frontend/test/providers/canonical_editor_provider_test.dart`
  - frontend state-model regression tests

### Existing files to modify

- `neurocnl/neurocnl/cnl/document.py`
  - extend document helpers so canonical round-trip metadata can be rendered and re-imported consistently
- `neurocnl/neurosim/app/routers/generation.py`
  - replace direct `CanvasGraph <-> CNL` sync with canonical-editor surfaces
- `neurocnl/neurosim/app/services/neurocnl_bridge.py`
  - move strict reflex-arc checks behind canonical projection support assessment
- `neurocnl/neurosim/app/services/cnl_to_graph.py`
  - demote or isolate lossy repair behavior so it is not the live sync path
- `neurocnl/frontend/lib/providers/canvas/sync_provider.dart`
  - consume canonical-editor endpoints instead of raw `repairCnl(...)` for live sync
- `neurocnl/frontend/lib/providers/canvas/canvas_provider.dart`
  - stop owning semantic truth; own only canvas-local view state and mutation intents
- `neurocnl/frontend/lib/screens/studio_screen.dart`
  - rewire bidirectional sync around the canonical editor provider
- `neurocnl/frontend/test/screens/studio_screen_test.dart`
  - replace stub-only regression coverage with canonical end-to-end provider flow assertions
- `docs/current tasks/MASTER_TASK_ORDER.md`
  - keep task order aligned with the new invariant and execution sequence

### Docs likely to update during implementation

- `neurocnl/docs/support_matrix.md`
- `neurocnl/docs/PRE_BETA_READINESS_REVIEW.md`

Only update these if the implementation changes support claims or user-visible editor guarantees.

## Implementation Plan

### Task 1: Define the Canonical Editor Contract

**Files:**
- Create: `neurocnl/neurosim/contracts/canonical_editor_contracts.py`
- Create: `neurocnl/frontend/lib/models/canonical_editor_document.dart`
- Test: `neurocnl/neurosim/tests/services/test_canonical_editor_projection.py`

- [ ] Define backend contract types for:
  - semantic nodes and connections
  - canvas layout metadata
  - fidelity annotations
  - canvas-edit mutation requests
  - sync diagnostics

- [ ] Mirror the contract in Flutter with JSON serialization and stable field names.

- [ ] Add contract tests asserting:
  - semantic payload survives JSON round-trip
  - layout metadata survives JSON round-trip
  - unsupported/advisory annotations survive JSON round-trip

- [ ] Verify with:

```bash
PYTHONPATH=neurocnl python3 -m pytest neurocnl/neurosim/tests/services/test_canonical_editor_projection.py -v
cd neurocnl/frontend && flutter test test/providers/canonical_editor_provider_test.dart
```

- [ ] Commit:

```bash
git add neurocnl/neurosim/contracts/canonical_editor_contracts.py \
  neurocnl/neurosim/tests/services/test_canonical_editor_projection.py \
  neurocnl/frontend/lib/models/canonical_editor_document.dart \
  neurocnl/frontend/test/providers/canonical_editor_provider_test.dart
git commit -m "feat: add canonical editor document contracts"
```

### Task 2: Build Canonical Transformations on the Backend

**Files:**
- Create: `neurocnl/neurosim/app/services/canonical_editor_projection.py`
- Modify: `neurocnl/neurocnl/cnl/document.py`
- Modify: `neurocnl/neurosim/app/services/neurocnl_bridge.py`
- Test: `neurocnl/neurosim/tests/services/test_canonical_editor_projection.py`

- [ ] Implement deterministic transformations:
  - `canonical_from_cnl(spec_text)`
  - `canonical_to_cnl(document)`
  - `canvas_from_canonical(document)`
  - `apply_canvas_mutation(document, mutation)`

- [ ] Keep unsupported or metadata-only semantics attached to fidelity annotations instead of deleting them during projection.

- [ ] Use `neurocnl.cnl.document` helpers where possible so round-trip metadata remains owned by `neurocnl`, not duplicated in NeuroSim.

- [ ] Add tests for:
  - canonical reflex arc round-trip
  - threshold/tau/weight/delay edits from canvas back into canonical state
  - unsupported multi-node semantics preserved as annotations
  - comments and round-trip metadata preserved in canonical-to-CNL rendering

- [ ] Verify with:

```bash
PYTHONPATH=neurocnl python3 -m pytest neurocnl/neurosim/tests/services/test_canonical_editor_projection.py -v
```

- [ ] Commit:

```bash
git add neurocnl/neurosim/app/services/canonical_editor_projection.py \
  neurocnl/neurocnl/cnl/document.py \
  neurocnl/neurosim/app/services/neurocnl_bridge.py \
  neurocnl/neurosim/tests/services/test_canonical_editor_projection.py
git commit -m "feat: add canonical CNL and canvas projections"
```

### Task 3: Replace Live Sync Endpoints with Canonical Editor Surfaces

**Files:**
- Modify: `neurocnl/neurosim/app/routers/generation.py`
- Modify: `neurocnl/neurosim/app/services/cnl_to_graph.py`
- Test: `neurocnl/neurosim/tests/routers/test_generation.py`

- [ ] Replace `generate-cnl` and `parse-cnl` behavior so live sync does not rely on lossy repair as its primary path.

- [ ] Recommended endpoint behavior:
  - `POST /api/neurosim/parse-cnl`: return canonical editor document plus projected canvas
  - `POST /api/neurosim/generate-cnl`: accept canonical document or a typed mutation payload, then return canonical document plus rendered CNL

- [ ] Keep a clearly named fallback import route for lossy repair only if needed for legacy templates or one-time imports. Do not leave it on the main live-sync path.

- [ ] Add router tests for:
  - canonical reflex arc returns 200 with canvas projection and CNL
  - unsupported semantics return structured diagnostics, not silent graph truncation
  - legacy lossy import route is explicitly marked approximate

- [ ] Verify with:

```bash
PYTHONPATH=neurocnl python3 -m pytest neurocnl/neurosim/tests/routers/test_generation.py -v
```

- [ ] Commit:

```bash
git add neurocnl/neurosim/app/routers/generation.py \
  neurocnl/neurosim/app/services/cnl_to_graph.py \
  neurocnl/neurosim/tests/routers/test_generation.py
git commit -m "feat: move live CNL-canvas sync to canonical editor endpoints"
```

### Task 4: Make the Frontend Canonical Document the Source of Truth

**Files:**
- Create: `neurocnl/frontend/lib/providers/canonical_editor_provider.dart`
- Modify: `neurocnl/frontend/lib/providers/canvas/sync_provider.dart`
- Modify: `neurocnl/frontend/lib/providers/canvas/canvas_provider.dart`
- Test: `neurocnl/frontend/test/providers/canonical_editor_provider_test.dart`

- [ ] Add a new provider that owns the canonical editor document.

- [ ] Change `canvasProvider` so it owns:
  - selection
  - viewport
  - drag/connect state
  - pending canvas mutation intents

It must not own semantic truth after this task.

- [ ] Change sync flows so:
  - CNL text edits update the canonical document
  - canvas parameter edits dispatch typed mutations into the canonical document
  - the canvas view is recomputed from the canonical document

- [ ] Add provider tests for:
  - CNL edit updates canonical document and recomputes canvas
  - canvas parameter edit updates canonical document and recomputes CNL
  - unsupported canvas mutation surfaces a fidelity warning without deleting semantics

- [ ] Verify with:

```bash
cd neurocnl/frontend && flutter test test/providers/canonical_editor_provider_test.dart
```

- [ ] Commit:

```bash
git add neurocnl/frontend/lib/providers/canonical_editor_provider.dart \
  neurocnl/frontend/lib/providers/canvas/sync_provider.dart \
  neurocnl/frontend/lib/providers/canvas/canvas_provider.dart \
  neurocnl/frontend/test/providers/canonical_editor_provider_test.dart
git commit -m "feat: make canonical editor provider own semantic sync state"
```

### Task 5: Rewire StudioScreen and Replace Stub-Level Sync Assumptions

**Files:**
- Modify: `neurocnl/frontend/lib/screens/studio_screen.dart`
- Modify: `neurocnl/frontend/test/screens/studio_screen_test.dart`

- [ ] Replace the current debounce-and-mirror logic so `StudioScreen` coordinates around the canonical editor provider instead of mirroring `specTextProvider` and `cnlSpecProvider` directly.

- [ ] Preserve the current good behavior:
  - debounce cancellation
  - no user-text clobbering in CNL mode
  - comments preserved on Canvas-to-CNL regeneration

- [ ] Remove test assumptions that a fake one-line canvas API proves semantic round-trip fidelity.

- [ ] Add widget tests for:
  - toggling CNL-to-canvas mode preserves canonical state
  - canvas parameter edit updates the visible CNL through canonical recomputation
  - unsupported semantics show a clear sync/fidelity banner instead of breaking the editor

- [ ] Verify with:

```bash
cd neurocnl/frontend && flutter test test/screens/studio_screen_test.dart
```

- [ ] Commit:

```bash
git add neurocnl/frontend/lib/screens/studio_screen.dart \
  neurocnl/frontend/test/screens/studio_screen_test.dart
git commit -m "feat: rewire studio screen around canonical bidirectional state"
```

### Task 6: Add Honest Round-Trip and Degradation Coverage

**Files:**
- Modify: `neurocnl/neurosim/tests/test_neurocnl_integration.py`
- Modify: `neurocnl/neurosim/tests/services/test_cnl_to_graph.py`
- Modify: `neurocnl/neurosim/tests/services/test_graph_to_cnl.py`
- Modify: `neurocnl/frontend/test/screens/studio_screen_test.dart`

- [ ] Add regression coverage for these paths:
  - `CNL -> canonical -> CNL`
  - `CNL -> canonical -> canvas -> canonical -> CNL`
  - canonical document with advisory-only semantics projected into canvas without semantic deletion
  - multi-node topology rejected for executable canvas editing but preserved in canonical fidelity state

- [ ] Demote old lossy repair tests so they describe import fallback behavior, not the live sync contract.

- [ ] Verify with:

```bash
PYTHONPATH=neurocnl python3 -m pytest \
  neurocnl/neurosim/tests/test_neurocnl_integration.py \
  neurocnl/neurosim/tests/services/test_cnl_to_graph.py \
  neurocnl/neurosim/tests/services/test_graph_to_cnl.py -v
cd neurocnl/frontend && flutter test test/screens/studio_screen_test.dart
```

- [ ] Commit:

```bash
git add neurocnl/neurosim/tests/test_neurocnl_integration.py \
  neurocnl/neurosim/tests/services/test_cnl_to_graph.py \
  neurocnl/neurosim/tests/services/test_graph_to_cnl.py \
  neurocnl/frontend/test/screens/studio_screen_test.dart
git commit -m "test: add canonical bidirectional round-trip coverage"
```

## Acceptance Criteria

The implementation is complete when all of the following are true:

1. The live editor no longer depends on lossy `cnl_to_graph(...)` repair for primary CNL-to-canvas sync.
2. One canonical editor document owns semantic truth across CNL, canvas, and export.
3. Canvas edits apply as typed mutations to canonical state, not as blind graph rewrites.
4. Unsupported semantics survive as fidelity annotations or explicit blocks, not silent deletion.
5. The reflex-arc subset still round-trips cleanly.
6. Existing debounce and comment-preservation fixes remain intact.
7. Tests prove semantic round-trip behavior, not just provider mirroring or UI debounce behavior.

## Risks and Mitigations

### Risk 1: Canonical model duplicates too much of `NetworkIR`

Mitigation:
- Keep the canonical document thin and projection-focused.
- Reuse `NetworkIR` field semantics and document helpers where possible.
- Avoid inventing a second independent semantic type system.

### Risk 2: Canvas cannot faithfully display all canonical semantics

Mitigation:
- Treat the canvas as a partial projection.
- Show non-editable annotations or blocked-edit diagnostics for unsupported structures.
- Do not widen support claims until honest projections exist.

### Risk 3: Legacy templates depend on lossy repair behavior

Mitigation:
- Keep an explicit fallback import route for legacy content.
- Label it approximate.
- Keep it out of the primary bidirectional editing path.

## Recommended Execution Order

1. Task 1
2. Task 2
3. Task 3
4. Task 4
5. Task 5
6. Task 6

Do not start Task 4 before Task 3 lands. Frontend state migration should happen only after the backend canonical contract is stable enough to avoid churn.
