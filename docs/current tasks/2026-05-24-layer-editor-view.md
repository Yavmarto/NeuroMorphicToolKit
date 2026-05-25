# Layer Editor View — Sequential / Structured Network Authoring

**Created**: 2026-05-24  
**Status**: Spec — no tasks started  
**Priority**: T2 (after T1-8 NIR editor round-trip stabilises)  
**Related**: `docs/current tasks/2026-05-24-nir-bundle-architecture.md`, T1-8, T1-10

---

## Idea Assessment

The proposal is to add a **structured, row/column layer view** to the Studio canvas that lets users
build a network by stacking layers — like `nn.Sequential` in PyTorch — instead of drawing
free-form nodes and edges. Each layer card maps directly to one or two CNL sentences.

**Verdict: Strong idea, substantial scope. Should be its own task, not folded into the bundle architecture.**

### Why it makes sense

1. **Every mainstream SNN framework thinks in layers.** PyTorch `nn.Sequential`, snnTorch
   `Leaky`/`Synaptic` stacks, Norse `LIFCell` chains, Lava Process chains — all are conceptually
   an ordered list of (synapse, neuron) pairs. A layer-list editor speaks the same language.

2. **Each layer is exactly one or two CNL sentences.** A `Linear(in, out) + LIF(n)` layer lowers
   to: `Connect A to B with dense weights w` and `Define a LIF population B with N neurons`.
   The mapping is mechanical and invertible.

3. **Grouping + expand reveals sub-steps.** A collapsed layer card shows type and size.
   Expanding it reveals parameters, learning rule (if plastic), connectivity pattern, and the
   equivalent CNL text — teaching the user the language as they build.

4. **Orientation makes topology visible at a glance.** Rows = feedforward depth.
   Columns = parallel pathways (multi-area, ensemble, dual-stream). Most common SNN topologies
   (feedforward, branching, merge) fit naturally.

### Why it is a *complement*, not a *replacement* for the graph canvas

The graph canvas is still needed for:
- **Recurrent connections** (lateral feedback loops don't fit a layer list)
- **Lateral inhibition** (cross-layer connections with no clean sequential ordering)
- **Arbitrary skip connections** (ResNet-style)
- **Multi-area networks with complex wiring**

The layer editor should be a **second view mode** in Studio — a toggle alongside the existing
canvas, not a replacement. Networks authored in the layer view can always be viewed in the graph
canvas; the reverse is only true for networks with a sequential topology.

---

## Framework Layer Equivalence

The math is the same across frameworks. The table below shows how one "layer" maps to each
framework's code, and to the CNL it produces.

### Layer type: `Linear + LIF`

| Framework | Code | CNL equivalent |
|---|---|---|
| **PyTorch / snnTorch** | `nn.Linear(256, 128)` + `snn.Leaky(beta=0.9)` | `Connect hidden to output with 256×128 dense weights 0.3` |
| **Norse** | `F.linear(x, w)` + `LIFCell(LIFParameters(tau_mem=20e-3))` | `Define a LIF population output with 128 neurons, tau_rc 20ms` |
| **Lava** | `Dense(in_channels=256, out_channels=128)` + `LIF(shape=(128,), du=0, dv=0, vth=10)` | same pair of sentences |
| **BindsNET** | `Connection(source, target, rule=PostPre)` | same + `with STDP learning rule` |

All four frameworks share the same two-step structure: **synapse (weight matrix) → neuron
(dynamics)**. The layer card wraps these two CNL sentences into one expandable card.

### Layer type: `Input encoding`

| Framework | Code | CNL equivalent |
|---|---|---|
| snnTorch | `spikegen.rate(data, num_steps=T)` | `Define an input population encoding with 784 neurons` |
| Norse | `PoissonEncoder(seq_length=T)(data)` | same |
| Lava | `SpikeIn(shape=(784,))` | same |

### Layer type: `Convolution + LIF`

| Framework | Code | CNL equivalent |
|---|---|---|
| snnTorch | `nn.Conv2d(1, 32, 3)` + `snn.Leaky()` | `Connect input to conv1 with 32 3×3 convolutional filters` |
| Norse | `Conv2dCell(1, 32, 3, ...)` | same |
| Lava | `Conv(in_channels=1, out_channels=32, kernel_size=3, ...)` | same |

NIR has a `nir.Conv2d` primitive, so this lowers faithfully.

### Layer type: `Linear + LIF + STDP` (plastic layer)

This is the online-learning case. The layer card shows the STDP parameters as a sub-section
(expandable). Only available when backend is Lava (online) or BindsNET (simulation-only).

```
▼ Layer 2: LIF [128] — plastic (STDP)
    Synapse:  Dense 256 × 128, w_init = Normal(0, 0.3)
    Neuron:   LIF, threshold 1.0, τ_rc 20ms, τ_ref 2ms
    Learning: STDP  A+ 0.01  A- 0.01  τ+ 20ms  τ- 20ms  [Lava only]
    CNL:      "Connect hidden to output with 256×128 dense weights 0.3
               with STDP learning rule, rate 0.01, window 20ms"
```

---

## Layer Card Anatomy

Each card has two states:

```
Collapsed:
┌─────────────────────────────────────────────────────┐
│ ▶  Layer 2 · LIF  ·  256 → 128  ·  dense  [plastic] │
└─────────────────────────────────────────────────────┘

Expanded:
┌─────────────────────────────────────────────────────┐
│ ▼  Layer 2 · LIF  ·  256 → 128  ·  dense  [plastic] │
├─────────────────────────────────────────────────────┤
│  Synapse                                             │
│    Type:        Dense (fully connected)              │
│    In → Out:    256 → 128                            │
│    Weight init: Normal(μ=0, σ=0.3)                  │
│                                                      │
│  Neuron                                              │
│    Type:        LIF                                  │
│    Threshold:   1.0                                  │
│    τ_rc:        20 ms                                │
│    τ_ref:       2 ms                                 │
│                                                      │
│  Learning rule  [plastic edge]                       │
│    Rule:        STDP (Lava only)                     │
│    A+:  0.01    τ+:  20 ms                           │
│    A-:  0.01    τ-:  20 ms                           │
│                                                      │
│  CNL preview                                         │
│    Connect hidden to output with 256×128 dense       │
│    weights 0.3 with STDP learning rule, rate 0.01,   │
│    window 20ms                                       │
│    Define a LIF population output with 128 neurons,  │
│    threshold 1.0, tau_rc 20ms, tau_ref 2ms           │
└─────────────────────────────────────────────────────┘
```

The CNL preview section is **read-only text** reflecting the current parameter state — it updates
live as the user changes sliders/fields. This is the primary teaching mechanism: users learn
CNL by building visually.

---

## Orientation Model

### Rows (feedforward depth)

```
[Input  784] ──▶ [Dense + LIF  128] ──▶ [Dense + LIF  64] ──▶ [Output  10]
```

Used for: standard feedforward SNN, most snnTorch / Norse examples.

### Columns (parallel pathways)

```
[Input  784]
   ├──▶ [Dense + LIF  128] ──▶ [Merge]
   └──▶ [Conv + LIF  32 ]  ──▶ [Merge] ──▶ [Output  10]
```

Used for: dual-stream, multi-area, ensemble models.

### Mixed (grouped)

Groups = named modules (like PyTorch `nn.Module` subclasses). A group can be collapsed to
a single card and expanded to show its internal layers. This is equivalent to `nn.Sequential`
blocks nested inside a parent `nn.Module`.

```
▼ Encoder block
    [Input 784] → [Conv + LIF 32] → [Conv + LIF 64]
▼ Classifier
    [Dense + LIF 128] → [Output 10]
```

---

## CNL Sentence Mapping

The layer editor is a **structured front-end** for CNL. It does not introduce a new language — it
generates valid CNL sentences from UI state.

| Layer card field | CNL sentence fragment |
|---|---|
| Layer type = LIF, size N | `Define a LIF population <name> with N neurons` |
| Threshold | `, threshold <v>` |
| τ_rc | `, tau_rc <v>ms` |
| τ_ref | `, tau_ref <v>ms` |
| Synapse type = Dense, src→dst, weight | `Connect <src> to <dst> with <src_n>×<dst_n> dense weights <w>` |
| Synapse type = Conv, filters, kernel | `Connect <src> to <dst> with <k> <sz>×<sz> convolutional filters` |
| Learning rule = STDP | ` with STDP learning rule, rate <r>, window <w>ms` |
| Learning rule = Surrogate | *(offline — no CNL extension needed; backend-only)* |

The mapping is one-to-one and lossless for all currently supported NIR primitives.

---

## Relationship to Existing Components

### What changes

| Component | Change |
|---|---|
| `neurocnl/frontend/lib/screens/studio_screen.dart` | Add view-mode toggle: Graph ↔ Layers |
| `neurocnl/frontend/lib/widgets/canvas/` | New `layer_editor.dart` widget subtree |
| `neurocnl/frontend/lib/models/canvas/canvas.dart` | `CanvasGraph` becomes the shared state between both views |
| `neurocnl/frontend/lib/providers/canvas/canvas_provider.dart` | `addLayer()` / `removeLayer()` / `reorderLayer()` mutations |
| `neurocnl/frontend/lib/models/canonical_editor_document.dart` | `CanvasProjection` extended with `orientation` and `groups` |
| `nmtk_ui_core` | `LayerCard`, `LayerGroup`, `LayerEditorShell` widgets |

### What does not change

- The `CanvasGraph` / `CanvasNode` / `CanvasEdge` model is the shared source of truth
- The `_pushToCanonical()` → backend round-trip is identical
- CNL parsing, IR lowering, NIR export — untouched
- The graph canvas remains available as an alternate view

---

## Scope Decision

This is **not in the active queue** until T1-8 (NIR editor round-trip) is complete, because:

1. T1-8 fixes the bug where NIR-native CNL does not populate the canvas correctly. The layer
   editor depends on the canvas model being correct.
2. T1-10 (sentence picker NIR alignment) must be done first, or the layer editor's CNL
   preview will emit invalid sentences.

Once those two are green, this task unlocks as a T2 item.

---

## Implementation Phases

### Phase 1 — Layer model extension (backend-only, no new UI)

1. Extend `CanvasProjection` with `orientation: "rows" | "columns"` and
   `groups: List[LayerGroup]`.
2. Add `LayerGroup` to `canonical_editor_document.dart` with `id`, `name`, `layerIds`.
3. Add `addLayer()`, `removeLayer()`, `reorderLayer()` to `CanvasNotifier`.
4. Add `groupLayers()`, `ungroupLayers()` mutations.
5. Confirm the existing `_pushToCanonical()` path handles the new fields transparently.

**Exit criteria**: The graph canvas is unchanged; the new fields round-trip through the backend.

---

### Phase 2 — Layer card widget (display only, no editing yet)

1. Build `LayerCard` in `nmtk_ui_core`: collapsed + expanded states, CNL preview section.
2. Build `LayerGroup` accordion wrapper.
3. Build `LayerEditorShell` scroll-based layout supporting rows and columns.
4. Wire `LayerEditorShell` to read `canvasProvider` state (display-only).
5. Add view-mode toggle to Studio toolbar (Graph ↔ Layers).

**Exit criteria**: Switching to Layers view shows the current graph as an ordered list of
collapsed cards. Graph view is unchanged.

---

### Phase 3 — Layer editing

1. Each card's expanded form is an editable form (dropdowns, sliders, text fields).
2. Editing a field calls `updateNodeParameters()` / `updateEdgeParameters()` on the canvas
   provider — same path as the existing graph canvas inspector.
3. Add Layer type, neuron size, synapse type, weight init pickers.
4. Add learning rule section (only shown when `CanvasEdge.learningRule != null`).
5. Drag-to-reorder layers.

**Exit criteria**: A user can build a feedforward SNN entirely in the layer editor and it
produces valid NIR via the existing export path.

---

### Phase 4 — Groups, columns, and parallel pathways

1. Add "New group" action.
2. Implement column-orientation layout for parallel pathways.
3. Add "branch" and "merge" node types to the layer editor (these map to existing
   `CanvasNode` with `nirType = 'nir.Input'` / `nir.Output`).
4. Validate that the CNL preview remains correct for branching topologies.

**Exit criteria**: A dual-stream network can be authored in the layer editor and produces
correct NIR.

---

### Phase 5 — Teaching mode (stretch goal)

1. CNL preview section is always expanded in a sidebar panel.
2. Typing in the CNL editor updates the layer cards in real time (live parse → canvas →
   layer model sync).
3. Tooltip on each card field links to the relevant CNL sentence grammar.

**Exit criteria**: A new user can build a network in the layer editor and read the CNL it
produces without having written any CNL manually.

---

## Open Questions

1. **Is the layer editor the *default* view for new projects?** (Recommended: yes, for
   feedforward networks. Switch to graph canvas only when the user adds a recurrent connection.)

2. **What happens when a user adds a recurrent edge in the graph canvas?** The layer editor
   should gracefully degrade — show the feedforward layers it can represent and a banner:
   *"This network has recurrent connections that cannot be displayed in layer view."*

3. **Does "orientation" belong on the bundle or just on the UI?** Orientation is purely a
   display preference — it should live in the workspace JSON, not in `internal_ir.json` or
   the NIR graph.

4. **Layer names:** Auto-generated (`layer_1`, `layer_2`) or user-editable? Recommended:
   user-editable, because they become the population names in CNL and in the NIR graph.
