import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_toolkit/features/neurobench/models/result.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/deployment/deploy/voyager_workspace/studio_voyager_workspace.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/studio_voyager_deploy_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/services/studio_voyager_deploy_service.dart';

BenchmarkResult _sampleResult({
  Map<String, double> metrics = const {},
  Map<String, dynamic>? spikeData,
}) {
  return BenchmarkResult(
    id: 'res_voyager_test',
    benchmarkId: StudioVoyagerDeployService.benchmarkId,
    networkSpecHash: 'hash',
    timestamp: '2026-01-01T00:00:00Z',
    targetId: StudioVoyagerDeployService.targetId,
    params: const {},
    metrics: metrics,
    spikeData: spikeData,
    wallTimeSeconds: 1,
    seed: 0,
  );
}

void main() {
  testWidgets('Voyager workspace shows hardware-pending chip without metrics', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          studioVoyagerDeployProvider.overrideWith(
            () => _StaticVoyagerController(
              StudioVoyagerDeployState(
                phase: StudioVoyagerDeployPhase.hardwarePending,
                result: _sampleResult(
                  spikeData: const {'hardware_status': 'pending_hardware'},
                ),
                activityMessage:
                    'Compile finished; AIPU numbers need Metis hardware.',
              ),
            ),
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: StudioVoyagerWorkspace(isCompact: false),
          ),
        ),
      ),
    );

    expect(find.textContaining('Metis not available yet'), findsOneWidget);
    expect(find.textContaining('CPU latency'), findsNothing);
    expect(find.text('Open NeuroBench Compare'), findsOneWidget);
  });

  testWidgets('Voyager workspace shows returned metrics only', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          studioVoyagerDeployProvider.overrideWith(
            () => _StaticVoyagerController(
              StudioVoyagerDeployState(
                phase: StudioVoyagerDeployPhase.completed,
                result: _sampleResult(
                  metrics: const {'cpu_latency_ms': 120.5},
                ),
              ),
            ),
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: StudioVoyagerWorkspace(isCompact: false),
          ),
        ),
      ),
    );

    expect(find.textContaining('CPU latency (ms): 120.50'), findsOneWidget);
    expect(find.textContaining('AIPU latency (ms)'), findsNothing);
  });
}

class _StaticVoyagerController extends StudioVoyagerDeployController {
  _StaticVoyagerController(this._state);

  final StudioVoyagerDeployState _state;

  @override
  StudioVoyagerDeployState build() => _state;
}
