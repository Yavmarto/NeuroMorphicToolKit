# Port-anchored "add connected node" `+` on all canvases

Date: 2026-07-31 · Module: `neurocnl/frontend` (package `neurocnl_studio`)

## What was asked

A `+` next to every connector port on every node, opening the same Add-Node popup but
filtered to node types that can actually connect in that direction, with each candidate drawn
showing its ports on the correct side, and clicking a port creating the node *and* the wire.
Plus a search field in the popup.

## What was built

New files:

- `lib/widgets/canvas/canvas_connect_palette.dart` — `showCanvasConnectPalette(...)`, the
  port-anchored palette. Model-agnostic (`CanvasConnectPaletteEntry` / `…Port` / `…Result`)
  because the two canvases have unrelated `PortType` declarations. Tiles render as mini node
  cards with the facing ports down the correct edge; each port row is its own tap target,
  keyed `palette_port_<entryId>_<portId>`. Tapping the tile body takes the first port.
- `lib/widgets/canvas/canvas_palette_search_field.dart` — `CanvasPaletteSearchField`, shared
  by all three palettes.
- `lib/utils/canvas_palette_search.dart` — `canvasPaletteMatchScore` /
  `filterCanvasPaletteItems`. Ranks exact → label-prefix → label-substring → keyword
  (port ids, category, type id) → fuzzy. Reuses `levenshteinDistance`, made public in
  `utils/nir_node_type_suggestions.dart` rather than copied.

Changed:

- `canvas_shared_widgets.dart` — `CanvasPortAddButton` (+ `kCanvasPortAddHitTargetSize`),
  tap-only so it never competes with the port's drag-to-connect or the canvas pan.
- `pipeline_phase_canvas.dart` — port-geometry helpers (`_inputPortLocalTopLeft`,
  `_outputPortLocalTopLeft`, `_portAddLocalTopLeft`), `_buildPortAddButtons`,
  `_handleAddFromPort`; port dots now carry `gestureDetectorKey`, so pipeline ports are
  addressable in tests for the first time; local `_categoryColor`/`_categoryIcon` duplicates
  deleted.
- `network_canvas.dart` — `_buildPortAddButtons` reusing `_getPortPosition`, and
  `_handleAddFromPort` which reuses `_createConnection`'s validation.
- `canvas_provider.dart` — `addNodeWithEdge`, so one gesture is one undo step (`addNode` and
  `addEdge` each push history).
- `pipeline_dag.dart` — `pipelineNodeTypesFor(phase, platforms)`, extracted from
  `canvas_screen.dart`; now the single candidate-set source for every add-node surface.
- `theme/nir_node_styles.dart` — `pipelineCategoryColor` / `pipelineCategoryIcon`, previously
  duplicated across `canvas_screen.dart` and `pipeline_phase_canvas.dart`.
- `canvas_screen.dart` — both bottom-bar palettes gained the search field; the components
  fetch is now guarded so an unreachable backend degrades to built-in types instead of a dead
  Add button (same guard added in the port palette).

## Decisions

- **Direction-only filtering**, per the user: an output-side `+` offers types with ≥1 input
  and vice versa. No data-type filter — `PortSpec.type` / `inferNirPortTypes` coverage is thin
  enough that it would hide connectable nodes. Real mismatches are still reported by the
  existing connect-time checks.
- No input-port occupancy check was added; there is none today and adding one would change
  drag-to-connect behaviour too.
- The palette stays a centred dialog / bottom sheet, matching the existing palettes. Anchoring
  it to the button would be new work in `MobileCanvasChrome` and was not requested.

## Gotcha worth remembering

A `Positioned` child outside its parent Stack's `size` **paints** under
`clipBehavior: Clip.none` but is **never hit-tested** — the parent rejects the pointer first.
The first implementation put the `+` inside the node card's Stack at a negative offset; it
rendered and `find.byKey` located it, but taps went to the grid painter. Hence the
canvas-level placement.

## Tests

New: `test/widgets/canvas/canvas_connect_palette_test.dart` (9),
`test/widgets/canvas/pipeline_port_add_test.dart` (6),
`test/widgets/canvas/network_port_add_test.dart` (4),
`test/utils/canvas_palette_search_test.dart` (13).
Extended: `test/models/pipeline_dag_test.dart` (`pipelineNodeTypesFor`),
`test/providers/canvas/canvas_provider_pipeline_dag_test.dart` (`addNodeWithEdge` undo).

Palette widget tests must override `componentsProvider` — unstubbed it awaits real HTTP that
never resolves under the test binding, and the palette silently never opens.

`flutter analyze lib test` → 0 errors. `flutter test` → the pre-existing baseline failure set,
unchanged (verified by stashing the change and re-running); all new tests pass.

## Follow-up, same day: the port dot *is* the `+`, and edges can be deleted

Two changes on top of the above, both requested after seeing the first version.

### The floating `+` is gone; the port dot carries it

`CanvasPortAddButton` was deleted. `CanvasPortWidget` now draws a `+` glyph inside
the dot (faint at rest, firm once armed) and the canvases give consecutive taps on one dot
two different meanings:

- **First tap** — arms the port. On an output that is the existing `startConnecting`
  behaviour, so drag-to-connect and tap-an-input-to-finish are untouched. On an input it is
  new: previously an input tap did nothing unless a connection was already in flight.
- **Second tap on the same dot** — opens the add-node palette (`fromOutput` for an output
  dot, `fromInput` for an input dot).

Armed state is local to each canvas (`_armedPortNodeId` / `_armedPortId`), not in
`canvasProvider`: `startConnecting` is defined as "an output is the connection source", and
reusing it to mark an armed *input* would break the drop logic. It is cleared on Escape, on a
background tap, on an edge tap, when a drag ends, and when the palette opens.

Side benefit: nothing is positioned outside a node card any more, so the hit-test constraint
noted below no longer applies to the add affordance.

### Edges can be selected and deleted

The architecture canvas already had edge tap-to-select and a Delete/Backspace handler. The
pipeline canvas had the Delete handler but **nothing ever set `selectedEdgeId`** — no edge
hit-testing existed, so an edge could never be selected there at all.

- `pipeline_phase_canvas.dart` — new `_edgeAtLocalPosition` samples each wire's curve
  (`pipelineEdgeDistance`) with a zoom-corrected tolerance, and the background `onTapDown`
  selects a wire instead of clearing the selection when the tap lands on one. The painter
  takes `selectedEdgeId` and draws that wire thicker in the studio accent.
- New shared `CanvasEdgeDeleteButton` (`✕`) is positioned at the selected edge's midpoint on
  **both** canvases, keyed `pipeline_edge_delete` / `nir_edge_delete`. The Delete/Backspace
  shortcuts still work; this just makes the action visible.
- The endpoint maths that the painter, the live-wire preview, hit-testing and the `✕` all
  need was consolidated into `pipelinePortCentre` / `pipelineEdgeEndpoints` /
  `pipelineEdgeControlPoints` / `pipelineEdgePointAt`. It had been written out three times.
  On the NIR side the painter's badge midpoint became the shared
  `connectionCurveMidpoint`.

Tests were rewritten for the two-stage tap and extended with edge selection/deletion:
`pipeline_port_add_test.dart` is now 11 cases, `network_port_add_test.dart` 8.

## Not done

`PipelineOverviewCanvas` (read-only, no ports) and `PipelinePhaseId.infer` (has a DAG and a
palette path but no tab) are untouched. The macOS app was not launched — verification is
static analysis plus widget tests.
