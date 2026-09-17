import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_toolkit/features/neurobench/models/benchmark.dart';
import 'package:neuro_toolkit/features/neurobench/models/result.dart';
import 'package:neuro_toolkit/features/neurobench/providers/benchmarks_provider.dart';
import 'package:neuro_toolkit/features/neurobench/providers/results_provider.dart';
import 'package:neuro_toolkit/features/neurobench/widgets/report_builder.dart';

class MockActiveBenchmarkId extends ActiveBenchmarkId {
  @override
  String? build() => 'test_bench';
}

void main() {
  testWidgets(
    'ReportBuilder shows title field and generate button',
    skip: true,
    (WidgetTester tester) async {
      final container = ProviderContainer(
        overrides: [
          benchmarksProvider.overrideWith(
            (ref) async => <BenchmarkDefinition>[
              BenchmarkDefinition(
                id: 'test_bench',
                name: 'Test benchmark',
                description: 'Benchmark for report builder tests',
                taskType: 'classification',
                builtin: true,
                assertions: const <String>[],
                inputSpec: InputSpec(type: 'synthetic'),
                scoring: ScoringConfig(
                  primaryMetric: 'accuracy',
                  secondaryMetrics: const <String>[],
                  higherIsBetter: true,
                  passThreshold: 0.8,
                ),
                defaultParams: const <String, dynamic>{},
              ),
            ],
          ),
          activeBenchmarkIdProvider.overrideWith(MockActiveBenchmarkId.new),
          resultsProvider.overrideWith(
            (ref) async => const <BenchmarkResult>[],
          ),
          baselinesProvider.overrideWith(
            (ref) async => const <BenchmarkResult>[],
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(body: SingleChildScrollView(child: ReportBuilder())),
          ),
        ),
      );

      expect(find.text('Report Workbench'), findsOneWidget);
      expect(find.text('Report Title'), findsOneWidget);
      expect(find.text('Generate Report'), findsOneWidget);
    },
  );
}
