import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:neuro_toolkit/features/neurocnl/models/canvas/canvas.dart';
import 'package:neuro_toolkit/features/neurocnl/utils/force_directed_layout.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/brainviz_force_3d_view.dart';

CanvasGraph _sampleGraph() => neuronRasterGraph(<String, List<double>>{
  '0': <double>[10, 20],
  '1': <double>[12, 22],
  '2': <double>[100],
  '3': <double>[5],
});

void main() {
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

  testWidgets('BrainvizForce3DView paints dense active cluster without throwing', (
    tester,
  ) async {
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
  });

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
