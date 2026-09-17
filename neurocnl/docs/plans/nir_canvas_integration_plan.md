# NIR Canvas Integration Plan — neurocnl Studio

> **Date:** 2026-05-17
> **Scope:** Replace / evolve the generic `NetworkCanvas` into a NIR-native editable graph viewer, informed by analysis of `open-neuromorphic/nirviz`.

---

## Executive Summary

**Do not try to reuse nirviz's frontend code — there isn't any.** nirviz is a Python library that feeds NIR graphs into Graphviz and spits out static PNG/SVG files. It has zero interactivity, zero editing capabilities, and no JavaScript/TypeScript/Dart codebase. The only thing worth salvaging is its **style taxonomy** (`style.yml`), which maps NIR node type names to colors and shapes.

**Do not rewrite the canvas from scratch either.** The current `NetworkCanvas` (`neurocnl/frontend/lib/widgets/canvas/network_canvas.dart`) is already a well-engineered editable graph editor with zoom, pan, drag-and-drop, ports, connections, keyboard shortcuts, and Riverpod state management. Throwing that away to rebuild a NIR viewer would waste months. The right move is to **evolve the existing canvas into a NIR-native editor**.

---

## What Is Useful From nirviz

1. **Style taxonomy** (`nirviz/style.yml`): It categorizes NIR node types and assigns them Graphviz colors/shapes. This is a valuable design artifact to port to Dart.
2. **Node type coverage**: It recognizes `Input`, `Output`, `Affine`, `Linear`, `Conv1d`, `Conv2d`, `Flatten`, `AvgPool`, `CubaLIF`, `LIF`, `IF`, `LI`, etc. This forms the basis of the NIR palette.
3. **Nothing else**: The rendering, layout, and traversal logic is trivial and already exists in the codebase in superior form.

---

## Current State of the Canvas

There are **two** graph visualizations in neurocnl today:

- **`NetworkCanvas`** (`widgets/canvas/network_canvas.dart`): The editable generic component canvas. Nodes are `CanvasNode` + `ComponentBlock`, with drag-and-drop from a sidebar, ports, connections, property panels, and CNL sync.
- **`NetworkGraphView`** (`widgets/network_graph_view.dart`): A read-only generated network preview (CustomPainter, circles/rectangles, tiered BFS auto-layout). It explicitly disclaims being an editor.

Additionally, the backend already has `nir_graph_serializer.py`, which converts `nir.NIRGraph` -> JSON topology (though it only handles `Input`, `Output`, `LIF`, `Linear`, and `Delay` today).

---

## Recommended Approach: Evolve, Don't Rewrite

Upgrade the existing `NetworkCanvas` to speak NIR natively. Keep the interaction layer (zoom, pan, drag, ports, keyboard) and replace the generic component model with a NIR type system.

---

## Implementation Plan

### Phase 1: NIR Style Taxonomy & Theme
**Goal:** Port nirviz's visual language into the Flutter theme system, but make it look modern and consistent with `shadcn_ui`.

- **New file:** `neurocnl/frontend/lib/theme/nir_node_styles.dart`
  - Map NIR type names -> `Color`, `IconData`, `ShapeBorder`, and `NirNodeCategory` (input/output, connection, computation, pool, transform).
  - Port nirviz colors but elevate them to the design system (e.g., use `shadcn_ui` tokens, better contrast, dark-mode variants).
- **Update:** `neurocnl/frontend/lib/theme/app_theme.dart` to expose NIR category colors.

---

### Phase 2: NIR Node Type Registry
**Goal:** Replace the generic `ComponentBlock` palette with canonical NIR node definitions.

- **New file:** `neurocnl/frontend/lib/models/nir_node_type.dart`
  - Define `NirNodeType` with fields: `id` (e.g., `nir.LIF`), `displayName`, `category`, `icon`, `parameterSchema` (for dynamic property panel rendering).
  - Cover all nirviz-recognized types + any extras the backend supports.
- **New provider:** `neurocnl/frontend/lib/providers/canvas/nir_types_provider.dart`
  - Expose the palette for the sidebar.
- **Update:** `neurocnl/frontend/lib/models/canvas/component.dart` or create a parallel model so the canvas can reference either generic components or NIR types.

---

### Phase 3: Canvas Model Extension
**Goal:** Allow `CanvasNode` to carry NIR type identity.

- **Update:** `neurocnl/frontend/lib/models/canvas/canvas.dart`
  - Add `String? nirNodeType` to `CanvasNode`.
  - Keep `componentId` for backward compatibility, but when `nirNodeType` is set, the renderer uses the NIR style registry.
- **Update:** `canvas.g.dart` via `build_runner`.

---

### Phase 4: Visual Redesign of the Canvas Node
**Goal:** Make NIR nodes look polished and informative.

- **Update:** `_CanvasNodeWidget` in `network_canvas.dart`
  - Use NIR category colors for the header accent (port from Phase 1).
  - Replace generic icons with NIR-specific ones.
  - Show parameter badges directly on the node card (e.g., a `LIF` node shows "tau=20 ms | v_th=1.0" as chips).
  - Improve shadows, borders, and selection states to match `shadcn_ui` elevation.
  - Add shape variants: rounded rects for connections, circles for neuron populations, etc.

---

### Phase 5: Auto-Layout for NIR Graphs
**Goal:** When importing a NIR graph, nodes should not land as a pile of overlapping nodes.

- **Port:** The tiered BFS layout algorithm from `NetworkGraphView._computeTieredLayout()` into `canvas_provider.dart` as `autoLayoutNirGraph()`.
- **Add:** An "Auto Layout" button to the canvas toolbar.
- **Trigger:** Call auto-layout immediately after importing a NIR graph.

---

### Phase 6: NIR Import / Export
**Goal:** Bidirectional bridge between the canvas and real NIR files.

- **Backend:** Extend `neurocnl/backend/app/services/nir_graph_serializer.py`
  - Add support for `CubaLIF`, `IF`, `LI`, `Conv1d`, `Conv2d`, `Flatten`, `AvgPool`, `SumPool`, and any other NIR nodes the backend can handle.
  - Implement `deserialize_nir_graph()` to turn Studio JSON back into `nir.NIRGraph`.
- **Frontend API:** Add endpoints in `neurocnl/frontend/lib/services/canvas_api_client.dart` for `/nir/import` and `/nir/export`.
- **UI:** Add Import/Export buttons to the canvas screen (or toolbar) that file-pick `.nir`/`.json` files and call the backend.

---

### Phase 7: NIR-Aware Property Panel
**Goal:** Editing a `LIF` node should show `tau_mem`, `v_threshold`, etc., not generic parameter blobs.

- **Update:** `neurocnl/frontend/lib/widgets/canvas/property_panel.dart`
  - Build a dynamic form generator based on the `NirNodeType.parameterSchema` from Phase 2.
  - Render sliders for time constants, numeric fields for thresholds, matrix previews for weights, etc.
  - Update `CanvasNotifier.updateNodeParameters()` as usual -- the provider does not change, only the UI layer does.

---

### Phase 8: Palette & Sidebar Integration
**Goal:** The component library sidebar should offer NIR primitives.

- **Update:** `neurocnl/frontend/lib/widgets/canvas/component_library_sidebar.dart`
  - Add a "NIR Primitives" section with draggable NIR node types.
  - Keep the generic component section behind a toggle or tab if backward compatibility is desired.

---

## Effort Estimate

| Phase | Effort | Risk |
|-------|--------|------|
| 1 -- Theme | 1 day | Low |
| 2 -- Type Registry | 2--3 days | Low |
| 3 -- Model Extension | 1 day | Low |
| 4 -- Visual Redesign | 3--5 days | Medium (design iteration) |
| 5 -- Auto-Layout | 1--2 days | Low |
| 6 -- Import/Export | 3--5 days | Medium (backend serialization) |
| 7 -- Property Panel | 2--3 days | Medium |
| 8 -- Sidebar | 1 day | Low |

**Total: roughly 2--3 weeks** for a polished, editable NIR canvas that replaces the current generic one.

---

## Why This Beats a Rewrite

- **Keep the proven interaction model** (zoom, pan, drag, ports, keyboard shortcuts, edge creation) that already works.
- **Keep the state management** (Riverpod) and backend sync (CNL generation, validation) without rewriting the orchestration layer.
- **`NetworkGraphView` already proves NIR-like nodes can be rendered nicely** -- it just needs to become editable and move into `NetworkCanvas`.
- **The backend already has NIR serialization** -- extending it is far cheaper than building a new NIR parser in Dart.

---

## What To Ignore From nirviz

- The Python `graphviz` rendering pipeline (irrelevant for a Flutter frontend).
- The CLI tool (`python -m nirviz`) -- Studio is the UI.
- The static image output (`to_image()`, `show()`) -- the goal is live, editable vectors.
