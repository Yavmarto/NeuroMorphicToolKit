import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:neuro_toolkit/features/neurobench/widgets/robustness_curve_chart.dart';

void main() {
  testWidgets('RobustnessCurveChart shows no benchmark selected by default', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: Scaffold(body: RobustnessCurveChart())),
      ),
    );

    expect(find.text('Robustness'), findsOneWidget);
    expect(
      find.text('Select a benchmark to view robustness metrics.'),
      findsOneWidget,
    );
  });
}
