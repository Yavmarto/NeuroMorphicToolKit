import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:neuro_toolkit/features/neurocnl/models/canvas/canvas.dart';
import 'package:neuro_toolkit/features/neurocnl/utils/force_directed_layout.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/brainviz_force_3d_painter.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/brainviz_force_3d_view.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/brainviz_perspective.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/network_2_5d_view.dart'
    show OrbitCamera;

CanvasGraph _sampleGraph() => neuronRasterGraph(<String, List<double>>{
  '0': <double>[10, 20],
  '1': <double>[12, 22],
  '2': <double>[100],
  '3': <double>[5],
});

void main() {
  test(
    'BrainvizForce3DPainter shouldRepaint skips unchanged visual inputs',
    () {
      final graph = _sampleGraph();
      final layout = CorrelationForceBrainvizLayout3D(graph);
      final projection = BrainvizPerspective(
        size: const Size(640, 480),
        camera: OrbitCamera.identity,
        sceneScale: layout.maxExtent(),
      );
      const activity = <String, double>{'0': 0.5, '1': 0.3};
      final radii = <String, double>{'0': 5.0, '1': 4.0};
      final pairs = <({String a, String b, double strength})>[];
      final labels = <String>{'0'};

      BrainvizForce3DPainter buildPainter({
        Map<String, double>? activityOverride,
        Map<String, double> pulse = const <String, double>{},
        bool drawWires = true,
        bool ringActivity = false,
      }) {
        return BrainvizForce3DPainter(
          graph: graph,
          positions: layout.positions,
          positionsRevision: layout.positionsRevision,
          projection: projection,
          activity: activityOverride ?? activity,
          pulse: pulse,
          drawWires: drawWires,
          ringActivity: ringActivity,
          radii: radii,
          correlationPairs: pairs,
          nodeClusterIndices: null,
          labelNodeIds: labels,
          selectedId: null,
          activityColorOf: (_) => Colors.red,
          labelStyle: const TextStyle(),
        );
      }

      final first = buildPainter();
      final second = buildPainter();
      expect(second.shouldRepaint(first), isFalse);

      final freshPositionsWrapper = buildPainter();
      expect(freshPositionsWrapper.shouldRepaint(first), isFalse);

      expect(
        buildPainter(
          activityOverride: const {'0': 0.9, '1': 0.3},
        ).shouldRepaint(first),
        isTrue,
      );

      // A changed activity pulse must trigger a repaint even when the
      // underlying activity is unchanged — that is what keeps active nodes
      // visibly breathing instead of freezing.
      expect(
        buildPainter(
          pulse: const <String, double>{'0': 1.25},
        ).shouldRepaint(first),
        isTrue,
      );

      // Variant switches (wires / rings) must also repaint.
      expect(buildPainter(drawWires: false).shouldRepaint(first), isTrue);
      expect(buildPainter(ringActivity: true).shouldRepaint(first), isTrue);
    },
  );

  test('brainvizGlowDensityScale attenuates with nearby active count', () {
    expect(brainvizGlowDensityScale(0), 1.0);
    expect(brainvizGlowDensityScale(10), lessThan(0.5));
    expect(brainvizGlowDensityScale(50), lessThan(0.25));
  });

  testWidgets('BrainvizForce3DView paints without throwing', (tester) async {
    final matrix = <String, Map<String, double>>{
      '0': {'1': 0.8, '2': 0.1},
      '1': {'0': 0.8, '2': 0.2},
      '2': {'0': 0.1, '1': 0.2, '3': 0.6},
      '3': {'2': 0.6},
    };

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 640,
            height: 480,
            child: BrainvizForce3DView(
              graph: _sampleGraph(),
              activity: const {'0': 0.9, '1': 0.4, '2': 0.1, '3': 0.0},
              correlationMatrix: matrix,
              animate: false,
            ),
          ),
        ),
      ),
    );

    expect(find.byType(BrainvizForce3DView), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'BrainvizForce3DView paints dense active cluster without throwing',
    (tester) async {
      final raster = <String, List<double>>{};
      final activity = <String, double>{};
      for (var i = 0; i < 120; i++) {
        final id = 'n$i';
        raster[id] = <double>[i % 20, (i * 3) % 20];
        activity[id] = 0.15 + (i % 7) * 0.1;
      }

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 640,
              height: 480,
              child: BrainvizForce3DView(
                graph: neuronRasterGraph(raster),
                activity: activity,
                animate: false,
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'BrainvizForce3DView tolerates fresh activity maps with same values',
    (tester) async {
      const activity = <String, double>{'0': 0.8, '1': 0.4, '2': 0.1, '3': 0.0};

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 640,
              height: 480,
              child: BrainvizForce3DView(
                graph: _sampleGraph(),
                activity: Map<String, double>.from(activity),
                animate: true,
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 640,
              height: 480,
              child: BrainvizForce3DView(
                graph: _sampleGraph(),
                activity: Map<String, double>.from(activity),
                animate: true,
              ),
            ),
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 16));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('BrainvizForce3DView paints correlation edges when matrix set', (
    tester,
  ) async {
    final matrix = <String, Map<String, double>>{
      '0': {'1': 0.9},
      '1': {'0': 0.9},
    };

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 640,
            height: 480,
            child: BrainvizForce3DView(
              graph: _sampleGraph(),
              activity: const {'0': 0.8, '1': 0.7, '2': 0.0, '3': 0.0},
              correlationMatrix: matrix,
              animate: false,
            ),
          ),
        ),
      ),
    );

    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
