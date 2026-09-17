import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_toolkit/features/neurobench/models/benchmark.dart';
import 'package:neuro_toolkit/features/neurobench/models/result.dart';
import 'package:neuro_toolkit/features/neurobench/models/workbench_tab.dart';
import 'package:neuro_toolkit/features/neurobench/providers/benchmarks_provider.dart';
import 'package:neuro_toolkit/features/neurobench/widgets/benchmark_results_table.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

void useMobileViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

BenchmarkResult _result(String id, String timestamp) {
  return BenchmarkResult(
    id: id,
    benchmarkId: 'bench-1',
    networkSpecHash: 'hash-1',
    timestamp: timestamp,
    params: const <String, dynamic>{},
    metrics: const <String, double>{'accuracy': 0.9},
    wallTimeSeconds: 1.2,
    seed: 1,
  );
}

Future<void> _pump(WidgetTester tester, ProviderContainer container) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        home: Scaffold(
          body: BenchmarkResultsTable(onNavigateTab: _noopNavigate),
        ),
      ),
    ),
  );
  await tester.pump();
}

void _noopNavigate(NeurobenchWorkbenchTab tab) {}

void main() {
  testWidgets('empty state shows no past runs message', (tester) async {
    useMobileViewport(tester);
    final container = ProviderContainer(
      overrides: [
        benchmarksProvider.overrideWith((ref) async => <BenchmarkDefinition>[]),
        activeBenchmarkResultsProvider.overrideWith((ref) async => []),
      ],
    );
    addTearDown(container.dispose);

    await _pump(tester, container);

    expect(find.text('No past runs for this benchmark.'), findsOneWidget);
    expect(find.byType(NmtkSurfaceCard), findsNothing);
  });

  testWidgets('card list renders one keyed card per result', (tester) async {
    useMobileViewport(tester);
    final container = ProviderContainer(
      overrides: [
        benchmarksProvider.overrideWith((ref) async => <BenchmarkDefinition>[]),
        activeBenchmarkResultsProvider.overrideWith(
          (ref) async => [
            _result('run_1', '2026-04-24T10:00:00Z'),
            _result('run_2', '2026-04-25T10:00:00Z'),
          ],
        ),
      ],
    );
    addTearDown(container.dispose);

    await _pump(tester, container);

    expect(find.byKey(const ValueKey('run_1')), findsOneWidget);
    expect(find.byKey(const ValueKey('run_2')), findsOneWidget);
    expect(find.byType(NmtkSurfaceCard), findsNWidgets(2));
  });

  testWidgets('card list shows newest run first', (tester) async {
    useMobileViewport(tester);
    final container = ProviderContainer(
      overrides: [
        benchmarksProvider.overrideWith((ref) async => <BenchmarkDefinition>[]),
        activeBenchmarkResultsProvider.overrideWith(
          (ref) async => [
            _result('older', '2026-04-23T10:00:00Z'),
            _result('newer', '2026-04-24T10:00:00Z'),
          ],
        ),
      ],
    );
    addTearDown(container.dispose);

    await _pump(tester, container);

    final newerY = tester.getTopLeft(find.byKey(const ValueKey('newer'))).dy;
    final olderY = tester.getTopLeft(find.byKey(const ValueKey('older'))).dy;
    expect(newerY, lessThan(olderY));
  });

  testWidgets('card list updates when results refresh', (tester) async {
    useMobileViewport(tester);
    final resultsStateProvider = StateProvider<List<BenchmarkResult>>(
      (ref) => [_result('run_1', '2026-04-24T10:00:00Z')],
    );
    final container = ProviderContainer(
      overrides: [
        benchmarksProvider.overrideWith((ref) async => <BenchmarkDefinition>[]),
        activeBenchmarkResultsProvider.overrideWith(
          (ref) async => ref.watch(resultsStateProvider),
        ),
      ],
    );
    addTearDown(container.dispose);

    await _pump(tester, container);
    expect(find.byKey(const ValueKey('run_1')), findsOneWidget);
    expect(find.byKey(const ValueKey('run_2')), findsNothing);

    container.read(resultsStateProvider.notifier).state = [
      _result('run_1', '2026-04-24T10:00:00Z'),
      _result('run_2', '2026-04-25T10:00:00Z'),
    ];
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const ValueKey('run_2')), findsOneWidget);
    expect(find.byType(NmtkSurfaceCard), findsNWidgets(2));
  });
}
