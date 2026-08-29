import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_toolkit/features/neurobench/models/benchmark_job.dart';
import 'package:neuro_toolkit/features/neurobench/providers/execution_provider.dart';
import 'package:neuro_toolkit/features/neurobench/widgets/active_jobs_bar.dart';

class MockBenchmarkExecutionController extends BenchmarkExecutionController {
  @override
  BenchmarkExecutionState build() {
    return const BenchmarkExecutionState(
      activeJob: BenchmarkJob(
        id: 'job_551f1226',
        benchmarkId: 'bench-1',
        status: BenchmarkJobStatus.running,
        networkPath: 'examples/net.json',
        createdAt: '2026-01-01T00:00:00Z',
        updatedAt: '2026-01-01T00:00:01Z',
      ),
    );
  }
}

void main() {
  testWidgets(
    'ActiveJobsBar renders active job and responds to cancel',
    skip: true,
    (WidgetTester tester) async {
      final container = ProviderContainer(
        overrides: [
          benchmarkExecutionProvider.overrideWith(
            MockBenchmarkExecutionController.new,
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(bottomNavigationBar: ActiveJobsBar()),
          ),
        ),
      );
      await tester.pump();

      expect(find.textContaining('job_551f1226'), findsOneWidget);
      expect(find.text('Running'), findsOneWidget);
    },
  );

  testWidgets('ActiveJobsBar hidden when no job', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: Scaffold(bottomNavigationBar: ActiveJobsBar()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Background run'), findsNothing);
  });
}
