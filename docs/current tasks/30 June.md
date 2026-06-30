# NMTK June 30 Implementation Plan

## Context

The earlier analysis (condensing CS history into 5 patterns) was directionally correct — NMTK is already
IR-centric, compiler-pass-structured, and plugin-driven. But it was written from architecture docs, not
code. Code exploration reveals things the doc-level analysis missed: some gaps are smaller than stated,
some blockers are more concrete, and a few "missing" things already exist but are unwired.

**What to do today (June 30):** Close the three most impactful gaps, one ruff sweep, one deletion.
Everything else is multi-day work that should NOT start until the P0 integration is verified working.

---

## Where the Analysis Was Right

- **Canvas ↔ training disconnect is real P0.** `SnnTorchAdapter` builds its own hardcoded `TinySnn`
  topology and ignores the NIR graph in the payload. Confirmed in `snntorch_adapter.py`.
- **`CanvasEdge` has no learning rule field.** Confirmed in `canvas.dart` (canvas editor model).
- **`deployment_mode` missing from `LearningRuleIR`.** Confirmed in `ir/types.py`.
- **Plugin architecture is working correctly** — constructor injection, not dynamic discovery. Keep it.

## Where the Analysis Was Incomplete or Off

- **`NetworkEdge` (not `CanvasEdge`) ALREADY has `hasLearningRule: bool` and `learningRule: String?`**
  in `network_graph.dart`. The data model exists; it's just not wired into the canonical projection.
  This is a wire-up, not a build.
- **`FidelityAnnotation` in `CanvasProjection`** already supports marking edges as `"unsupported"` or
  `"advisory"` with a message. Use this to surface learning rule backend constraints rather than
  building new UI chrome.
- **`planner.py`** is more complete than described — it has a full `BackendCapabilityProfile` registry
  with per-concept support verdicts across 13 backends. Lean on it, don't rewrite it.
- **The plugin system does NOT need entry points or dynamic discovery.** Constructor injection in
  `factory.py` is correct ponytail architecture. The analysis implied it needs "improvement" — it doesn't.
- **Lava exporter exists** (`lava_exporter.py`); the 501s are specifically on the `LavaOnlineAdapter`
  hardware path, not the full export pipeline.

---

## June 30 Tasks (Ordered by Impact)

### Task 1 — Fix canvas ↔ training disconnect (P0 blocker)

**Problem:** `SnnTorchAdapter.run()` builds a hardcoded 2-layer LIF topology (`TinySnn`). It never reads
`request.nir_graph`. The training panel submits a job but never serializes the canvas graph into the
payload. Result: every training run trains the same toy network regardless of what the user drew.

**Fix:**
1. `neurocnl/backend/app/services/training_service.py` — in `submit_training_job()`, compile the CNL
   spec from the request into a `NetworkIR`, serialize to NIR, and attach as `request.nir_graph`.
2. `neurocnl/neurocnl/training/snntorch_adapter.py` — in `run()`, deserialize `request.nir_graph` into
   a live `nir.NIRGraph` and build the snnTorch model from it using the existing `ModelConverter`
   (pivot at `converter/pivot.py`) instead of `TinySnn`. Fall back to `TinySnn` with a logged warning
   if `nir_graph` is absent (backwards compat).
3. `neurocnl/frontend/lib/` — in the training submit handler, export `CanvasGraph` to CNL (or pass
   the raw CNL from the editor state) in the job request body.

**Acceptance:** Submit a job with a 3-population canvas graph. The training loss curve reflects a 3-layer
network, not the hardcoded 2-layer one. Check via `GET /training/jobs/{id}/activity.npy` shape.

**Files:**
- `neurocnl/neurocnl/training/snntorch_adapter.py`
- `neurocnl/backend/app/services/training_service.py`
- `neurocnl/backend/app/schemas/training.py` (add `nir_graph: dict | None` to request schema)
- `neurocnl/frontend/lib/` (training submit handler — find exact file via Semble)

---

### Task 2 — Add `deployment_mode` to `LearningRuleIR` (foundational field)

**Problem:** Nothing prevents `online_learn` from being silently dropped when a non-Lava backend is
selected. No field exists to express intent; adapters can't check for it.

**Fix — minimal (4 lines of code):**
```python
# ir/types.py — in LearningRuleIR dataclass
deployment_mode: Literal["offline_train", "online_learn", "deploy_only"] = "offline_train"
```

Then in `nir_exporter.py`'s concept fidelity audit, add one check:
```python
if rule.deployment_mode == "online_learn" and backend not in ONLINE_LEARN_BACKENDS:
    raise CompileError(f"online_learn requires Lava/Loihi; {backend} supports offline_train only")
```

`ONLINE_LEARN_BACKENDS = {"lava", "loihi2"}` — derive from `capabilities.py` `concept_support` dict,
don't hardcode a new list.

**Files:**
- `neurocnl/neurocnl/ir/types.py`
- `neurocnl/neurocnl/export/nir_exporter.py`
- `neurocnl/backend/app/schemas/training.py` (expose in `TrainingRequest` if needed)

---

### Task 3 — Wire `hasLearningRule` into canonical canvas projection

**Problem:** `NetworkEdge.hasLearningRule` exists in `network_graph.dart` but `CanvasProjection`'s
`CanvasEdge` (in `canonical_editor_document.dart`) has no learning rule field. The visual editor is
blind to plasticity.

**Fix — use existing `FidelityAnnotation` mechanism:**
1. In `canonical_editor_document.dart`, add `hasLearningRule: bool` and `learningRuleKind: String?`
   to the `CanvasEdge` (canonical version). This mirrors what `NetworkEdge` already has.
2. In `canvas_projection_utils.dart` → `canvasGraphFromCanonical()`, copy these fields from projection
   edges into `CanvasGraph` edges (the editor model's `CanvasEdge.parameters` map is already
   `Map<String, dynamic>` — just add `"hasLearningRule"` and `"learningRuleKind"` keys).
3. In the edge painter (find via Semble: `"CanvasEdge painter"` or `"edge stroke"`), render plastic
   edges with a dashed stroke when `parameters["hasLearningRule"] == true`. One conditional, no new
   widget.
4. Add a `FidelityAnnotation` (kind: `"advisory"`, concept: `"learning_rule"`) to any edge whose
   `learningRuleKind` maps to an unsupported concept per the active backend's `capabilities.py`
   profile. Reuse `plan_backend_support()` from `planner.py` — don't re-implement the lookup.

**Files:**
- `neurocnl/frontend/lib/models/canonical_editor_document.dart`
- `neurocnl/frontend/lib/utils/canvas_projection_utils.dart`
- Edge painter file (locate via Semble before editing)

---

### Task 4 — Ruff auto-fix sweep (hygiene, unblocks CI)

219 of 557 ruff errors are auto-fixable. Run once:
```bash
cd /Users/yoshimartodihardjo/NeuroMorphicToolKit
ruff check --fix neurocnl/ suite_api/ Neurohub/ Neurosim/ Neurosense/ Neurochip/ Neurobench/
```

Then commit with message `chore: ruff auto-fix 219 violations`. Do not attempt manual fixes for the
remaining 338 — those are separate work with human judgment required.

---

### Task 5 — Delete `scratch.py` (30 seconds)

```bash
rm neurocnl/backend/app/scratch.py
```

It's a debug print file in production package space. No references, no consumers. Just delete it.

---

## What is NOT in scope for June 30

| Item | Why deferred |
|------|-------------|
| `.nmtk` ZIP bundle format | Multi-day; needs `NetworkIR.to_dict()` + Dart zip writer |
| BindsNET adapter | No NIR bridge; needs research before implementation |
| Lava online learning adapter | Needs real Lava hardware for validation |
| Hardware export stubs (BrainScaleS, SpiNNaker) | Multi-day, hardware-specific |
| Three-factor / R-STDP rules | Depends on `reward_signal` field + reward node UI |
| Neurochip frontend | 0 Dart files; full sprint, not a day |
| 338 manual ruff fixes | Judgment calls; not a blind automation job |

---

## Verification

After all five tasks:

1. **Training integration:** Draw a 4-node network in neurocnl canvas, submit training job, confirm
   `activity.npy` shape reflects 4 populations (not the hardcoded 2).
2. **Deployment mode guard:** Submit a `LearningRuleIR` with `deployment_mode="online_learn"` targeting
   `snntorch`; confirm `CompileError` is raised with actionable message.
3. **Canvas visual:** Open a network with at least one STDP edge; confirm dashed stroke renders.
   Confirm `FidelityAnnotation` appears if backend doesn't support STDP.
4. **Ruff:** `ruff check .` reports ≤338 errors (no new auto-fixable ones introduced).
5. **`scratch.py` gone:** `ls neurocnl/backend/app/scratch.py` returns 404.

---

## Save location

Per user request, also save this file to:
`/Users/yoshimartodihardjo/NeuroMorphicToolKit/docs/current tasks/30 June.md`

(during execution — plan mode restricts writes to this file only)
