import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'package:neuro_toolkit/features/neurocnl/widgets/canvas/canvas_handwriting_overlay.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/canvas/canvas_shared_widgets.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/canvas/canvas_viewport.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/canvas/stylus_canvas_recognizer.dart';

/// Stylus behaviour shared by every canvas: drag on empty canvas to lasso
/// (rubber-band) select, tap on empty canvas to write a node type by hand.
///
/// This used to live entirely inside the Architecture canvas, so the Train and
/// Eval canvases had neither — the same pen did different things depending on
/// which tab was open. Hosts mix this in alongside [CanvasViewportMixin] and
/// implement the four hooks below; everything else (arena wiring, lasso state,
/// overlay lifecycle) is here.
mixin CanvasStylusMixin<T extends StatefulWidget> on State<T>
    implements CanvasViewportMixin<T> {
  // ── Hooks the host must provide ───────────────────────────────────────────

  /// True when [scenePosition] is over empty canvas — no node, no port. The
  /// recognizer declines anywhere else, so node drags and port drags keep
  /// winning the arena there for every pointer kind.
  bool canvasIsEmptyAt(Offset scenePosition);

  /// Selects everything inside the lassoed scene rect.
  void canvasSelectInRect(Rect sceneRect);

  /// Display names to offer as suggestion chips for the text written so far.
  List<String> canvasSuggestNodeTypes(String query);

  /// Creates a node from handwritten [text] at [scenePosition]. The host is
  /// responsible for telling the user when nothing matched.
  void canvasCreateNodeFromText(String text, Offset scenePosition);

  // ── Lasso state ──────────────────────────────────────────────────────────

  Offset? _lassoStart;
  Offset? _lassoEnd;

  /// Non-null while a lasso drag is in progress; the host paints
  /// [MarqueeSelectionPainter] between them.
  Offset? get canvasLassoStart => _lassoStart;
  Offset? get canvasLassoEnd => _lassoEnd;

  OverlayEntry? _handwritingOverlay;
  TextEditingController? _handwritingController;
  VoidCallback? _handwritingDismissOnPan;

  /// Gesture-recognizer entry for the canvas's [RawGestureDetector], which
  /// claims stylus pointers on empty canvas before [InteractiveViewer] can.
  Map<Type, GestureRecognizerFactory> get canvasStylusGestures =>
      <Type, GestureRecognizerFactory>{
        StylusCanvasRecognizer:
            GestureRecognizerFactoryWithHandlers<StylusCanvasRecognizer>(
              () => StylusCanvasRecognizer(
                hitTestEmptyCanvas: _isEmptyCanvasAtGlobal,
                onDown: canvasHandleStylusDown,
                onMove: canvasHandleStylusMove,
                onUp: canvasHandleStylusUp,
                onCancel: canvasResetStylusGesture,
              ),
              (StylusCanvasRecognizer instance) {},
            ),
      };

  bool _isEmptyCanvasAtGlobal(Offset globalPosition) {
    final RenderObject? renderObject = context.findRenderObject();
    if (renderObject is! RenderBox) return false;
    return canvasIsEmptyAt(
      canvasSceneFromViewport(renderObject.globalToLocal(globalPosition)),
    );
  }

  Offset _sceneFromGlobal(Offset globalPosition) {
    final RenderBox box = context.findRenderObject()! as RenderBox;
    return canvasSceneFromViewport(box.globalToLocal(globalPosition));
  }

  void canvasHandleStylusDown(PointerDownEvent event) {
    if (event.kind == PointerDeviceKind.invertedStylus) {
      // The eraser tip is handled on down by the host's ambient pointer
      // listener, not as a lasso.
      return;
    }
    final Offset scenePos = _sceneFromGlobal(event.position);
    setState(() {
      _lassoStart = scenePos;
      _lassoEnd = scenePos;
    });
  }

  void canvasHandleStylusMove(PointerMoveEvent event) {
    if (_lassoStart == null) return;
    final Offset scenePos = _sceneFromGlobal(event.position);
    setState(() => _lassoEnd = scenePos);
  }

  void canvasHandleStylusUp(PointerEvent event, {required bool wasTap}) {
    if (_lassoStart == null) return;
    final Offset start = _lassoStart!;
    final Offset end = _lassoEnd ?? start;
    setState(() {
      _lassoStart = null;
      _lassoEnd = null;
    });

    if (wasTap) {
      canvasShowHandwritingPopup(event.position, start);
    } else {
      canvasSelectInRect(Rect.fromPoints(start, end));
    }
  }

  void canvasResetStylusGesture() {
    if (_lassoStart == null) return;
    setState(() {
      _lassoStart = null;
      _lassoEnd = null;
    });
  }

  // ── Handwriting popup ────────────────────────────────────────────────────

  void canvasShowHandwritingPopup(Offset globalPosition, Offset scenePosition) {
    canvasDismissHandwritingPopup();

    final TextEditingController controller = TextEditingController();
    _handwritingController = controller;

    void submit(String text) {
      canvasDismissHandwritingPopup();
      canvasCreateNodeFromText(text, scenePosition);
    }

    // A pan or zoom while the field is open would leave it pointing at the
    // wrong place, so it closes instead of following.
    void dismissOnPan() => canvasDismissHandwritingPopup();
    _handwritingDismissOnPan = dismissOnPan;
    canvasTransform.addListener(dismissOnPan);

    _handwritingOverlay = OverlayEntry(
      builder: (BuildContext overlayContext) => CanvasHandwritingOverlay(
        position: globalPosition,
        controller: controller,
        onSubmitted: submit,
        onDismiss: canvasDismissHandwritingPopup,
        suggest: canvasSuggestNodeTypes,
      ),
    );
    Overlay.of(context).insert(_handwritingOverlay!);
  }

  void canvasDismissHandwritingPopup() {
    if (_handwritingDismissOnPan != null) {
      canvasTransform.removeListener(_handwritingDismissOnPan!);
      _handwritingDismissOnPan = null;
    }
    _handwritingOverlay?.remove();
    _handwritingOverlay = null;
    _handwritingController?.dispose();
    _handwritingController = null;
  }

  /// Hosts must call this from `dispose`.
  void canvasDisposeStylusLayer() => canvasDismissHandwritingPopup();
}
