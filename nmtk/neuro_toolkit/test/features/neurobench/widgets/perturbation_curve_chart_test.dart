import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:neuro_toolkit/features/neurobench/widgets/perturbation_curve_chart.dart';

void main() {
  testWidgets('PerturbationCurveChart shows no benchmark selected by default', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: Scaffold(body: PerturbationCurveChart())),
      ),
    );

    expect(find.text('Perturbation'), findsOneWidget);
    expect(
      find.text('Select a benchmark to view perturbation metrics.'),
      findsOneWidget,
    );
  });
}
