import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:neuro_toolkit/features/neurocnl/models/canvas/canvas.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/brainviz_force_3d_view.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/brainviz_variants.dart';

CanvasGraph _graph(List<String> ids) => CanvasGraph(
  nodes: <CanvasNode>[
    for (final id in ids)
      CanvasNode(
        id: id,
        componentId: 'lif_population',
        label: id,
        parameters: const <String, dynamic>{},
        position: const <double>[0, 0],
      ),
  ],
  edges: const <CanvasEdge>[],
  metadata: const <String, dynamic>{},
);

void main() {
  test('every variant has a non-empty label and caption', () {
    final labels = <String>{};
    for (final variant in BrainvizVariant.values) {
      expect(variant.label.trim(), isNotEmpty);
      expect(variant.caption.trim(), isNotEmpty);
      labels.add(variant.label);
    }
    expect(labels.length, BrainvizVariant.values.length);
  });

  testWidgets('buildBrainvizVariant maps each variant to its renderer', (
    tester,
  ) async {
    final graph = _graph(const ['a', 'b']);
    final activity = const <String, double>{'a': 0.9, 'b': 0.2};
    final matrix = <String, Map<String, double>>{
      'a': {'b': 0.7},
      'b': {'a': 0.7},
    };

    Widget wrap(BrainvizVariant variant) => MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 400,
          height: 300,
          child: buildBrainvizVariant(
            variant: variant,
            graph: graph,
            activity: activity,
            matrix: matrix,
          ),
        ),
      ),
    );

    for (final variant in BrainvizVariant.values) {
      await tester.pumpWidget(wrap(variant));
      if (variant.isMatrix) {
        expect(
          find.byType(BrainvizMatrixView),
          findsOneWidget,
          reason: '${variant.name} should use the matrix view',
        );
      } else {
        expect(
          find.byType(BrainvizForce3DView),
          findsOneWidget,
          reason: '${variant.name} should use the 3D view',
        );
      }
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('matrix view asks for more data with fewer than two neurons', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 300,
            child: BrainvizMatrixView(
              matrix: <String, Map<String, double>>{},
              activity: <String, double>{'a': 0.5},
            ),
          ),
        ),
      ),
    );

    expect(find.text('Not enough co-firing yet.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('comparison grid builds a card per variant', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BrainvizVariantsView(
            graph: _graph(const ['a', 'b']),
            activity: const <String, double>{'a': 0.9, 'b': 0.2},
            matrix: const <String, Map<String, double>>{
              'a': <String, double>{'b': 0.7},
              'b': <String, double>{'a': 0.7},
            },
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(BrainvizMatrixView), findsOneWidget);
    expect(
      find.byType(BrainvizForce3DView),
      findsNWidgets(BrainvizVariant.values.length - 1),
    );
    expect(find.text('Activity'), findsOneWidget);
    expect(find.text('Co-firing grid'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
