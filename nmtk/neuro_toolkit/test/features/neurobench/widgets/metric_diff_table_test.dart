import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_toolkit/features/neurobench/models/result.dart';
import 'package:neuro_toolkit/features/neurobench/providers/benchmarks_provider.dart';
import 'package:neuro_toolkit/features/neurobench/widgets/metric_diff_table.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

void useMobileViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

MetricDiff _metric(String name) {
  return MetricDiff(
    name: name,
    baselineValue: 0.8,
    currentValue: 0.9,
    delta: 0.1,
    deltaPct: 12.5,
    status: MetricStatus.improved,
    thresholdViolated: false,
    isSignificant: true,
    pValueTtest: 0.001,
  );
}

DiffResult _diff(List<MetricDiff> metrics) {
  return DiffResult(baselineId: 'base_1', currentId: 'run_1', metrics: metrics);
}

Future<void> _pump(WidgetTester tester, ProviderContainer container) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: Scaffold(body: MetricDiffTable())),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('null diff shows no comparison data message', (tester) async {
    useMobileViewport(tester);
    final container = ProviderContainer(
      overrides: [activeDiffProvider.overrideWith((ref) async => null)],
    );
    addTearDown(container.dispose);

    await _pump(tester, container);

    expect(find.text('No comparison data available'), findsOneWidget);
    expect(find.byType(NmtkSurfaceCard), findsNothing);
  });

  testWidgets('card list renders one keyed card per metric', (tester) async {
    useMobileViewport(tester);
    final container = ProviderContainer(
      overrides: [
        activeDiffProvider.overrideWith(
          (ref) async => _diff([_metric('accuracy'), _metric('latency_ms')]),
        ),
      ],
    );
    addTearDown(container.dispose);

    await _pump(tester, container);

    expect(find.byKey(const ValueKey('accuracy')), findsOneWidget);
    expect(find.byKey(const ValueKey('latency_ms')), findsOneWidget);
    expect(find.byType(NmtkSurfaceCard), findsNWidgets(2));
  });

  testWidgets('card list preserves metric order from diff', (tester) async {
    useMobileViewport(tester);
    final container = ProviderContainer(
      overrides: [
        activeDiffProvider.overrideWith(
          (ref) async => _diff([
            _metric('accuracy'),
            _metric('latency_ms'),
            _metric('energy_pj'),
          ]),
        ),
      ],
    );
    addTearDown(container.dispose);

    await _pump(tester, container);

    final accuracyY = tester
        .getTopLeft(find.byKey(const ValueKey('accuracy')))
        .dy;
    final latencyY = tester
        .getTopLeft(find.byKey(const ValueKey('latency_ms')))
        .dy;
    final energyY = tester
        .getTopLeft(find.byKey(const ValueKey('energy_pj')))
        .dy;
    expect(accuracyY, lessThan(latencyY));
    expect(latencyY, lessThan(energyY));
  });

  testWidgets('card list updates when diff refresh adds a metric', (
    tester,
  ) async {
    useMobileViewport(tester);
    final diffStateProvider = StateProvider<DiffResult?>(
      (ref) => _diff([_metric('accuracy')]),
    );
    final container = ProviderContainer(
      overrides: [
        activeDiffProvider.overrideWith(
          (ref) async => ref.watch(diffStateProvider),
        ),
      ],
    );
    addTearDown(container.dispose);

    await _pump(tester, container);
    expect(find.byKey(const ValueKey('accuracy')), findsOneWidget);
    expect(find.byKey(const ValueKey('latency_ms')), findsNothing);

    container.read(diffStateProvider.notifier).state = _diff([
      _metric('accuracy'),
      _metric('latency_ms'),
    ]);
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const ValueKey('latency_ms')), findsOneWidget);
    expect(find.byType(NmtkSurfaceCard), findsNWidgets(2));
  });
}
