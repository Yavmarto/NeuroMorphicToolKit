import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:neuro_toolkit/features/neurocnl/widgets/canvas/canvas_stylus_layer.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/canvas/canvas_viewport.dart';

/// Base for every canvas surface -- Architecture (`NetworkCanvas`), Train and
/// Eval (both `PipelinePhaseCanvas`).
///
/// Owns the pan/zoom ([CanvasViewportMixin]) and stylus lasso/handwriting
/// ([CanvasStylusMixin]) behaviour every canvas mixes in, plus the primary-
/// modifier check and the mobile drag-vs-tap guard ([dragStartGuard]) that
/// used to be copy-pasted per canvas -- and, for the Train/Eval canvases,
/// never actually applied (see CEL-479: `pipeline_phase_canvas.dart` still
/// selected on drag-start unconditionally after the Architecture canvas was
/// fixed in CEL-476). Landing the guard here means a future change to it
/// only has to happen once.
abstract class CanvasSurfaceState<W extends ConsumerStatefulWidget>
    extends ConsumerState<W>
    with CanvasViewportMixin<W>, CanvasStylusMixin<W> {
  /// True while the platform's "primary" selection modifier (⌘ on macOS,
  /// Ctrl elsewhere) is held, toggling additive multi-select.
  bool get isPrimaryModifierPressed =>
      HardwareKeyboard.instance.isControlPressed ||
      HardwareKeyboard.instance.isMetaPressed;

  /// Wraps [selectStructurally] so a touch-drag doesn't fire it.
  ///
  /// On mobile/compact ([isVertical]) layouts, selecting a node pops the
  /// inspector bottom sheet (see `CanvasScreen`'s listener on the selected-
  /// node provider), which steals the pointer mid-drag before Flutter's pan
  /// recognizer settles -- so a touch-drag could never actually move the
  /// node. Skipping the selection step at drag-start avoids that; the
  /// node's `onTap` still selects (and opens the sheet) normally. Desktop/
  /// wide layouts keep selecting on drag-start, since nothing there pops a
  /// sheet.
  VoidCallback dragStartGuard({
    required bool isVertical,
    required VoidCallback selectStructurally,
  }) => isVertical ? () {} : selectStructurally;

  int _handledWorkspaceRestoreFocusRevision = 0;

  /// Runs [panToFirstNode] once per new nonzero workspace-load [revision],
  /// after the current frame lays out (so `context.findRenderObject()` has
  /// a size to pan within).
  void scheduleWorkspaceRestoreFocus(
    int revision,
    VoidCallback panToFirstNode,
  ) {
    if (revision == 0 || revision == _handledWorkspaceRestoreFocusRevision) {
      return;
    }
    _handledWorkspaceRestoreFocusRevision = revision;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      panToFirstNode();
    });
  }

  @override
  void dispose() {
    canvasDisposeStylusLayer();
    super.dispose();
  }
}
