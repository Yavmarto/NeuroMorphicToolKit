# CNL Editor ↔ Canvas Live-Sync Glow — Implementation Plan

**Date:** 2026-07-05  
**Module:** `neurocnl/frontend`  
**Goal:** When the user edits a CNL sentence the corresponding canvas node glows; when the user taps/selects a canvas node the corresponding CNL line glows (cursor jumps to it). Both directions must be instantaneous, non-blocking, and loop-free.

---

## Background & Current Architecture

| File | Role |
|---|---|
| `widgets/cnl_editor.dart` | CNL text field, `_CnlController` (syntax highlighting), `_CnlEditorState._syncSelectionState()` pushes cursor position to `workspaceProvider` |
| `widgets/canvas/network_canvas.dart` | `_CanvasNodeWidget` — node rendering; `isSelected` drives border colour; `boxShadow` is a static drop-shadow |
| `providers/canvas/canvas_provider.dart` | `CanvasState.selectedNodeIds` — canonical selection set |
| `providers/studio_sync_notifier.dart` | `StudioSyncController` — all CNL↔canvas round-trips; debounce logic; loop-prevention flags |
| `models/parsed_spec.dart` | `ParseSentence` has `.line` (1-based) and `.parsed.subject` (neuron name / entity name) |

### Missing link today
`ParseSentence` exposes `subject` and `line`, and `CanvasNode` has `label`/`id`. There is **no runtime map** from a CNL line number → node ID and vice-versa. Building and maintaining that map is the core of this work.

---

## Design Decisions

### 1. Where does the mapping live?
A new lightweight Riverpod provider:

```
providers/cnl_focus_provider.dart
```

State: `CnlFocusState` with two optional fields:
- `int? focusedLine` — 1-based CNL line currently active in the editor
- `String? focusedNodeId` — canvas node the user tapped

This is a **pure UI-focus signal**, intentionally separated from `selectedNodeIds` (structural selection) to avoid merge conflicts with existing clipboard/multi-select logic.

### 2. How is line→nodeId resolved?
At parse time, `ParseSentence.parsed.subject` already contains the neuron/population name. `CanvasNode.label` (or `parameters['name']`) carries the same name from the canonical doc pipeline. So:

```
Map<int, String> lineToNodeId   // line number → node id
Map<String, int> nodeIdToLine   // node id → first matching line
```

These maps are derived from `pipelineProvider.parseResult.sentences` joined with `canvasProvider.graph.nodes` by name match. Recomputed whenever either changes. Exposed as a selector on the new `cnlFocusProvider` (or as a separate computed provider).

### 3. Loop prevention
`StudioSyncController` already uses `_syncingCnlToCanvas` / `_syncingCanvasToCnl` flags. The new glow sync must not touch those flags — it is **display-only** and fires no API calls. A separate `_glowingFromEditor` bool in `CnlFocusNotifier` is sufficient to break the tiny loop:
- editor cursor → focus provider sets `focusedLine` → canvas reads it → canvas node tap → focus provider sets `focusedNodeId` → editor reads it and scrolls to line → (no further cursor change)

---

## Implementation Steps

### Step 1 — New provider: `cnl_focus_provider.dart`

**File:** `frontend/lib/providers/cnl_focus_provider.dart`

```dart
// cnl_focus_provider.dart
@riverpod
class CnlFocusNotifier extends _$CnlFocusNotifier {
  @override
  CnlFocusState build() => const CnlFocusState();

  void setFocusedLine(int? line) {
    if (state.focusedLine == line) return;
    state = state.copyWith(focusedLine: line, clearFocusedNodeId: true);
  }

  void setFocusedNode(String? nodeId) {
    if (state.focusedNodeId == nodeId) return;
    state = state.copyWith(focusedNodeId: nodeId, clearFocusedLine: true);
  }
}

@immutable
class CnlFocusState {
  final int? focusedLine;       // 1-based
  final String? focusedNodeId;
  const CnlFocusState({this.focusedLine, this.focusedNodeId});
  // copyWith omitted for brevity
}
```

**Why setFocusedLine clears focusedNodeId and vice-versa:** exactly one direction is "canonical" at any moment — prevents stale highlights on the other side.

---

### Step 2 — Line↔node mapping provider

**File:** `frontend/lib/providers/cnl_line_node_map_provider.dart`

```dart
@riverpod
({Map<int, String> lineToNode, Map<String, int> nodeToLine})
    cnlLineNodeMap(Ref ref) {
  final sentences = ref.watch(
    pipelineProvider.select((p) => p.parseResult?.sentences ?? const []),
  );
  final nodes = ref.watch(
    canvasProvider.select((c) => c.graph.nodes),
  );

  // Build a name→nodeId lookup from canvas nodes.
  final nameToId = <String, String>{
    for (final n in nodes)
      (n.label ?? n.parameters['name']?.toString() ?? n.id).toLowerCase(): n.id,
  };

  final lineToNode = <int, String>{};
  final nodeToLine = <String, int>{};
  for (final s in sentences) {
    if (!s.valid || s.parsed == null) continue;
    final subject = s.parsed!.subject.toLowerCase().trim();
    final nodeId = nameToId[subject];
    if (nodeId == null) continue;
    lineToNode[s.line] = nodeId;
    nodeToLine.putIfAbsent(nodeId, () => s.line);
  }
  return (lineToNode: lineToNode, nodeToLine: nodeToLine);
}
```

**Cost:** O(sentences × nodes) per update — negligible (<1 ms for typical CNL documents of <200 lines).

---

### Step 3 — Editor side: publish focused line

**File:** `widgets/cnl_editor.dart`  
**Touch point:** `_syncSelectionState()` (already called on every cursor move)

```dart
void _syncSelectionState() {
  // ... existing cursor tracking ...

  // NEW: compute 1-based line number from cursor offset
  final text = _controller.text;
  final offset = _controller.selection.extentOffset.clamp(0, text.length);
  final line = '\n'.allMatches(text.substring(0, offset)).length + 1;
  ref.read(cnlFocusNotifierProvider.notifier).setFocusedLine(line);
}
```

**Editor side: react to focusedNodeId (canvas → editor)**

In `_CnlEditorState.build()` add a `ref.listen`:

```dart
ref.listen<CnlFocusState>(cnlFocusNotifierProvider, (_, next) {
  final nodeId = next.focusedNodeId;
  if (nodeId == null) return;
  final map = ref.read(cnlLineNodeMapProvider);
  final line = map.nodeToLine[nodeId];
  if (line == null) return;
  _scrollEditorToLine(line);
});
```

---

### Step 4 — `_CnlController` line glow

Extend `_CnlController`:

```dart
int? _focusedLine;   // 0-based index (matches loop variable i in buildTextSpan)
set focusedLine(int? value) {
  if (_focusedLine == value) return;
  _focusedLine = value;
  notifyListeners();
}
```

Because `TextField` / `EditableText` does not cleanly support per-line background colours via `TextSpan`, the cleanest approach is a transparent `CustomPaint` layer drawn **behind** the text field inside a `Stack`:

```
Stack(
  children: [
    // Layer 0: line highlight painter
    _CnlLineHighlightPainter(
      focusedLine: focusedLine,           // 0-based
      lineHeight: _kLineHeight,
      scrollOffset: _textFieldScrollController.offset,
      paddingTop: _kEditorContentPadding.top,
    ),
    // Layer 1: the actual TextField
    TextField(...),
  ],
)
```

`_CnlLineHighlightPainter` is a `CustomPainter` that:
1. Reads `focusedLine` and `scrollOffset`
2. Paints a rounded rect at `y = focusedLine * lineHeight + paddingTop - scrollOffset`
3. Fills with `amber.withOpacity(0.12)` and draws a left border `amber` accent (2 px)

---

### Step 5 — Canvas side: glow on focused node

**File:** `widgets/canvas/network_canvas.dart`  
**Touch point:** `_CanvasNodeWidget.build()`

Add a `bool isGlowing` parameter alongside `bool isSelected`.

Compute which node should glow in the parent:

```dart
// In NetworkCanvas.build(), inside the nodes.map():
final focusState = ref.watch(cnlFocusNotifierProvider);
final lineMap = ref.watch(cnlLineNodeMapProvider);

final glowNodeId = focusState.focusedNodeId
    ?? (focusState.focusedLine != null
        ? lineMap.lineToNode[focusState.focusedLine]
        : null);

_CanvasNodeWidget(
  ...
  isGlowing: node.id == glowNodeId,
  ...
)
```

**Glow rendering in `_CanvasNodeWidget`:**

```dart
boxShadow: [
  // existing drop shadow
  BoxShadow(
    color: Colors.black.withValues(alpha: 0.10),
    blurRadius: 4,
    offset: const Offset(0, 2),
  ),
  // glow — only when isGlowing
  if (isGlowing)
    BoxShadow(
      color: accentColor.withValues(alpha: 0.55),
      blurRadius: 18,
      spreadRadius: 4,
    ),
],
border: Border.all(
  color: isGlowing
      ? accentColor
      : isSelected
          ? tokens.studioPalette.accent
          : tokens.chromeBorder,
  width: (isGlowing || isSelected) ? 2 : 1,
),
```

Wrap the `Container` in a `TweenAnimationBuilder<double>` on `glowOpacity` (0.0 → 0.55 over 200 ms) to animate glow in/out smoothly.

**Canvas node tap → publish focusedNodeId:**

```dart
onTap: () {
  _focusNode.requestFocus();
  final notifier = ref.read(canvasProvider.notifier);
  if (_isPrimaryModifierPressed) {
    notifier.toggleNodeSelection(node.id, additive: true);
  } else {
    notifier.selectNode(node.id);
  }
  // NEW: publish focus to the cross-widget provider
  ref.read(cnlFocusNotifierProvider.notifier).setFocusedNode(node.id);
},
```

---

### Step 6 — Scroll-to-line helper in `_CnlEditorState`

```dart
void _scrollEditorToLine(int line /* 1-based */) {
  if (!_textFieldScrollController.hasClients) return;
  final targetY = (line - 1) * _kLineHeight + _kEditorContentPadding.top;
  final viewportHeight = _textFieldScrollController.position.viewportDimension;
  final currentOffset = _textFieldScrollController.offset;
  final maxOffset = _textFieldScrollController.position.maxScrollExtent;

  // Only scroll if the line is outside the visible window
  if (targetY < currentOffset ||
      targetY + _kLineHeight > currentOffset + viewportHeight) {
    final desired = (targetY - viewportHeight / 2).clamp(0.0, maxOffset);
    _textFieldScrollController.animateTo(
      desired,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
  }
}
```

---

## File Change Summary

| File | Change type |
|---|---|
| `providers/cnl_focus_provider.dart` | **NEW** — `CnlFocusState`, `CnlFocusNotifier` |
| `providers/cnl_focus_provider.g.dart` | **NEW** — generated (run `flutter pub run build_runner build`) |
| `providers/cnl_line_node_map_provider.dart` | **NEW** — derived `lineToNode` / `nodeToLine` map |
| `widgets/cnl_editor.dart` | Extend `_syncSelectionState()`; add `ref.listen` for node focus; add `_scrollEditorToLine()`; add `_CnlLineHighlightPainter` layer in `_buildEditor()` |
| `widgets/canvas/network_canvas.dart` | Add `isGlowing` param to `_CanvasNodeWidget`; update `boxShadow`/`Border`; publish `setFocusedNode` on tap; read `cnlFocusNotifierProvider` in build |

**No backend changes required. No changes to `studio_sync_notifier.dart` (glow is display-only).**

---

## Tests to Write

| Test file | What to cover |
|---|---|
| `test/providers/cnl_focus_provider_test.dart` | `setFocusedLine` clears `focusedNodeId`; `setFocusedNode` clears `focusedLine`; idempotent set does not notify listeners |
| `test/providers/cnl_line_node_map_provider_test.dart` | Happy path name match; case-insensitive match; unmatched sentence → not in map; multiple sentences per node → first line wins in `nodeToLine` |
| `test/widgets/cnl_editor_line_highlight_test.dart` | Painter renders rect at correct Y offset for given `focusedLine`; scroll triggered when line is off-screen; no scroll when already visible |
| `test/widgets/network_canvas_glow_test.dart` | `isGlowing: true` produces larger `blurRadius` in `boxShadow`; border colour matches `accentColor`; glow not shown when `isGlowing: false` |

---

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| Name mismatch (subject ≠ node label) | Fall back to node `id` match if label-based lookup fails; log unresolved names in debug mode |
| Stale map after canvas-only edits (name changed in property panel) | Map is recomputed whenever `canvasProvider.graph.nodes` changes — Riverpod handles this automatically |
| Glow on every keystroke causes jank | `cnlLineNodeMapProvider` returns a stable struct when nothing changed (Riverpod equality guard); `_CanvasNodeWidget` is wrapped in `RepaintBoundary` — only the glowing node repaints |
| Two nodes with same display name | `nodeToLine` maps first match only; acceptable for now, can add disambiguation UI later |
| Focus loop (editor → canvas → editor → ...) | `setFocusedLine` clears `focusedNodeId` and vice-versa; loop terminates after one round-trip by design |
| glow flicker on rapid typing | Glow is read from stable provider; `_CnlLineHighlightPainter` respects `shouldRepaint` → only repaints when line or scroll offset changes |

---

## Order of Execution

1. `cnl_focus_provider.dart` + unit tests — pure logic, no UI
2. `cnl_line_node_map_provider.dart` + unit tests — pure logic
3. Canvas glow in `network_canvas.dart` — visual feedback immediately testable
4. Editor line highlight (`_CnlLineHighlightPainter` inside `_buildEditor()`)
5. Editor → canvas direction (publish `focusedLine` in `_syncSelectionState`)
6. Canvas → editor direction (`ref.listen` for `focusedNodeId` + `_scrollEditorToLine`)
7. Widget tests + golden screenshots

Run after each step:
```bash
cd neurocnl/frontend
flutter pub run build_runner build --delete-conflicting-outputs
flutter test
dart fix --apply && dart format .
```

---

## Part 2 — Canvas Interaction Improvements

### Feature A: Port Tap → "Add & Connect" Popup

#### Current behaviour (output ports)
- **Tap** an output port → enters `connectingFromNodeId` mode (click-to-connect flow)
- **Pan** from output port → live drag-wire to nearest input (existing, keep this)
- Input ports only accept connections; tapping does nothing unless connecting is active

#### New behaviour: tap output port → node-type picker popup
The goal is to let the user **tap** an output port and immediately see a compact popup listing compatible node types to add. Selecting one creates the new node, auto-positions it to the right of the source, and wires them in one action. **Drag still connects to existing nodes** — no behaviour change there.

#### Key distinction: tap vs. drag on port
`_PortWidget` already exposes separate `onTap`, `onPanStart`, `onPanUpdate`, `onPanEnd` callbacks. The separation is clean — no gesture disambiguation needed:

| Gesture | Current | New |
|---|---|---|
| Output port **tap** | Enters click-connect mode | Opens "Add Node" popup |
| Output port **pan/drag** | Starts live drag-wire | Same (no change) |
| Input port **tap** (while connecting) | Completes connection | Same |
| Input port **tap** (idle) | No-op | Optional: open node picker for upstream |

#### Implementation

**Step A1 — New widget: `_PortAddNodePopup`**

A compact `OverlayEntry` (matches the existing `_HandwritingOverlay` pattern). Shows a `ListView` of `NirNodeType` entries filtered by port type compatibility. Appears anchored just below/right of the tapped port in global coords.

```dart
// In NetworkCanvasState — mirrors _showHandwritingPopup
void _showPortAddNodePopup({
  required String sourceNodeId,
  required String sourcePortId,
  required Offset globalPortPosition,
  required Map<String, NirNodeType> nirTypeMap,
}) {
  _dismissPortAddNodePopup();

  final PortType? portType = _inferPortTypeById(sourceNodeId, sourcePortId);

  // Filter types that have at least one compatible input port
  final compatible = nirTypeMap.values.where((NirNodeType t) =>
    t.ports.any((p) => p.direction == 'input' &&
      (portType == null || _isTypeCompatible(portType, p)))
  ).toList()
    ..sort((a, b) => a.displayName.compareTo(b.displayName));

  _portAddNodeOverlay = OverlayEntry(
    builder: (context) => _PortAddNodePopup(
      globalPosition: globalPortPosition,
      nodeTypes: compatible,
      onSelected: (NirNodeType type) {
        _dismissPortAddNodePopup();
        _createNodeFromPort(
          sourceNodeId: sourceNodeId,
          sourcePortId: sourcePortId,
          type: type,
          nirTypeMap: nirTypeMap,
        );
      },
      onDismiss: _dismissPortAddNodePopup,
    ),
  );
  Overlay.of(context).insert(_portAddNodeOverlay!);
}
```

**Step A2 — `_createNodeFromPort` auto-positions and auto-connects**

```dart
void _createNodeFromPort({
  required String sourceNodeId,
  required String sourcePortId,
  required NirNodeType type,
  required Map<String, NirNodeType> nirTypeMap,
}) {
  // Find source node position — place new node 280px to the right
  final graph = ref.read(canvasProvider).graph;
  final sourceNode = graph.nodes.firstWhere((n) => n.id == sourceNodeId);
  final newPos = Offset(
    sourceNode.position[0] + kNodeWidth + 80,
    sourceNode.position[1],
  );

  final String newId = '${type.id}_${DateTime.now().millisecondsSinceEpoch}';
  final int nextIndex = graph.nodes.length + 1;
  final newNode = CanvasNode(
    id: newId,
    componentId: type.legacyComponentId ?? type.id,
    nirType: type.id,
    label: type.displayName,
    parameters: {
      ...type.defaultParameters,
      'name': '${type.displayName} $nextIndex',
    },
    position: [newPos.dx, newPos.dy],
    width: kNodeWidth,
    height: kNodeHeight,
    metadata: {'category': type.category},
  );

  // Pick the first compatible input port on the new node
  final targetPort = type.ports.firstWhere(
    (p) => p.direction == 'input',
    orElse: () => type.ports.first,
  );

  ref.read(canvasProvider.notifier).addNode(newNode);
  _createConnection(
    sourceNodeId: sourceNodeId,
    sourcePortId: sourcePortId,
    targetNodeId: newId,
    targetPortId: targetPort.id,
    nirTypeMap: nirTypeMap,
  );
}
```

**Step A3 — Wire the tap callback**

In `_PortWidget` / `_buildPorts`, change the output port `onTap`:

```dart
// BEFORE (in _CanvasNodeWidget._buildPorts):
onTap: () => onOutputPortTap(outputs[i].id),

// AFTER: route to parent via new callback
onTap: () => onOutputPortTap(outputs[i].id),  // parent decides tap vs. popup
```

In `NetworkCanvas.build()` node mapping, change the `onOutputPortTap` handler:

```dart
onOutputPortTap: (String portId) {
  _focusNode.requestFocus();
  // If already in connecting mode from same port → cancel (existing)
  final cs = ref.read(canvasProvider);
  if (cs.connectingFromNodeId == node.id && cs.connectingFromPortId == portId) {
    ref.read(canvasProvider.notifier).cancelConnecting();
    _resetConnectionHoverState();
    return;
  }
  // NEW: tap → add-node popup instead of entering click-connect mode
  final globalPortPos = _computePortGlobalPosition(node, portId, nirTypeMap);
  _showPortAddNodePopup(
    sourceNodeId: node.id,
    sourcePortId: portId,
    globalPortPosition: globalPortPos,
    nirTypeMap: nirTypeMap,
  );
},
```

Drag behaviour (pan from port) remains unchanged — `onPanStart` in `_PortWidget` still calls `canvasProvider.notifier.startConnecting(...)`.

**Files changed for Feature A:**

| File | Change |
|---|---|
| `widgets/canvas/network_canvas.dart` | Add `_showPortAddNodePopup`, `_dismissPortAddNodePopup`, `_createNodeFromPort`, `_PortAddNodePopup` widget; update `onOutputPortTap` handler; add `_computePortGlobalPosition` helper |

**Tests for Feature A:**

| Test | What to cover |
|---|---|
| `test/widgets/port_add_node_popup_test.dart` | Popup appears on output port tap; node created and connected on selection; popup dismissed on Escape; type list filtered by port compatibility |

---

### Feature B (advised): Double-click empty canvas → Add Node Picker

**Current:** stylus tap on empty canvas opens a text popup for handwriting. Mouse/touch users have no equivalent gesture.

**Proposed:** double-tap/double-click on any empty canvas area opens the same `_PortAddNodePopup` (no port filter applied, all types shown) at the click position. The new node is placed at the click scene position.

Touch point: `NetworkCanvas.build()` — the `InteractiveViewer`'s `onInteractionEnd` / `GestureDetector.onDoubleTap` on the canvas background.

---

### Feature C (advised): Right-click / long-press context menu on nodes and edges

**Current:** nodes have no right-click menu; operations require toolbar buttons or keyboard shortcuts.

**Proposed:** `GestureDetector.onSecondaryTap` (desktop right-click) and `onLongPress` (mobile) on `_CanvasNodeWidget` open a `PopupMenuButton`-style overlay with:
- Rename / edit label inline
- Duplicate node
- Delete node
- Set as input / output (marks the node as network I/O)
- Jump to CNL line (uses `cnlLineNodeMapProvider` from Part 1 — free integration)

For edges, same gesture on the bezier line shows: Edit weight, Edit delay, Flip polarity, Delete connection.

---

### Feature D (advised): Edge click → inline weight/delay editor

**Current:** clicking an edge selects it, but editing requires opening the property panel.

**Proposed:** clicking an edge shows a small inline floating card (similar to `_HandwritingOverlay` placement) with two numeric inputs (weight, delay) and a polarity toggle. Saves on blur. This eliminates the need to open the side panel for the most common edge edit.

Touch point: `_findEdgeAtPosition` is already in `NetworkCanvas` — add a tap handler to show the card.

---

### Feature E (advised): Fit-to-view button & mini-map

**Current:** users can zoom with Ctrl+scroll or keyboard shortcuts, but there is no "zoom to fit all nodes" action and no spatial overview for large networks.

**Proposed:**
1. **Fit-to-view** button (ZetaIcons-equivalent of "fit screen") in the canvas toolbar. Computes the bounding rect of all nodes and sets the viewport to show all of them with 32 px padding. One method on `CanvasController`.
2. **Mini-map** — a small `CustomPaint` in the bottom-right corner (100×70 px, semi-transparent dark panel) that renders scaled-down node rectangles and a "viewport indicator" rectangle. Draggable — panning the mini-map moves the main viewport. Toggleable via a toolbar button.

---

### Feature F (advised): Lasso-select on mouse (not just stylus)

**Current:** `StylusCanvasRecognizer` implements lasso only for stylus. Mouse users must Shift+click individual nodes.

**Proposed:** On mouse, detect a pan-start on empty canvas background (no node under pointer) with no modifier key pressed as the start of a marquee selection. Re-use the existing `MarqueeSelectionPainter` and `selectNodesInRect` — only the gesture entry point differs.

Touch point: add a secondary `GestureDetector` layer on the canvas background; distinguish from InteractiveViewer's pan by checking whether the pointer started on empty canvas.

---

### Feature G (advised): Snap-to-grid toggle

**Current:** nodes move freely (floating-point positions).

**Proposed:** a toggleable "snap to grid" mode (default: off, persisted in workspace preferences). When on, `updateNodePosition` rounds `x` and `y` to the nearest multiple of 20 px. Optionally draw a faint dot-grid `CustomPainter` layer on the canvas background when snapping is active.

---

### Feature H (advised): "Ghost wire" preview when hovering port (mouse)

**Current:** the live wire preview only appears during a pan/drag gesture. Hovering over a port on desktop does not give a preview of where a connection would go.

**Proposed:** on `MouseRegion.onHover` over an output port, show a short "ghost wire" extending ~60 px to the right. When the user moves their mouse after hover, the ghost follows. This gives a strong affordance that the port is interactive before committing to a drag.

---

## Updated File Change Summary

| File | Existing change | New change (Part 2) |
|---|---|---|
| `providers/cnl_focus_provider.dart` | NEW | — |
| `providers/cnl_line_node_map_provider.dart` | NEW | — |
| `widgets/cnl_editor.dart` | Modified | — |
| `widgets/canvas/network_canvas.dart` | Modified (glow) | Feature A (port popup), B (double-click), F (lasso), G (snap), H (ghost wire) |
| `widgets/canvas/canvas_shared_widgets.dart` | — | Feature D (edge inline card) |
| `widgets/canvas/canvas_toolbar.dart` (new or existing) | — | Feature E (fit-to-view, mini-map toggle) |

## Updated Execution Order

1. Part 1 steps 1–7 (glow sync) — as before
2. Feature A (port tap → popup) — highest user value, well-contained
3. Feature B (double-click → picker) — reuses Feature A popup
4. Feature C (context menu) — high value on desktop
5. Feature D (edge inline card) — reduces property panel dependency
6. Feature F (mouse lasso) — parity with stylus
7. Feature E (fit-to-view) — quick win; mini-map is a larger effort
8. Feature G (snap-to-grid) — polish
9. Feature H (ghost wire) — pure visual polish, low risk

---

## Part 3 — Touch-First Controls (missing from Part 2)

> **Context:** The canvas already branches on `_isMobile` for port layout (ports flip top/bottom instead of left/right). `MobileCanvasChrome` provides a floating pill bar with Undo/Redo/AutoLayout/Add buttons. All new interactions must provide a touch alternative — gestures must be reachable with a thumb, without hover, without a keyboard, and with 44-pt minimum tap targets.

---

### Touch alternative map — per feature

| Feature | Desktop gesture | Touch alternative | Implementation note |
|---|---|---|---|
| **A** Port tap → node picker | Tap output port | Same — tap fires `onTap` on `_PortWidget` | Works as-is; popup items must be ≥ 48 px tall (thumb target) |
| **A** Port drag → connect | Pan from port | Same — `onPanStart/Update/End` works on touch | Already works |
| **B** Double-click → picker | `onDoubleTap` on canvas | `onLongPress` on canvas background | Two separate handlers; long-press shows picker at press position |
| **C** Context menu on node | `onSecondaryTap` (right-click) | `onLongPress` on node header | Already planned; ensure `onLongPress` is wired on `_CanvasNodeWidget` |
| **C** Context menu on edge | `onSecondaryTap` on bezier | Long-press `GestureDetector` over edge hit region | Need a transparent `GestureDetector` layer over edge painter |
| **D** Edge inline card | Click on edge | Long-press on edge | Same `GestureDetector` overlay as above |
| **E** Fit-to-view | Canvas toolbar button | Add to `MobileCanvasChrome.extraRightActions` | Pass `onFitToView` callback through `MobileCanvasChrome` |
| **E** Mini-map | Floating corner widget | Hidden on mobile by default; show via toggle in bottom bar | Too small to be useful on phone; optional on tablet |
| **F** Lasso-select | Pan on empty canvas (mouse) | Two-finger tap-and-drag (one finger pans, two fingers select) | Use `ScaleGestureRecognizer`; single-finger on empty = pan (InteractiveViewer), two-finger drag on empty = lasso |
| **G** Snap-to-grid | Toolbar toggle | Bottom bar toggle button | Add to `MobileCanvasChrome.extraLeftActions` |
| **H** Ghost wire on hover | `MouseRegion.onHover` | Not applicable — touch has no hover state | Skip on touch; port already pulses when `isConnecting` is active |

---

### Touch-specific additions not covered by desktop features

#### T1 — Floating "Add Node" FAB opens full node picker
`MobileCanvasChrome.onAddPrimitive` already exists but currently opens the component library sidebar (if wired). Change the callback so it opens the same `_PortAddNodePopup` (unfiltered, all types) centered on screen, styled as a bottom sheet on mobile.

```dart
// In studio_screen.dart (or canvas_host_screen.dart):
onAddPrimitive: () => _showAddNodeBottomSheet(context, ref, nirTypeMap),
```

`_showAddNodeBottomSheet` calls `showModalBottomSheet` with a `ListView` of all `NirNodeType` entries, each with a 56 px tile. On selection, node is created at the current viewport centre.

#### T2 — Node action sheet on long-press (replaces right-click context menu)
On touch, long-press on a node header opens `showModalBottomSheet` with action tiles:
- Rename (opens inline `TextField` in the node header)  
- Duplicate  
- Delete  
- Jump to CNL line (from `cnlLineNodeMapProvider`)  
- Set as Input / Output  

Tile height ≥ 52 px, icons left-aligned. Dismiss on drag-down or tap outside.

```dart
// In _CanvasNodeWidget.build():
GestureDetector(
  onLongPress: () => _showNodeActionSheet(context, ref, node),
  child: ... // existing header GestureDetector wraps this
)
```

#### T3 — Edge long-press action sheet
Since bezier edges are difficult to long-press precisely on mobile (thin stroke), increase the touch hit tolerance from `kEdgeHitTolerance` (currently 8 px) to **20 px** when `_isMobile` is true. On long-press in the edge hit region, show a compact bottom sheet:
- Edit weight (numeric input)
- Edit delay (numeric input)
- Flip polarity (excitatory ↔ inhibitory)
- Delete connection

#### T4 — Two-finger long-press → multi-select mode
When the user places two fingers on the canvas simultaneously (scale gesture with near-zero scale change), enter a "multi-select mode" that activates lasso behaviour for a single subsequent drag. This is analogous to the desktop Shift+click flow.

```dart
// Detect in onScaleStart when pointerCount == 2 and scale delta < 0.05:
_enterMultiSelectMode();
```

#### T5 — Fit-to-view in `MobileCanvasChrome`
Add a `ZetaIcons.fit_to_screen` (or equivalent) button to the `MobileCanvasChrome` bottom bar as `extraRightActions`. Wire to the same `CanvasController.fitToView()` method defined in Feature E. This is the primary way mobile users recover after getting lost in a large canvas.

```dart
// MobileCanvasChrome call site:
extraRightActions: [
  CanvasChromeIconButton(
    icon: Icons.fit_screen,  // ZETA-MIGRATION-EXEMPT
    tooltip: 'Fit to View',
    enabled: true,
    onPressed: () => ref.read(canvasProvider.notifier).fitToView(),
  ),
],
```

#### T6 — Port hit target size on mobile
The current port hit target is `kPortHitTargetSize = 30.0` — too small for a finger. When `_isMobile`, expand the hit target to **48 px** (Apple/Google minimum) without changing the visual dot size. This applies to both input and output ports.

```dart
// In _PortWidget.build():
final double hitSize = isMobile ? 48.0 : kPortHitTargetSize;
return Positioned(
  left: position.dx - (hitSize / 2),
  top: position.dy - (hitSize / 2),
  child: SizedBox(
    width: hitSize,
    height: hitSize,
    child: CanvasPortWidget(...),
  ),
);
```

---

### Updated file change table with touch columns

| File | Desktop change | Touch change |
|---|---|---|
| `widgets/canvas/network_canvas.dart` | Feature A–H as before | T2 long-press on node, T3 edge long-press, T4 two-finger multi-select, T6 port hit-target scaling |
| `widgets/canvas/mobile_canvas_chrome.dart` | — | T1 FAB → bottom sheet, T5 fit-to-view button |
| `widgets/canvas/canvas_shared_widgets.dart` | Feature D edge card | T3 bottom sheet variant |
| `screens/studio/studio_screen.dart` or `canvas_host_screen.dart` | — | T1 `onAddPrimitive` wired to bottom sheet |

---

### Touch test matrix additions

| Test | What to cover |
|---|---|
| `test/widgets/mobile_canvas_chrome_test.dart` | Fit-to-view button present; Add button opens bottom sheet; tiles are ≥ 48 px |
| `test/widgets/network_canvas_touch_test.dart` | Port hit target is 48 px on mobile; long-press on node opens action sheet; edge long-press hits with 20 px tolerance; two-finger gesture enters multi-select mode |
| `test/widgets/port_add_node_popup_test.dart` | Popup items are ≥ 48 px tall on mobile; bottom sheet shown on mobile instead of overlay |
