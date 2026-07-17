# Canvas Drawing Model — Implementation Plan

## Verified Implementation Status (2026-07-04)

**Status: DONE.** The plan was implemented (with some naming/scope evolution beyond the original spec) in the `neurocnl` module.

- **Component 1 (Canvas State Model):** `neurocnl/frontend/lib/providers/canvas/canvas_provider.dart` defines `CanvasTab` (`architecture, pipelineTrain, pipelineEval, pipelineOverview` — evolved from the plan's simpler `architecture, pipeline` split) and `CanvasState.pipeline: PipelineConfig` (line 49) plus `pipelinePhases: PipelinePhases` (line 55). `PipelineConfig` is implemented as its own model file at `neurocnl/frontend/lib/models/canvas/pipeline_config.dart`, matching the plan's `[NEW] pipeline_config.dart`.
- **Component 2 (Canvas Tab UI):** `neurocnl/frontend/lib/screens/canvas/canvas_screen.dart` exists and hosts the tab-based architecture/pipeline UI. A dedicated `pipeline_steps_panel.dart` file was not created as a literal fixed-4-card layout; instead the pipeline UI was built around `pipelinePhases`/`PipelinePhaseId` (train/eval) in the provider, a broader design than the plan's static step cards.
- **Component 3 (Edge Learning Rule Badge):** `LearningRuleBadge` and STDP/Surrogate Gradient/Hebbian options exist in `neurocnl/frontend/lib/widgets/canvas/property_panel.dart:488-496` and are referenced from `network_graph.dart` and `canvas_projection_utils.dart`, matching the plan.
- **Component 4 (Generate Button & Export Flow):** `neurocnl/frontend/lib/services/notebook_generate_service.dart` implements `NotebookGenerateService.generate()`, joining the CNL spec (`specTextProvider`/`canonicalDocProvider`) with `PipelineConfig` exactly as the plan's "Decision 3" split describes, and calls `api.generateNotebookV2(...)` (also wired from `run_step.dart:138` and `notebook_step.dart:73`). `export_screen.dart:171` has a "Generate Notebook" action.
- **Component 5 (Backend endpoint):** `neurocnl/backend/app/routers/notebook.py:1283-1345` defines `PipelineConfigPayload`, `GenerateV2Request`, and `GenerateV2Response`; the route is registered at `neurocnl/backend/app/routers/notebook.py:2034` (`@router.post("/notebook/generate-v2", ...)`). A dedicated test file exists: `neurocnl/backend/tests/test_notebook_generate_v2.py` (1065 lines).
- **Component 6 (Navigation):** No change was planned and none was needed; consistent with plan.

**Not verified:** actual test-suite pass/fail (`flutter test`, `pytest test_notebook_generate_v2.py`) and the manual end-to-end walkthrough steps — this audit is static-code-only, not a runtime check. The Phase 2 "Unified View" (dashed-arrow combined layout) was not found and appears genuinely deferred, consistent with the plan calling it out of scope.

---

**Date:** 12 June 2026  
**Status:** Approved — Ready for Implementation

---

## Goal

Enable users to *draw* a complete neuromorphic ML pipeline on the Canvas — both the network architecture and the training/evaluation/inference pipeline — and generate a runnable Jupyter notebook (with `.py` download) that compiles to multiple frameworks via NIR.

---

## Decisions Locked

| # | Decision | Resolution |
|---|---|---|
| 1 | Canvas scope | Tabbed (Architecture + Pipeline), unified view Phase 2 |
| 2 | Pipeline nodes | Fixed steps: Dataset → Train → Evaluate → Infer |
| 3 | CNL vs. JSON split | **Tab is the discriminator** — Architecture tab → CNL, Pipeline tab → JSON config |
| 4 | Learning rules on edges | Edge badge + Property Panel |
| 5 | Output format | Jupyter notebook primary, `.py` download secondary |

---

## Architecture Overview

```
┌─────────────────────────────────────────────────┐
│  Canvas Screen                                  │
│  ┌──────────┬──────────┐   (Phase 2: Unified)  │
│  │Arch. Tab │Pipeline  │                        │
│  │          │Tab       │                        │
│  │ NIR nodes│ Fixed    │                        │
│  │ + edges  │ steps    │                        │
│  └──────────┴──────────┘                        │
└─────────────────────────────────────────────────┘
         │ Architecture tab          │ Pipeline tab
         ▼                           ▼
     spec.cnl                training_config.json
         │                           │
         └──────────┬────────────────┘
                    ▼
           Backend: POST /api/notebook/generate-v2
                    │
                    ▼
           notebook.ipynb  (+ .py download)
           via NIR → snnTorch / Lava / Nengo
```

---

## Proposed Changes

---

### Component 1 — Canvas State Model (Frontend, Dart)

#### [MODIFY] canvas_provider.dart

Add `activeTab` and `pipelineConfig` to `CanvasState`.  
`pipelineConfig` is the authoritative source for the Pipeline tab; it serialises to `training_config.json`.

```dart
enum CanvasTab { architecture, pipeline }

class PipelineConfig {
  final String dataset;        // e.g. "NMNIST", "SHD"
  final String framework;      // e.g. "snntorch_sim", "lava_sim"
  final int epochs;
  final double learningRate;
  final String optimizer;      // e.g. "Adam", "SGD"
  final int batchSize;
  final bool runEvaluation;
  final bool exportNir;

  const PipelineConfig({
    this.dataset = 'NMNIST',
    this.framework = 'snntorch_sim',
    this.epochs = 50,
    this.learningRate = 1e-3,
    this.optimizer = 'Adam',
    this.batchSize = 32,
    this.runEvaluation = true,
    this.exportNir = false,
  });

  Map<String, dynamic> toJson() => { ... };
  factory PipelineConfig.fromJson(Map<String, dynamic> json) => ...;
}

class CanvasState {
  final CanvasGraph graph;           // Architecture tab → CNL
  final PipelineConfig pipeline;     // Pipeline tab → JSON config
  final CanvasTab activeTab;
  final String? selectedNodeId;
  final String? selectedEdgeId;
  ...
}
```

**Why:** The tab is the discriminator. `graph` serialises to CNL; `pipeline` serialises to JSON. No mixing, no ambiguity.

---

#### [NEW] pipeline_config.dart

Standalone model for `PipelineConfig` with JSON serialisation (`json_annotation`).  
Includes `toJson()` and `fromJson()` for persistence and backend payload.

---

### Component 2 — Canvas Tab UI (Frontend, Dart)

#### [MODIFY] canvas_screen.dart

Add a tab bar at the top of the canvas area:

```
[Architecture]  [Pipeline]
```

- **Architecture tab**: current `NetworkCanvas` + Component Library + Property Panel — unchanged.
- **Pipeline tab**: replaces the canvas area with a new `PipelineStepsPanel` widget (fixed steps, no drag-and-drop).

The toolbar buttons (Palette, Auto Layout, Inspector) are hidden when Pipeline tab is active.

---

#### [NEW] pipeline_steps_panel.dart

A vertical card-based layout showing the four fixed steps.  
Each step is a `PipelineStepCard` with an icon, title, description, and an "Edit" button that opens the step's property form inline.

```
┌─────────────────────────────────────────┐
│  1. Dataset                    [Edit ▾] │
│     NMNIST · 60 000 samples             │
├─────────────────────────────────────────┤
│  2. Train                      [Edit ▾] │
│     snnTorch · 50 epochs · Adam 1e-3   │
├─────────────────────────────────────────┤
│  3. Evaluate                   [Edit ▾] │
│     Accuracy · Loss curve               │
├─────────────────────────────────────────┤
│  4. Infer / Export             [Edit ▾] │
│     Export NIR · Download .py           │
└─────────────────────────────────────────┘
```

Each "Edit" expand reveals the property fields for that step.  
All field values write back to `PipelineConfig` via the `canvasProvider`.

---

### Component 3 — Edge Learning Rule Badge (Frontend, Dart)

#### [MODIFY] network_canvas.dart

When rendering a `CanvasEdge`, check `edge.parameters['learning_rule']`.  
If set, render a small `LearningRuleBadge` widget at the midpoint of the edge line.

```dart
// Badge colours:
// 'stdp'                → amber
// 'surrogate_gradient'  → blue
// 'hebbian'             → green
// (null)                → no badge
```

#### [MODIFY] property_panel.dart

Inside `_EdgePropertyPanel`: add a **Learning Rule** section with:
- Dropdown: `None` / `STDP` / `Surrogate Gradient` / `Hebbian`
- Conditional fields (shown when STDP selected): A+, A-, τ+, τ-
- These write to `edge.parameters` → lower into CNL as `stdp_learning` concept

---

### Component 4 — Generate Button & Export Flow (Frontend, Dart)

#### [MODIFY] canvas_screen.dart

Add a **"Generate Notebook"** primary action button visible in both tabs.  
On tap: calls `NotebookGenerateV2Service.generate(cnlSpec, pipelineConfig)`.

#### [NEW] notebook_generate_service.dart

Service that:
1. Reads `canvasProvider.state.graph` → serialises to CNL via existing `cnl_import_provider`
2. Reads `canvasProvider.state.pipeline` → `toJson()` → `PipelineConfig`
3. POSTs to `POST /api/notebook/generate-v2` with `{ spec: cnlSpec, pipeline_config: {...} }`
4. On success: opens the returned JupyterLab URL (same as existing flow)

#### [MODIFY] export_screen.dart

Add two new format options to the dropdown:
- `notebook_v2` → "Jupyter Notebook (Pipeline-aware)"
- `python_v2` → "Python Script (Pipeline-aware)"

These use the new `generate-v2` endpoint, not the existing `from-spec` endpoint.

---

### Component 5 — Backend: New Generate Endpoint (Python / FastAPI)

#### [MODIFY] notebook.py

Add new endpoint `POST /api/notebook/generate-v2`.

```python
class PipelineConfigPayload(BaseModel):
    dataset: str = "NMNIST"
    framework: str = "snntorch_sim"
    epochs: int = 50
    learning_rate: float = 1e-3
    optimizer: str = "Adam"
    batch_size: int = 32
    run_evaluation: bool = True
    export_nir: bool = False

class GenerateV2Request(BaseModel):
    spec: str                          # CNL text from Architecture tab
    pipeline_config: PipelineConfigPayload
    workspace_path: str = ""

class GenerateV2Response(BaseModel):
    workspace_folder: str
    notebook_filename: str
    python_filename: str
    jupyter_url: str = ""
```

**Notebook cell structure** (generated in order):

| Cell # | Type | Source | Data |
|---|---|---|---|
| 1 | Markdown | `# Architecture` | From CNL |
| 2 | Code | `config = { ... }` | From `PipelineConfigPayload` — **always editable** |
| 3 | Code | `net = build_from_nir(graph)` | Compiled via `compile_to_nir(spec)` |
| 4 | Markdown | `## Train` | — |
| 5 | Code | Training loop | Framework-specific, from `_TARGET_CELLS[framework]` |
| 6 | Markdown | `## Evaluate` | — |
| 7 | Code | Evaluation | Conditional on `run_evaluation` |
| 8 | Markdown | `## Infer / Export` | — |
| 9 | Code | NIR export / `.py` download | Conditional on `export_nir` |

**Key safety rule:** Cell 2 (`config = {}`) is always the first code cell, always visible, always editable. Architecture cells (3+) are commented as auto-generated. Wrong values in Cell 2 are immediately visible — no silent failure.

---

### Component 6 — Navigation Update (Frontend, Dart)

#### [NO CHANGE] neurosim_nav_section.dart

No new top-level nav sections needed. The `architecture` / `pipeline` split is handled as tabs within the existing `NeuroSimNavSection.canvas` section.

---

## Phase 2 — Unified View (deferred, not in scope now)

After Phase 1 ships:
- Add a **"Unified" toggle** button in the canvas toolbar
- Renders Architecture graph (left) + Pipeline steps (right) in a single scrollable horizontal layout
- A dashed `→ Generates` arrow connects the Architecture graph to the first Pipeline step card
- Read-only mode: all editing still happens in the respective tab

---

## Decision 3 — CNL/JSON Split Safety Summary

The split is enforced structurally, not by convention:

```
CanvasState.graph      → architecture tab UI → CNL parser
CanvasState.pipeline   → pipeline tab UI     → JSON → Cell 2
```

**How errors surface:**
- A value in the wrong CNL field → `LoweringError` from the parser (immediate, named, explicit)
- A wrong key in `PipelineConfig.toJson()` → Python `KeyError` in Cell 5 (immediate, traceable)
- No silent data corruption path exists

---

## Verification Plan

### Automated Tests

```bash
# Dart — new model serialisation
cd neurocnl/frontend && flutter test test/models/pipeline_config_test.dart

# Dart — canvas state tab switching
flutter test test/providers/canvas/canvas_provider_test.dart

# Python — new endpoint smoke test
cd neurocnl && python3 -m pytest tests/test_notebook_generate_v2.py -v

# Python — existing notebook tests still pass (no regression)
python3 -m pytest tests/test_notebook.py -v

# Launcher doctor
python3 scripts/launcher_control_service.py --doctor --json
```

### Manual Verification Steps

1. Open Canvas → confirm two tabs appear (Architecture, Pipeline)
2. Add a population node on Architecture tab → confirm CNL updates in Studio panel
3. Switch to Pipeline tab → change epochs to 100 → confirm `PipelineConfig` state updated
4. Add STDP to an edge → confirm amber badge appears on edge, A+/A- fields visible in Property Panel
5. Click "Generate Notebook" → confirm notebook opens in JupyterLab
6. In notebook Cell 2, verify `epochs: 100` matches what was set in the Pipeline tab
7. Change Cell 2 `epochs` to 200 → re-run Cell 5 → confirm training uses 200
8. Click "Download as .py" → confirm file is syntactically valid Python

---

## Files Touched Summary

| File | Status | Change |
|---|---|---|
| `lib/providers/canvas/canvas_provider.dart` | MODIFY | Add `activeTab`, `pipeline: PipelineConfig` to `CanvasState` |
| `lib/models/canvas/pipeline_config.dart` | **NEW** | `PipelineConfig` model + JSON serialisation |
| `lib/screens/canvas/canvas_screen.dart` | MODIFY | Add tab bar + Generate button |
| `lib/widgets/canvas/pipeline_steps_panel.dart` | **NEW** | Fixed-step pipeline card UI |
| `lib/widgets/canvas/network_canvas.dart` | MODIFY | Edge learning rule badges |
| `lib/widgets/canvas/property_panel.dart` | MODIFY | Learning rule dropdown + STDP params on edges |
| `lib/screens/canvas/export_screen.dart` | MODIFY | Add `notebook_v2` and `python_v2` formats |
| `lib/services/notebook_generate_service.dart` | **NEW** | `generate-v2` API service |
| `lib/routing/canvas/neurosim_nav_section.dart` | NO CHANGE | — |
| `backend/app/routers/notebook.py` | MODIFY | Add `POST /api/notebook/generate-v2` |
| `tests/test_notebook_generate_v2.py` | **NEW** | Pytest coverage for new endpoint |
| `test/models/pipeline_config_test.dart` | **NEW** | Dart model serialisation tests |
| `test/providers/canvas/canvas_provider_test.dart` | MODIFY | Add tab-switch coverage |
