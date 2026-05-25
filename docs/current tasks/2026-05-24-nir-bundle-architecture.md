# NIR + Training Bundle Architecture
## Viability Assessment & Integration Plan for NeuroMorphicToolKit

---

## 1. Executive Summary

The proposed architecture — separating network structure (`.nir`) from learning rules (`.train`) and ultimately consolidating both into a single project bundle — is **viable and aligns well with the existing NMTK codebase**. The internal IR layer (`NetworkIR`, `LearningRuleIR`) already expresses the necessary separation conceptually. The `TrainingAdapterRegistry` already provides the plug-in backend model. The main work is formalising the bundle format and hardening synchronisation between the structural and training halves.

The five problems raised in the critique are real, but all five have tractable solutions that map directly onto code that already exists or is partially scaffolded here.

---

## 2. What Already Exists in the Codebase

Before proposing changes, it is worth mapping the current state precisely, because the proposal is closer to done than it might appear.

### 2.1 `NetworkIR` + `LearningRuleIR` — the conceptual split already lives here

[`neurocnl/ir/types.py`](file:///Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl/neurocnl/ir/types.py) defines `NetworkIR` (line 203), which holds:

- `populations` — structural nodes
- `connections` — structural edges
- `learning_rules: list[LearningRuleIR]` — learning annotations, **already a first-class field**

`LearningRuleIR` (line 148) stores `kind`, `source`, `target`, `rate`, `window`, `weight_min`, `weight_max`, and an open `attributes` dict. The conceptual two-file split is **already encoded in a single dataclass**. The bundle approach is simply the persistence layer that gives this existing distinction a file-system representation.

### 2.2 `compile_to_nir` — clean NIR output pipeline

[`neurocnl/compile.py`](file:///Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl/neurocnl/compile.py) is the primary public surface:

```
CNL spec text
    → NIR_CNL_Parser   (parse)
    → NIR_Compiler     (structural validate + materialise)
    → nir.NIRGraph     (output)
    → nir.write()      (optional save_to=)
```

This pipeline intentionally **does not carry learning rules** into the NIR graph — STDP is acknowledged in `nir_exporter.py` as `"lowered_as_metadata"`. That is already the right behaviour: the `.nir` side stays NIR-spec-compliant, and learning rules live separately.

### 2.3 `TrainingAdapterRegistry` — plug-in backend model

[`neurocnl/training_registry.py`](file:///Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl/neurocnl/training_registry.py) provides `BaseTrainingAdapter`, `TrainingRequest`, and `TrainingResult`. The factory in [`neurocnl/training/factory.py`](file:///Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl/neurocnl/training/factory.py) wires up `SnnTorchAdapter` and `SleepPesAdapter`. This is exactly the "per-framework translation layer" the critique calls out as hard work — and it is already scaffolded.

### 2.4 `nir_exporter.py` — concept fidelity audit

[`neurocnl/export/nir_exporter.py`](file:///Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl/neurocnl/export/nir_exporter.py) already classifies concepts:

| Concept | Verdict |
|---|---|
| `stdp_learning` | `lowered_as_metadata` |
| `homeostatic_plasticity` | `lowered_approximately` |
| `neuromodulation` | `lowered_as_metadata` |
| `short_term_plasticity` | `lowered_approximately` |
| `threshold_firing` | `lowered_faithfully` |
| `synaptic_weight` | `lowered_faithfully` |

This is the ground truth for which concepts belong in `.nir` vs. which must live in the training side of the bundle.

---

## 3. What the Current Canvas Actually Supports

The Flutter Studio canvas (the visual editor in `neurocnl/frontend`) was audited to determine how much of the proposed learning rule and backprop architecture it already handles vs. what is missing.

### 3.1 Canvas data model — no learning rules today

[`canonical_editor_document.dart`](file:///Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl/frontend/lib/models/canonical_editor_document.dart) defines the canvas-facing types:

- `CanvasNode` — stores `id`, `label`, `nirType`, `type`, `size`, `threshold`, `tau`. **No learning rule field.**
- `CanvasEdge` — stores `source`, `target`, `polarity`, `weight`, `connectivityPattern`. **No learning rule field.**
- `CanvasProjection` — a list of nodes and edges. **No plasticity layer.**

The canvas therefore has **zero awareness of STDP, Hebbian, surrogate-gradient, or any training annotation on an edge or node**. Learning rules that exist in the backend `NetworkIR.learning_rules` list are silently discarded when the canonical doc is projected to the canvas.

### 3.2 `CanvasEdge.parameters` — the escape hatch that exists but is unused

The lower-level canvas model in [`canvas.dart`](file:///Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl/frontend/lib/models/canvas/canvas.dart) has a `parameters: Map<String, dynamic>` on both `CanvasNode` and `CanvasEdge`. In the demo reflex arc ([`canvas_provider.dart`](file:///Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl/frontend/lib/providers/canvas/canvas_provider.dart) line 157) this carries `synapse_type`, `weight`, and `delay` — but not a learning rule kind. The escape hatch is structurally present but no code populates it with learning rule data or reads it back as one.

### 3.3 Training panel — capability-aware UI exists, but is disconnected from the canvas graph

A full training panel exists in [`training_inspector_panel.dart`](file:///Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl/frontend/lib/widgets/training_inspector_panel.dart) and [`training_provider.dart`](file:///Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl/frontend/lib/providers/training_provider.dart). It:

- Fetches available backends from `GET /api/training/capabilities` (snnTorch surrogate, Sleep-PES)
- Shows a mode selector and epoch count slider
- Submits a job via `POST /api/training/run` with `{backend_name, training_mode, n_epochs, spec}`
- Polls for completion and shows loss/duration

What it **does not do**:

- It does not read the canvas graph to determine which edges have learning rules attached
- It does not send per-edge or per-connection rule parameters to the backend
- It hardcodes the dataset to `'n-mnist'` regardless of what the user has drawn on the canvas
- It has no concept of `deployment_mode` or online vs. offline learning
- There is no visual distinction on the canvas between a trained (plastic) edge and a static one

The training panel is effectively a **standalone training launcher** bolted onto the side of the editor. It submits the current CNL spec text but the backend ignores the graph's learning rules because the backend `SnnTorchAdapter` builds its own hardcoded `TinySnn` topology.

### 3.4 Sleep-PES / homeostasis panel — separate provider, also disconnected

[`learning_provider.dart`](file:///Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl/frontend/lib/providers/learning_provider.dart) and [`learning_config_panel.dart`](file:///Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl/frontend/lib/widgets/learning_config_panel.dart) handle the Sleep-PES path. This is the Nengo-based offline-learning path (homeostasisFactor, epochs). It is also disconnected from the canvas — it does not read per-node or per-edge learning parameters from the visual graph.

### 3.5 Backprop support summary

| Feature | Canvas UI | Backend | Wire between them? |
|---|---|---|---|
| Draw nodes and edges | ✅ | ✅ | ✅ via CNL spec |
| Static edge weights | ✅ (parameter panel) | ✅ | ✅ |
| Edge connectivity pattern | ✅ | ✅ | ✅ |
| Surrogate-gradient backprop (snnTorch) | ⚠️ trigger-only | ✅ adapter exists | ❌ hardcoded topology |
| Sleep-PES offline learning | ⚠️ trigger-only | ✅ adapter exists | ❌ hardcoded |
| STDP rule on a specific edge | ❌ not renderable | ✅ `LearningRuleIR` | ❌ not surfaced |
| Three-factor / reward-modulated STDP | ❌ | ❌ | ❌ |
| `deployment_mode` flag | ❌ | ❌ | ❌ |
| Learning rule visualised on canvas edge | ❌ | — | — |
| Plastic vs. static edge visual distinction | ❌ | — | — |

### 3.6 What must change in the canvas to support the proposed architecture

1. **`CanvasEdge` needs a `learningRule` field.** The `CanonicalEditorDocument.CanvasEdge` must carry an optional `LearningRuleProjection` (kind, rate, window, rewardSignal). This is the mirror of `LearningRuleIR` scoped to one edge.

2. **The canvas must visually distinguish plastic edges.** At minimum, a dashed or coloured edge style for STDP connections. The `network_graph_view.dart` edge painter needs to read this field.

3. **The training panel must read per-edge learning rules from the canvas graph** and send them in the job payload — not hardcode the topology in the adapter.

4. **The backend adapters must accept a topology description from the payload**, not build their own. The `SnnTorchAdapter._run_real()` currently constructs `TinySnn` internally. It needs to accept the NIR graph and learning rule spec from the request payload.

5. **A "reward node" palette item** is needed for three-factor rules (can be deferred to Phase 3).

---

## 4. The Five Problems — Honest Assessment

### Problem 1: The `.train` file format is undefined and you own it

**Verdict: Real problem, but less scary than described.**

You do not need to invent an abstract schema that covers STDP + Hebbian + backprop simultaneously. You need a schema that covers what `LearningRuleIR` already expresses, plus a `backend` discriminator that routes to the correct adapter.

The minimum viable training schema is:

```json
{
  "schema_version": "1.0",
  "target_backend": "snntorch",
  "training_mode": "surrogate",
  "hyperparameters": {
    "n_epochs": 10,
    "learning_rate": 0.005,
    "surrogate_slope": 25.0
  },
  "learning_rules": [
    {
      "kind": "stdp",
      "source": "sensory population",
      "target": "motor population",
      "rate": 0.01,
      "window": 0.02,
      "weight_min": 0.0,
      "weight_max": 1.0
    }
  ]
}
```

This is a direct serialisation of `TrainingRequest.payload` + the `learning_rules` field already on `NetworkIR`. The per-framework translation code that must exist is the adapter — and you already have the adapter pattern. Adding a BindsNET or Nengo adapter means writing one class that implements `BaseTrainingAdapter.run()`. That is the right unit of work, not a free-floating schema problem.

**What you must decide and document:** whether `learning_rules` in the bundle's training JSON are *constraints* (must be honoured by the backend) or *hints* (the backend may ignore if it does not support that rule type). This distinction should be explicit in the schema as a `"rule_mode": "strict" | "advisory"` field.

---

### Problem 2: File synchronisation is a real engineering problem

**Verdict: Legitimate, and the right fix is already implied by the codebase architecture.**

The codebase generates NIR *from* `NetworkIR`. It does not maintain a `.nir` file as a living source of truth alongside the IR. The correct model is:

```
ProjectBundle (source of truth)
    ├── internal_ir: NetworkIR   ← edit this
    └── on export:
            → graph.nir          (generated from NetworkIR.populations + .connections)
            → training.json      (generated from NetworkIR.learning_rules + target_backend)
```

The UI never edits `graph.nir` or `training.json` directly. Both are **outputs** of serialising `NetworkIR`. This completely avoids orphan rules and atomic rename problems. The bundle is a ZIP/HDF5 container; the internal representation is `NetworkIR` in memory.

Concretely: when a user deletes the edge `sensory → motor` in the visual editor, the code calls `NetworkIR.connections.remove(...)` and then also removes any `LearningRuleIR` whose `source` + `target` match that connection. This is a single function, not a two-file sync. On next export, both generated files reflect the updated state.

---

### NIR framework compatibility — the critical constraint on online learning

Before addressing the boundary problem, a hard constraint must be stated that the original proposal glosses over:

**BindsNET and SpikingJelly, despite being the richest frameworks for STDP, have no NIR support.** They cannot be export targets in an NIR-centric architecture. The verified NIR framework list (as of 2025) is:

| Framework | NIR support | Online learning (STDP etc.) | Practical status for NMTK |
|---|---|---|---|
| **Lava / Lava-DL** | ✅ Official | ✅ `STDPLoihi`, R-STDP, 3-factor | **Only viable NIR + online learning path** |
| **Nengo** | ✅ Official | ✅ PES (online), Hebbian | Removed from NMTK stack (ADR) |
| **Norse** | ✅ Official | ⚠️ Experimental trace-based only | Primarily backprop/surrogate |
| **snnTorch** | ✅ Official | ❌ Not built in | Surrogate-gradient only |
| **Rockpool** | ✅ Official | ❌ | Deployment-focused |
| **Sinabs** | ✅ Official | ❌ | Hardware deployment (Speck/Xylo) |
| **Spyx** | ✅ Official | ❌ | JAX, no online rules |
| **BindsNET** | ❌ No NIR support | ✅ Core feature | Cannot be an export target |
| **SpikingJelly** | ❌ No NIR support | ✅ Has STDP module | Cannot be an export target |

**Consequence:** `deployment_mode = "online_learn"` in the bundle is **Lava-only today**. Any other NIR-compatible backend must be `"offline_train"` or `"deploy_only"`. The proposed BindsNET adapter (Phase 4 in this plan) would work as a *simulation-only* training backend but could never produce a portable NIR export — that must be called out clearly in the UI.

---

### Problem 3: STDP blurs the train/deploy boundary

**Verdict: Accurate, and the `deployment_mode` flag is Lava-only for now.**

The tier model in the proposal (train → both files; deploy → `.nir` only) is wrong for online learning networks. The bundle must support three modes explicitly:

| Mode | What goes to hardware | Weights frozen? | Available backends |
|---|---|---|---|
| `offline_train` | `.nir` file (post-training) | Yes | snnTorch, Norse, Rockpool, Sinabs |
| `online_learn` | `.nir` + learning rule metadata | No — plasticity runs on-chip | **Lava → Loihi 2 only** |
| `deploy_only` | `.nir` file | Yes | All NIR-compatible backends |

The `training.json` side of the bundle should carry `"deployment_mode": "offline_train" | "online_learn" | "deploy_only"`. When `online_learn` is selected with any backend other than Lava, the system must surface a clear error — not silently export a static `.nir` file and lose the learning rules.

This is new code, but it is a field on a schema and a `case` in the exporter — not an architectural revision.

---

### Problem 4: The framework table has inaccuracies

**Verdict: Correct, and more serious than the original proposal acknowledged — two of the best STDP frameworks have no NIR path at all.**

The table items that affect the NMTK codebase specifically:

- **Lava / Loihi 2**: The only NIR-compatible framework with real, production-grade online learning. The existing [`lava_exporter.py`](file:///Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl/neurocnl/export/lava_exporter.py) targets the deployment path only. Adding `deployment_mode = "online_learn"` support means the exporter must also emit `STDPLoihi` learning rule configuration alongside the network graph — this is the key gap.

- **NengoDL**: Nengo PES is a real online learning rule and Nengo is NIR-compatible. However, the NMTK codebase already removed Nengo as a first-class intermediary (Open Brain ADR: *"Removed Nengo as the intermediary layer between CNL and NIR"*). Re-adding it just for PES would be a regression against that decision.

- **BindsNET**: Has the richest STDP support of any Python SNN framework, but **has no NIR bridge**. It can be wired up as a simulation-only training backend (write a `BindsNETAdapter` that trains and returns weights) but its output cannot be expressed as a portable `.nir` file. Any UI that offers BindsNET as a backend must make this limitation visible.

- **SpikingJelly**: Same position as BindsNET — excellent STDP support, no NIR bridge. Cannot be an export target.

---

### Problem 5: Three-factor rules (reward-modulated STDP) need a new node type

**Verdict: Real gap in `LearningRuleIR`, solvable with a targeted extension.**

The current `LearningRuleIR` has no field for a global reward/teaching signal. The schema needs:

```python
@dataclass(slots=True)
class LearningRuleIR:
    kind: str
    source: str | None = None
    target: str | None = None
    rate: float | None = None
    window: float | None = None
    weight_min: float | None = None
    weight_max: float | None = None
    # NEW — for three-factor / RL rules:
    reward_signal: str | None = None   # population name that carries the teaching signal
    attributes: dict[str, Any] = field(default_factory=dict)
    provenance: list[SourceProvenance] = field(default_factory=list)
```

In the visual editor, a "reward node" is a population with `role="reward_signal"`. The CNL sentence would be something like:

```
The reward population MUST modulate the connection from sensory to motor with STDP
```

The lowering step maps this to `LearningRuleIR(kind="r-stdp", reward_signal="reward population", ...)`. The NIR exporter continues to treat it as `lowered_as_metadata`. Of the NIR-compatible backends, only **Lava → Loihi 2** supports three-factor rules via its `Rmax`/reward-modulated learning engine. BindsNET also has a `Reward` learning rule but, having no NIR bridge, can only be used as a simulation backend — not as an export target.

---

## 5. The Concrete Bundle Format

Based on the above, the recommended project bundle format for NMTK is:

```
my_network.nmtk          ← ZIP container
├── manifest.json        ← bundle version, schema_version, creation date
├── graph.nir            ← NIR-spec-compliant graph (generated output)
├── training.json        ← learning rules + backend config (generated output)
├── internal_ir.json     ← serialised NetworkIR (source of truth for editing)
└── weights.h5           ← optional: cached trained weights
```

### `manifest.json`
```json
{
  "bundle_schema_version": "1.0",
  "nmtk_version": "...",
  "created_at": "2026-05-24T22:00:00Z",
  "target_backend": "snntorch",
  "deployment_mode": "offline_train"
}
```

### `training.json`
```json
{
  "schema_version": "1.0",
  "target_backend": "snntorch",
  "training_mode": "surrogate",
  "deployment_mode": "offline_train",
  "hyperparameters": {
    "n_epochs": 10,
    "learning_rate": 0.005
  },
  "learning_rules": [
    {
      "kind": "stdp",
      "source": "sensory population",
      "target": "motor population",
      "rate": 0.01,
      "window": 0.02,
      "reward_signal": null
    }
  ]
}
```

### Why `.nmtk` ZIP and not HDF5

HDF5 is excellent for purely numerical payloads. For NMTK, the bundle contains heterogeneous types (JSON metadata, NIR's HDF5-native `.nir` file, and optionally numpy weight arrays). A ZIP container is simpler to inspect, version-control friendly (individual files can be diffed), and already familiar to Python's standard library. The `.nir` inside the bundle is itself an HDF5 file, so no numerical precision is lost.

---

## 6. How This Maps to Existing Code

| Proposed component | Maps to existing code | Status |
|---|---|---|
| Bundle source of truth | `NetworkIR` dataclass in `ir/types.py` | ✅ Exists |
| Structural export | `compile_to_nir()` / `nir_exporter.py` | ✅ Exists |
| Learning rule schema | `LearningRuleIR` in `ir/types.py` | ✅ Exists, needs `reward_signal` field |
| Backend plug-in model | `BaseTrainingAdapter` + `TrainingAdapterRegistry` | ✅ Exists |
| snnTorch adapter | `SnnTorchAdapter` in `training/snntorch_adapter.py` | ✅ Exists |
| Sleep-PES adapter | `SleepPesAdapter` in `training/sleep_pes_adapter.py` | ✅ Exists |
| BindsNET adapter | — | ❌ Not yet, needs writing |
| Loihi online-learn branch | `lava_exporter.py` needs `deployment_mode` branch | ⚠️ Partial |
| Bundle serialiser (`internal_ir.json`) | `NetworkIR` has no JSON serialiser yet | ❌ Needs adding |
| Bundle container (ZIP read/write) | — | ❌ Needs adding |
| `manifest.json` writer | — | ❌ Needs adding |
| `deployment_mode` flag | Not in `LearningRuleIR` or `TrainingRequest` | ❌ Needs adding |
| Three-factor `reward_signal` field | Not in `LearningRuleIR` | ❌ Needs adding |

---

## 7. Phased Implementation Plan

### Phase 0 — Fix the adapter–canvas disconnect

| Gap | Solution |
|---|---|
| Adapter ignores user topology | Update adapter to accept `nir_graph` from payload |
| Training panel lacks topology context | `compile_to_nir()` triggered before training |

1. Modify `SnnTorchAdapter._run_real()` to accept a NIR graph from the payload (`payload['nir_graph']`) and build the snnTorch model from it, falling back to the demo topology only if no graph is provided.
2. Modify `_startTraining()` in `training_inspector_panel.dart` to call `compile_to_nir()` first and include the resulting graph structure in the payload.
3. This makes training actually reflect what the user has drawn — without any bundle format changes.

### Phase 1 — Formalise the internal IR as the source of truth (no new features)

1. Add a `NetworkIR.to_dict()` / `NetworkIR.from_dict()` serialiser (JSON-safe, no numpy — weights get a separate HDF5 sidecar).
2. Add `ProjectBundle` dataclass: wraps `NetworkIR`, `manifest`, `training_config`.
3. Add `ProjectBundle.save(path)` and `ProjectBundle.load(path)` using Python `zipfile`.
4. Generate `graph.nir` and `training.json` from `ProjectBundle.export()` — both are derived outputs, not inputs.

This phase is entirely in `neurocnl`. No UI changes needed yet.

### Phase 2 — Add learning rules to the canvas model

1. Add `LearningRuleProjection` class to `canonical_editor_document.dart` (mirrors `LearningRuleIR`: kind, rate, window, rewardSignal).
2. Add `learningRule: LearningRuleProjection?` to `CanvasEdge` in `canonical_editor_document.dart`.
3. Update the backend `CanonicalEditorDocument` Pydantic contract to include `learning_rule` on edge projections.
4. Update `network_graph_view.dart` edge painter to render plastic edges differently (dashed stroke, coloured label).
5. Update the edge parameter inspector panel so users can pick a learning rule kind from a dropdown ("static", "stdp", "surrogate").

### Phase 3 — Extend `LearningRuleIR` and `training.json`

1. Add `reward_signal: str | None` to `LearningRuleIR`.
2. Add `deployment_mode: Literal["offline_train", "online_learn", "deploy_only"]` to `TrainingRequest` and the `training.json` schema.
3. Update `SnnTorchAdapter` to read `deployment_mode` and error clearly if `"online_learn"` is requested (snnTorch does not support it natively).
4. Update `lava_exporter.py` to emit on-chip plasticity config when `deployment_mode == "online_learn"`.

### Phase 4 — BindsNET adapter (simulation-only)

> [!IMPORTANT]
> BindsNET has no NIR bridge. The weights it produces cannot be exported as a portable `.nir` file. This adapter is useful for simulating STDP behaviour locally, but the output is `weights.h5` only — not a deployable bundle.

1. Write `BindsNETAdapter(BaseTrainingAdapter)` with `output_format="weights_only"` (not `"nir"`).
2. Supported training modes: `"stdp"`, `"reward_modulated_stdp"`.
3. Consume `learning_rules` from the bundle's `training.json` and map them to BindsNET `Connection` constructor arguments.
4. Return learned weights in `TrainingResult.learned_weights`; bundle serialiser writes them to `weights.h5`.
5. Surface a clear UI warning: *"BindsNET training produces weights for use in simulation only. Export to neuromorphic hardware requires the Lava backend."*

### Phase 4b — Lava online_learn adapter

This is the only path that produces a truly deployable online-learning bundle.

1. Write `LavaOnlineAdapter(BaseTrainingAdapter)` with `deployment_mode="online_learn"` and `output_format="nir+stdp_config"`.
2. Translate `LearningRuleIR` entries into Lava `STDPLoihi` / `Rmax` process constructor arguments.
3. Generate `stdp_config.json` alongside `graph.nir` in the bundle — this carries the on-chip learning rule parameters that Loihi 2's compiler needs.
4. Update `lava_exporter.py` to read `deployment_mode` and, when `"online_learn"`, include `stdp_config.json` in the export payload.
5. When `online_learn` is requested with any non-Lava backend, raise `AdapterSelectionError` with `UnavailableReasonCode.NOT_IMPLEMENTED` and a message: *"Online learning requires the Lava backend targeting Loihi 2."*

### Phase 5 — UI integration (nmtk_ui_core / Flutter Studio)

1. The visual editor works against `ProjectBundle` (via the backend API), never against raw `.nir` or `.train` files.
2. Deleting an edge calls a `remove_connection(source, target)` API endpoint that removes both the `ConnectionIR` and any matching `LearningRuleIR` in one transaction.
3. The "Export" action calls `ProjectBundle.export()` and returns the ZIP to the user.
4. A "reward node" in the visual palette maps to `PopulationIR(role="reward_signal")`.

---

## 7. What the Critique Gets Right That This Document Must Not Gloss Over

1. **The `.train` format is still your format.** Even with the adapter pattern, you own the schema and must version it. Use `schema_version` in `training.json` and write a migration path before the first breaking change.

2. **File synchronisation is solved by making both files outputs, not inputs.** If any code path ever reads `.nir` or `training.json` back as sources of truth for editing, the orphan-rule bug reappears. The bundle loader must only read `internal_ir.json`; the generated files are write-only from the editor's perspective.

3. **Online learning through NIR means Lava → Loihi 2, specifically.** BindsNET and SpikingJelly are not NIR-compatible and cannot be export targets. The `deployment_mode` flag is not optional, and when set to `"online_learn"` with any non-Lava backend the system must error explicitly rather than silently drop the learning rules.

4. **Three-factor rules need a visual metaphor.** The "reward node" palette item must exist in the UI before anyone can express R-STDP in the editor. This is a UX design task, not just a schema task.

---

## 8. Conclusion

The two-file conceptual split is sound. The single-bundle implementation of it is correct. However, the canvas audit and NIR compatibility check together reveal two important additional gaps.

The real completion picture is therefore:

- **Structural half** (`NetworkIR` → `compile_to_nir` → `.nir`): ✅ complete and working.
- **Training backend half** (`LearningRuleIR` + `TrainingAdapterRegistry` + `SnnTorchAdapter`): ✅ scaffolded, but adapters ignore the user's topology.
- **Canvas ↔ training connection**: ❌ entirely missing. The canvas has no learning rule fields, no visual distinction for plastic edges, and the training panel does not read the graph.
- **Bundle format**: ❌ the `ProjectBundle` container, `internal_ir.json` serialiser, `deployment_mode` flag, and `reward_signal` field all need adding.
- **Online learning via NIR**: ⚠️ Lava → Loihi 2 is the only viable path. BindsNET and SpikingJelly, while richer for STDP simulation, cannot produce portable NIR exports. Any UI that offers them must surface this constraint explicitly.

The priority order should therefore be:
1. Fix the adapter–canvas disconnect (Phase 0) — makes the existing training UI actually useful.
2. Add `LearningRuleProjection` to the canvas model and edge painter (Phase 2) — gives learning rules a visual home.
3. Build the formal bundle format (Phase 1) around those foundations.
4. Add the Lava online_learn adapter (Phase 4b) as the sole NIR-portable online learning path.

All gaps are additive extensions to an already coherent system. None require architectural revision.

