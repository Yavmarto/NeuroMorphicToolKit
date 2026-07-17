# iPad & Android Pen Support Implementation Plan

## Verified Implementation Status (2026-07-04)
**DONE (mostly).** Code-verified against `neurocnl/frontend/lib/widgets/canvas/`:
- Stylus vs touch differentiation: `stylus_canvas_recognizer.dart` (full)
- Handwriting-to-node: `network_canvas.dart` `_showHandwritingPopup`/`_HandwritingOverlay` + `nir_node_type_resolver.dart` fuzzy match (full)
- Lasso selection: implemented as rect-overlap marquee (`canvas_provider.dart` `selectNodesInRect`), not true point-in-polygon — **partial**, item 3's polygon algorithm not built
- Node-port drag-to-connect, hover previews, pressure-sensitive stroke width, eraser via inverted stylus: all implemented (full)
- **Not implemented**: item 4 double-tap stylus action for delete/property panel
- Tests exist: `network_canvas_stylus_test.dart`, `stylus_canvas_recognizer_test.dart`
- Remaining work: true freeform lasso polygon, double-tap action

## Goal Description
Enhance the NeuroMorphicToolKit canvas (`network_canvas.dart`) to fully support stylus inputs (Apple Pencil / Android Pen). This will enable precise routing, handwriting-to-node creation, and lasso selection while preserving native touch gestures for panning and zooming.

## 1. Differentiating Pen vs. Touch (Core Interaction)
- **Target File**: `neurocnl/frontend/lib/widgets/canvas/network_canvas.dart`
- **Plan**:
  - Wrap the `InteractiveViewer` (or its child) in a Flutter `Listener` widget.
  - Inspect `PointerEvent.kind`. If `PointerDeviceKind.stylus` or `PointerDeviceKind.invertedStylus`, route the event to canvas drawing/selection logic.
  - If `PointerDeviceKind.touch`, route the event to `InteractiveViewer` for standard panning and zooming.

## 2. Handwriting-to-Node Creation (The "LIF" Popup)
- **Target File**: `neurocnl/frontend/lib/widgets/canvas/network_canvas.dart`
- **Plan**:
  - Detect a tap or short press on an empty canvas space using the stylus.
  - Spawn an overlaid, invisible `TextField` widget exactly at the stylus coordinates, auto-focused.
  - Allow the user to utilize native iPadOS Scribble or Android handwriting recognition to write a node type (e.g., "LIF").
  - On `onSubmitted` of the text field, dismiss the field, match the string to a `NirNodeType`, and dispatch a node creation event to the `CanvasProvider`.

## 3. Lasso Selection & Node Connection
- **Target File**: `neurocnl/frontend/lib/widgets/canvas/network_canvas.dart` & `ConnectionPainter`
- **Plan**:
  - On stylus drag across empty space, capture `List<Offset>` stroke points.
  - Render a dashed selection outline using `CustomPaint`.
  - On pointer up, execute a 2D point-in-polygon algorithm to select all `CanvasNode` instances whose bounding boxes intersect the drawn lasso shape.
  - On stylus drag originating from a node port, bypass the canvas pan and instantly begin drawing a connection wire to another port.

## 4. Low-Hanging Fruit Enhancements
- **Hover Previews**: Use `Listener.onPointerHover` to detect when the stylus is floating over the screen. Highlight valid target ports for connection before the stylus touches the glass.
- **Pressure Sensitivity**: Utilize `PointerEvent.pressure` (0.0 to 1.0) inside `ConnectionPainter` to dynamically adjust the `strokeWidth` of the connection wire as the user draws it, providing tactile visual feedback.
- **Double Tap (Apple Pencil)**: Intercept the system channel for stylus double-tap to quickly delete a selected node or open its property panel.

## Verification Plan
- **Testing**: Connect an iPad or Android tablet (or use a simulator with stylus emulation) and verify that fingers only pan/zoom, while the stylus exclusively draws/selects.
- **Review**: Ensure `canvas_provider.dart` correctly handles the new stylus-driven selection and creation events without breaking existing mouse/touch fallbacks.
