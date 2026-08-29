import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:neuro_toolkit/features/neurocnl/widgets/canvas/canvas_minimap.dart';

void main() {
  group('computeSceneBounds', () {
    test('returns the union of all node rects', () {
      final bounds = computeSceneBounds(<Rect>[
        const Rect.fromLTWH(10, 20, 100, 50),
        const Rect.fromLTWH(-30, 5, 40, 40),
      ]);

      expect(bounds, const Rect.fromLTRB(-30, 5, 110, 70));
    });

    test('returns a single rect unchanged', () {
      final bounds = computeSceneBounds(<Rect>[
        const Rect.fromLTWH(0, 0, 150, 132),
      ]);

      expect(bounds, const Rect.fromLTWH(0, 0, 150, 132));
    });

    test('returns Rect.zero for an empty list', () {
      expect(computeSceneBounds(<Rect>[]), Rect.zero);
    });
  });

  group('MinimapProjection.fit', () {
    test('scales to fit the tighter axis and centers the other axis', () {
      final projection = MinimapProjection.fit(
        bounds: const Rect.fromLTWH(0, 0, 200, 100),
        widgetSize: const Size(180, 130),
      );

      // Width is the binding constraint: 164/200 = 0.82 < 114/100 = 1.14.
      final topLeft = projection.toLocal(Offset.zero);
      final bottomRight = projection.toLocal(const Offset(200, 100));

      expect(topLeft.dx, closeTo(8, 0.001));
      expect(bottomRight.dx, closeTo(172, 0.001));
      // Height axis has slack, so it's centered with equal margins.
      expect(topLeft.dy, closeTo(24, 0.001));
      expect(bottomRight.dy, closeTo(106, 0.001));
    });

    test('toScene inverts toLocal', () {
      final projection = MinimapProjection.fit(
        bounds: const Rect.fromLTWH(0, 0, 200, 100),
        widgetSize: const Size(180, 130),
      );

      const scenePoint = Offset(50, 30);
      final roundTripped = projection.toScene(projection.toLocal(scenePoint));

      expect(roundTripped.dx, closeTo(scenePoint.dx, 0.001));
      expect(roundTripped.dy, closeTo(scenePoint.dy, 0.001));
    });

    test('degenerate (zero-size) bounds map to the widget center', () {
      final projection = MinimapProjection.fit(
        bounds: Rect.zero,
        widgetSize: const Size(180, 130),
      );

      final local = projection.toLocal(Offset.zero);

      expect(local.dx, closeTo(90, 0.001));
      expect(local.dy, closeTo(65, 0.001));
    });
  });

  group('computeViewportRectInScene', () {
    test('identity transform maps directly to viewport size', () {
      final rect = computeViewportRectInScene(
        Matrix4.identity(),
        const Size(800, 600),
      );

      expect(rect, const Rect.fromLTWH(0, 0, 800, 600));
    });

    test('inverts pan and zoom to recover the visible scene rect', () {
      final transform = Matrix4.identity()
        ..translateByDouble(10, 20, 0, 1)
        ..scaleByDouble(2.0, 2.0, 1, 1);

      final rect = computeViewportRectInScene(transform, const Size(100, 50));

      expect(rect.left, closeTo(-5, 0.001));
      expect(rect.top, closeTo(-10, 0.001));
      expect(rect.right, closeTo(45, 0.001));
      expect(rect.bottom, closeTo(15, 0.001));
    });
  });

  group('CanvasMinimapWidget', () {
    testWidgets('tapping calls onJumpTo with the corresponding scene point', (
      WidgetTester tester,
    ) async {
      Offset? jumpedTo;
      final controller = TransformationController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: CanvasMinimapWidget(
                nodes: const <MinimapNode>[
                  MinimapNode(Rect.fromLTWH(0, 0, 150, 132), Color(0xFF9B71DF)),
                ],
                edgeLines: const <MinimapEdgeLine>[],
                transformationController: controller,
                viewportSize: const Size(800, 600),
                onJumpTo: (Offset scenePoint) => jumpedTo = scenePoint,
              ),
            ),
          ),
        ),
      );

      final topLeft = tester.getTopLeft(find.byType(CanvasMinimapWidget));
      // bounds = (0,0,150,132), widgetSize = (180,130), padding = 8:
      // available = (164,114); scale = min(164/150, 114/132) = 0.8636...
      // localOrigin = ((180-129.55)/2, (130-114)/2) = (25.23, 8) -- this is
      // exactly where bounds.topLeft (scene (0,0)) projects to.
      const localOrigin = Offset(25.227272727272727, 8.0);
      await tester.tapAt(topLeft + localOrigin);
      await tester.pumpAndSettle();

      expect(jumpedTo, isNotNull);
      expect(jumpedTo!.dx, closeTo(0, 0.5));
      expect(jumpedTo!.dy, closeTo(0, 0.5));
    });
  });
}
