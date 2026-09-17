import 'package:flutter/gestures.dart';

/// Gesture-arena participant that eagerly claims stylus (and inverted-stylus,
/// i.e. eraser-tip) pointers landing on empty canvas, so that
/// `InteractiveViewer`'s own pan/scale recognizer never gets a chance to claim
/// them. Declines pointers over nodes/ports via [hitTestEmptyCanvas], so the
/// pre-existing node-drag and port-drag `GestureDetector`s keep winning the
/// arena there, unchanged, for any pointer kind.
///
/// Resolving [GestureDisposition.accepted] synchronously inside
/// [addAllowedPointer] -- on frame 0 of the down event, mirroring Flutter's
/// own `EagerGestureRecognizer` -- is what makes the win deterministic
/// instead of racing `InteractiveViewer`'s recognizer on movement/slop.
class StylusCanvasRecognizer extends OneSequenceGestureRecognizer {
  StylusCanvasRecognizer({
    required this.hitTestEmptyCanvas,
    required this.onDown,
    required this.onMove,
    required this.onUp,
    this.onCancel,
    super.debugOwner,
  }) {
    supportedDevices = const <PointerDeviceKind>{
      PointerDeviceKind.stylus,
      PointerDeviceKind.invertedStylus,
    };
  }

  /// Returns true when [globalPosition] is over empty canvas (no node, no
  /// port) -- the only region this recognizer is allowed to claim.
  final bool Function(Offset globalPosition) hitTestEmptyCanvas;

  final void Function(PointerDownEvent event) onDown;
  final void Function(PointerMoveEvent event) onMove;
  final void Function(PointerEvent event, {required bool wasTap}) onUp;
  final void Function()? onCancel;

  Offset? _downPosition;

  @override
  bool isPointerAllowed(PointerDownEvent event) {
    return super.isPointerAllowed(event) && hitTestEmptyCanvas(event.position);
  }

  @override
  void addAllowedPointer(PointerDownEvent event) {
    super.addAllowedPointer(event);
    _downPosition = event.position;
    resolve(GestureDisposition.accepted);
    onDown(event);
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event is PointerMoveEvent) {
      onMove(event);
      return;
    }
    if (event is PointerUpEvent) {
      final Offset start = _downPosition ?? event.position;
      final bool wasTap = (event.position - start).distance < kPanSlop;
      onUp(event, wasTap: wasTap);
      _downPosition = null;
      stopTrackingPointer(event.pointer);
      return;
    }
    if (event is PointerCancelEvent) {
      _downPosition = null;
      onCancel?.call();
      stopTrackingPointer(event.pointer);
    }
  }

  @override
  void didStopTrackingLastPointer(int pointer) {
    _downPosition = null;
  }

  @override
  String get debugDescription => 'stylusCanvasRecognizer';
}
