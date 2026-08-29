import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/canvas/stylus_canvas_recognizer.dart';

/// Wraps a [child] (typically an [InteractiveViewer]) with a
/// [RawGestureDetector] combining an ordinary tap recognizer (standing in for
/// the existing `onTapDown` select/deselect logic) with [StylusCanvasRecognizer],
/// mirroring the real integration in `network_canvas.dart`.
Widget _harness({
  required Widget child,
  required bool Function(Offset) hitTestEmptyCanvas,
  void Function(PointerDownEvent)? onDown,
  void Function(PointerMoveEvent)? onMove,
  void Function(PointerEvent, {required bool wasTap})? onUp,
}) {
  return MaterialApp(
    home: Scaffold(
      body: SizedBox(
        width: 400,
        height: 400,
        child: RawGestureDetector(
          gestures: <Type, GestureRecognizerFactory>{
            TapGestureRecognizer:
                GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
                  () => TapGestureRecognizer(),
                  (TapGestureRecognizer instance) {},
                ),
            StylusCanvasRecognizer:
                GestureRecognizerFactoryWithHandlers<StylusCanvasRecognizer>(
                  () => StylusCanvasRecognizer(
                    hitTestEmptyCanvas: hitTestEmptyCanvas,
                    onDown: onDown ?? (_) {},
                    onMove: onMove ?? (_) {},
                    onUp: onUp ?? (_, {required bool wasTap}) {},
                  ),
                  (StylusCanvasRecognizer instance) {},
                ),
          },
          child: child,
        ),
      ),
    ),
  );
}

void main() {
  group('StylusCanvasRecognizer device-kind gating', () {
    testWidgets('claims stylus pointers over empty canvas', (tester) async {
      int downCalls = 0;
      await tester.pumpWidget(
        _harness(
          child: Container(color: Colors.white),
          hitTestEmptyCanvas: (_) => true,
          onDown: (_) => downCalls++,
        ),
      );

      final TestGesture gesture = await tester.startGesture(
        const Offset(200, 200),
        kind: PointerDeviceKind.stylus,
      );
      await tester.pump();
      await gesture.up();

      expect(downCalls, 1);
    });

    testWidgets('ignores touch pointers entirely', (tester) async {
      int downCalls = 0;
      await tester.pumpWidget(
        _harness(
          child: Container(color: Colors.white),
          hitTestEmptyCanvas: (_) => true,
          onDown: (_) => downCalls++,
        ),
      );

      final TestGesture gesture = await tester.startGesture(
        const Offset(200, 200),
        kind: PointerDeviceKind.touch,
      );
      await tester.pump();
      await gesture.up();

      expect(downCalls, 0);
    });

    testWidgets('ignores mouse pointers entirely', (tester) async {
      int downCalls = 0;
      await tester.pumpWidget(
        _harness(
          child: Container(color: Colors.white),
          hitTestEmptyCanvas: (_) => true,
          onDown: (_) => downCalls++,
        ),
      );

      final TestGesture gesture = await tester.startGesture(
        const Offset(200, 200),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      await gesture.up();

      expect(downCalls, 0);
    });

    testWidgets('claims inverted-stylus (eraser tip) pointers', (tester) async {
      int downCalls = 0;
      await tester.pumpWidget(
        _harness(
          child: Container(color: Colors.white),
          hitTestEmptyCanvas: (_) => true,
          onDown: (_) => downCalls++,
        ),
      );

      final TestGesture gesture = await tester.startGesture(
        const Offset(200, 200),
        kind: PointerDeviceKind.invertedStylus,
      );
      await tester.pump();
      await gesture.up();

      expect(downCalls, 1);
    });
  });

  group('StylusCanvasRecognizer spatial gating', () {
    testWidgets('declines a stylus pointer when not over empty canvas', (
      tester,
    ) async {
      int downCalls = 0;
      await tester.pumpWidget(
        _harness(
          child: Container(color: Colors.white),
          hitTestEmptyCanvas: (_) => false, // e.g. landed on a node/port
          onDown: (_) => downCalls++,
        ),
      );

      final TestGesture gesture = await tester.startGesture(
        const Offset(200, 200),
        kind: PointerDeviceKind.stylus,
      );
      await tester.pump();
      await gesture.up();

      expect(downCalls, 0);
    });
  });

  group('StylusCanvasRecognizer tap-vs-drag classification', () {
    testWidgets('a short stylus tap resolves wasTap: true', (tester) async {
      bool? lastWasTap;
      await tester.pumpWidget(
        _harness(
          child: Container(color: Colors.white),
          hitTestEmptyCanvas: (_) => true,
          onUp: (_, {required bool wasTap}) => lastWasTap = wasTap,
        ),
      );

      final TestGesture gesture = await tester.startGesture(
        const Offset(200, 200),
        kind: PointerDeviceKind.stylus,
      );
      await tester.pump();
      await gesture.up();

      expect(lastWasTap, isTrue);
    });

    testWidgets('a long stylus drag resolves wasTap: false', (tester) async {
      bool? lastWasTap;
      await tester.pumpWidget(
        _harness(
          child: Container(color: Colors.white),
          hitTestEmptyCanvas: (_) => true,
          onUp: (_, {required bool wasTap}) => lastWasTap = wasTap,
        ),
      );

      final TestGesture gesture = await tester.startGesture(
        const Offset(100, 100),
        kind: PointerDeviceKind.stylus,
      );
      await tester.pump();
      await gesture.moveBy(const Offset(80, 80));
      await tester.pump();
      await gesture.up();

      expect(lastWasTap, isFalse);
    });
  });

  group('StylusCanvasRecognizer pre-empts InteractiveViewer pan', () {
    testWidgets(
      'a stylus drag over empty canvas does not pan InteractiveViewer, '
      'while an identical touch drag still does (regression guard)',
      (tester) async {
        Future<Matrix4> panWith(PointerDeviceKind kind) async {
          final TransformationController controller =
              TransformationController();
          await tester.pumpWidget(
            _harness(
              hitTestEmptyCanvas: (_) => true,
              child: InteractiveViewer(
                constrained: false,
                transformationController: controller,
                boundaryMargin: const EdgeInsets.all(1000),
                child: const SizedBox(width: 2000, height: 2000),
              ),
            ),
          );

          final TestGesture gesture = await tester.startGesture(
            const Offset(150, 150),
            kind: kind,
          );
          await tester.pump();
          await gesture.moveBy(const Offset(80, 80));
          await tester.pump();
          await gesture.up();
          await tester.pump();

          return controller.value;
        }

        final Matrix4 afterStylusDrag = await panWith(PointerDeviceKind.stylus);
        expect(afterStylusDrag, Matrix4.identity());

        final Matrix4 afterTouchDrag = await panWith(PointerDeviceKind.touch);
        expect(afterTouchDrag, isNot(Matrix4.identity()));
      },
    );
  });
}
