// CEL-421 mobile modal audit — viewport checks for the remaining app screens.
//
// Pumps the audited dialog/sheet surfaces at the two required mobile widths
// (375x667 iPhone SE class, 390x844 iPhone 14) and fails on a RenderFlex
// overflow. Keyboard-inset cases set viewInsets.bottom to prove the surfaces
// stay clear of the software keyboard.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

import 'package:neuro_toolkit/features/neurobench/models/benchmark.dart';
import 'package:neuro_toolkit/features/neurobench/models/result.dart';
import 'package:neuro_toolkit/features/neurobench/providers/benchmarks_provider.dart';
import 'package:neuro_toolkit/features/neurobench/widgets/results_summary_card.dart';
import 'package:neuro_toolkit/features/server/connect/connect_notifier.dart';
import 'package:neuro_toolkit/features/server/provision/provision_notifier.dart';
import 'package:neuro_toolkit/models/module.dart';
import 'package:neuro_toolkit/models/workspace_session.dart';
import 'package:neuro_toolkit/providers/riverpod_providers.dart';
import 'package:neuro_toolkit/screens/server_access_dialog_surface.dart';
import 'package:neuro_toolkit/screens/server_access_popup.dart';
import 'package:neuro_toolkit/screens/server_access_sheet_surface.dart';
import 'package:neuro_toolkit/services/analytics_service.dart';
import 'package:neuro_toolkit/services/control_api_service.dart';
import 'package:neuro_toolkit/services/update_service.dart';
import 'package:neuro_toolkit/src/features/app/presentation/launcher_app_host.dart';
import 'package:neuro_toolkit/src/features/module/domain/module_state.dart';
import 'package:neuro_toolkit/src/features/module/presentation/module_notifier.dart';
import 'package:neuro_toolkit/src/features/workspace/domain/workspace_state.dart';
import 'package:neuro_toolkit/src/features/workspace/presentation/workspace_notifier.dart';

const Size _iphoneSe = Size(375, 667);
const Size _iphone14 = Size(390, 844);

Future<List<String>> _captureOverflows(Future<void> Function() body) async {
  final overflows = <String>[];
  final original = FlutterError.onError;
  FlutterError.onError = (FlutterErrorDetails details) {
    final message = details.exceptionAsString();
    if (message.contains('overflowed by')) {
      overflows.add(message);
      return;
    }
    original?.call(details);
  };
  try {
    await body();
  } finally {
    FlutterError.onError = original;
  }
  return overflows;
}

void _useViewport(WidgetTester tester, Size size, {double keyboard = 0}) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
  addTearDown(tester.view.reset);
}

Widget _serverFlowBody() {
  return Column(
    children: [
      Row(
        children: [
          ZetaButton.text(label: 'Back', onPressed: () {}),
          const Spacer(),
          ZetaIconButton.text(
            icon: ZetaIcons.close,
            semanticLabel: 'Close',
            onPressed: () {},
          ),
        ],
      ),
      Expanded(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              for (var i = 0; i < 30; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: ZetaTextInput(label: 'Field $i'),
                ),
            ],
          ),
        ),
      ),
    ],
  );
}

class _StubConnectNotifier extends ConnectNotifier {
  @override
  ConnectState build() => const ConnectState();

  @override
  Future<void> connect(ConnectRequest request) async {}
}

class _StubProvisionNotifier extends ProvisionNotifier {
  @override
  ProvisionState build() => const ProvisionState();

  @override
  Future<void> provision(ProvisionRequest request) async {}
}

class _FakeModuleNotifier extends ModuleNotifier {
  @override
  Future<ModuleState> build() async {
    return ModuleState(
      modules: <Module>[
        Module(
          id: 'neurocnl',
          name: 'NeuroStudio',
          description: 'CNL compiler and visual design suite',
          directory: 'neurocnl',
          hasFrontend: true,
          status: ModuleStatus.starting,
        ),
      ],
      pendingLauncherUpdate: LauncherUpdate(
        version: '9.9.9',
        url: 'https://example.com/releases/9.9.9',
        releaseNotes: List<String>.generate(
          40,
          (index) => '- Long release note line $index that must scroll.',
        ).join('\n'),
      ),
    );
  }
}

class _FakeWorkspaceNotifier extends WorkspaceNotifier {
  @override
  Future<WorkspaceState> build() async {
    return const WorkspaceState(
      sessions: <WorkspaceSession>[
        WorkspaceSession(
          moduleId: 'neurocnl',
          surfaceMode: 'embedded',
          readinessState: 'warming_up',
        ),
      ],
      focusedModuleId: 'neurocnl',
    );
  }

  @override
  Future<void> ensureDefaultSessionsOnce({
    required List<WorkspaceSession> sessions,
    required String? focusedModuleId,
  }) async {}

  @override
  Future<void> openSession(
    String moduleId, {
    required String surfaceMode,
    String? deepLink,
    Map<String, dynamic> restoreState = const <String, dynamic>{},
    String readinessState = 'opening',
  }) async {}

  @override
  Future<void> focusSession(String moduleId) async {}

  @override
  Future<void> updateSession(
    String moduleId, {
    String? deepLink,
    Map<String, dynamic>? restoreState,
    String? readinessState,
  }) async {}

  @override
  Future<void> closeSession(String moduleId) async {}
}

BenchmarkDefinition _benchmark() {
  return BenchmarkDefinition(
    id: 'bench-1',
    name: 'MNIST',
    description: 'Digit classification',
    taskType: 'classification',
    inputSpec: InputSpec(type: 'synthetic'),
    assertions: const <String>[],
    scoring: ScoringConfig(
      primaryMetric: 'accuracy',
      secondaryMetrics: const <String>['latency_ms'],
      higherIsBetter: true,
      passThreshold: 0.5,
    ),
    defaultParams: const <String, dynamic>{},
    builtin: true,
  );
}

BenchmarkResult _result() {
  return BenchmarkResult(
    id: 'result-1',
    benchmarkId: 'bench-1',
    networkSpecHash: 'hash',
    timestamp: '2026-01-01T00:00:00Z',
    params: const <String, dynamic>{},
    metrics: const <String, double>{'accuracy': 0.93, 'latency_ms': 1.2},
    wallTimeSeconds: 0.1,
    seed: 1,
  );
}

void main() {
  group('server access sheet surface', () {
    for (final size in <Size>[_iphoneSe, _iphone14]) {
      testWidgets('fits ${size.width.toInt()}x${size.height.toInt()}', (
        tester,
      ) async {
        _useViewport(tester, size);
        final overflows = await _captureOverflows(() async {
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: ServerAccessSheetSurface(child: _serverFlowBody()),
              ),
            ),
          );
          await tester.pump();
        });
        expect(overflows, isEmpty, reason: overflows.join('\n'));
      });
    }

    testWidgets('body clears the keyboard inset on iPhone 14', (tester) async {
      const keyboard = 300.0;
      _useViewport(tester, _iphone14, keyboard: keyboard);
      final overflows = await _captureOverflows(() async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ServerAccessSheetSurface(child: _serverFlowBody()),
            ),
          ),
        );
        await tester.pump();
      });
      expect(overflows, isEmpty, reason: overflows.join('\n'));

      final sheetBox = tester.getRect(
        find.descendant(
          of: find.byType(ServerAccessSheetSurface),
          matching: find.byType(ClipRRect),
        ),
      );
      expect(
        sheetBox.bottom,
        lessThanOrEqualTo(_iphone14.height - keyboard + 0.5),
        reason: 'sheet content must sit above the keyboard',
      );
    });
  });

  group('server access dialog surface', () {
    for (final size in <Size>[_iphoneSe, _iphone14, const Size(1024, 600)]) {
      testWidgets('fits ${size.width.toInt()}x${size.height.toInt()}', (
        tester,
      ) async {
        _useViewport(tester, size);
        final overflows = await _captureOverflows(() async {
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: ServerAccessDialogSurface(child: _serverFlowBody()),
              ),
            ),
          );
          await tester.pump();
        });
        expect(overflows, isEmpty, reason: overflows.join('\n'));
      });
    }
  });

  testWidgets('server access popup opens a sheet on a phone', (tester) async {
    _useViewport(tester, _iphoneSe);
    final overflows = await _captureOverflows(() async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            connectNotifierProvider.overrideWith(_StubConnectNotifier.new),
            provisionNotifierProvider.overrideWith(_StubProvisionNotifier.new),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => Center(
                  child: ZetaButton(
                    label: 'Open',
                    onPressed: () => showServerAccessPopup(context),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    });
    expect(find.byType(ServerAccessSheetSurface), findsOneWidget);
    expect(overflows, isEmpty, reason: overflows.join('\n'));
  });

  testWidgets('results summary guide dialog fits a phone', (tester) async {
    _useViewport(tester, _iphoneSe);
    final overflows = await _captureOverflows(() async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            activeBenchmarkProvider.overrideWithValue(_benchmark()),
            activeBenchmarkResultsProvider.overrideWith(
              (ref) async => <BenchmarkResult>[_result()],
            ),
          ],
          child: const MaterialApp(home: Scaffold(body: ResultsSummaryCard())),
        ),
      );
      await tester.pump();
      await tester.tap(find.byIcon(ZetaIcons.help_outline));
      await tester.pumpAndSettle();
    });
    expect(find.text('Result Interpretation Guide'), findsOneWidget);
    expect(overflows, isEmpty, reason: overflows.join('\n'));
  });

  for (final size in <Size>[_iphoneSe, _iphone14]) {
    testWidgets('launcher update dialog scrolls at ${size.width.toInt()}x'
        '${size.height.toInt()}', (tester) async {
      _useViewport(tester, size);
      final overflows = await _captureOverflows(() async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              analyticsServiceProvider.overrideWithValue(AnalyticsService()),
              selectedControlApiServiceProvider.overrideWithValue(
                ControlApiService(
                  baseUri: Uri.parse('http://localhost:9000'),
                  analyticsService: AnalyticsService(),
                ),
              ),
              moduleProvider.overrideWith(_FakeModuleNotifier.new),
              workspaceProvider.overrideWith(_FakeWorkspaceNotifier.new),
            ],
            child: const MaterialApp(home: LauncherAppHost()),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pump(const Duration(milliseconds: 400));
      });
      expect(find.text('Launcher Update Available'), findsOneWidget);
      expect(overflows, isEmpty, reason: overflows.join('\n'));
    });
  }
}
