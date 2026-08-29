import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_toolkit/features/neurobench/models/benchmark.dart';
import 'package:neuro_toolkit/features/neurobench/widgets/benchmark_run_form.dart';

void main() {
  BenchmarkDefinition buildBenchmark() {
    return BenchmarkDefinition(
      id: 'bench-1',
      name: 'Latency Bench',
      description: 'Test benchmark',
      taskType: 'classification',
      builtin: true,
      assertions: <String>[],
      inputSpec: InputSpec(type: 'synthetic'),
      scoring: ScoringConfig(
        primaryMetric: 'accuracy',
        secondaryMetrics: <String>[],
        higherIsBetter: true,
        passThreshold: 0.8,
      ),
      defaultParams: <String, dynamic>{},
    );
  }

  testWidgets('Target dropdown renders without layout overflow', skip: true, (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: BenchmarkRunForm(benchmark: buildBenchmark()),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Target'), findsOneWidget);
    expect(find.text('Run Benchmark'), findsOneWidget);
  });
}
