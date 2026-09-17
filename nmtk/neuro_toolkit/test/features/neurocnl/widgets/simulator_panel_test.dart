import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart' show ZetaIcons;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:neuro_toolkit/features/neurocnl/models/simulator.dart';
import 'package:neuro_toolkit/features/neurocnl/models/trained_nir_artifact.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/simulator_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/spec_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/services/server_config_service.dart';
import 'package:neuro_toolkit/features/neurocnl/services/simulator_service.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/simulator_panel.dart';

// ---------------------------------------------------------------------------
// Fake service implementations
// ---------------------------------------------------------------------------

/// A [SimulatorService] that immediately returns fixed capabilities.
class _FakeSimulatorService extends SimulatorService {
  final List<SimulatorCapability> caps;
  final SimulatorRunResult? runResult;
  final SimulatorApiException? runError;
  final List<SimulatorRunRequest> requests = [];

  _FakeSimulatorService({required this.caps, this.runResult, this.runError})
    : super(baseUrl: 'http://fake', apiKey: '');

  @override
  Future<List<SimulatorCapability>> getCapabilities() async {
    return caps;
  }

  @override
  Future<SimulatorRunResult> run(SimulatorRunRequest request) async {
    requests.add(request);
    if (runError != null) throw runError!;
    return runResult!;
  }
}

/// A [SimulatorService] whose [getCapabilities] throws.
class _ErrorSimulatorService extends SimulatorService {
  _ErrorSimulatorService() : super(baseUrl: 'http://fake', apiKey: '');

  @override
  Future<List<SimulatorCapability>> getCapabilities() async {
    await Future<void>.delayed(Duration.zero);
    throw Exception('Network error');
  }

  @override
  Future<SimulatorRunResult> run(SimulatorRunRequest request) async {
    throw const SimulatorApiException(503, '{}');
  }
}

// ---------------------------------------------------------------------------
// Test helpers
// ---------------------------------------------------------------------------

SimulatorCapability _ready(String backendName, String displayName) =>
    SimulatorCapability(
      backendName: backendName,
      displayName: displayName,
      available: true,
      supportedNirNodes: const ['Input', 'Output', 'LIF', 'Linear'],
    );

SimulatorCapability _unavailable(String backendName, String displayName) =>
    SimulatorCapability(
      backendName: backendName,
      displayName: displayName,
      available: false,
      unavailableReason: 'Package not installed.',
      requiresOptionalDependency: 'lava-nc',
    );

SimulatorRunResult _preflight() => const SimulatorRunResult(
  backendName: 'lava_sim',
  status: SimulatorStatus.completed,
  supportLevel: SupportLevel.exact,
  timesteps: 100,
  durationSeconds: 0.02,
  nirSummary: SimulatorNIRSummary(nodeCount: 4, edgeCount: 3),
  metadata: {'seed': 1, 'runtime_mode': 'preflight'},
);

/// A run that completed but recorded nothing, with the backend's own reason.
SimulatorRunResult _silentRunWithWarning() => const SimulatorRunResult(
  backendName: 'snntorch_sim',
  status: SimulatorStatus.completed,
  supportLevel: SupportLevel.exact,
  timesteps: 50,
  durationSeconds: 0.004,
  spikes: {'pop1': {}},
  warnings: [
    'Every weight in this network is 0.0, so no neuron can reach threshold '
        'and nothing will fire.',
  ],
  nirSummary: SimulatorNIRSummary(nodeCount: 3, edgeCount: 2),
);

SimulatorRunResult _resultWithSpikesAndVoltages() => const SimulatorRunResult(
  backendName: 'snntorch_sim',
  status: SimulatorStatus.completed,
  supportLevel: SupportLevel.exact,
  timesteps: 50,
  durationSeconds: 0.04,
  spikes: {
    'pop1': {
      '0': [5, 15, 25],
      '1': [10, 20, 30],
    },
  },
  voltages: {
    'pop1': {
      '0': [-65.0, -60.0, -55.0, -50.0, -48.0],
      '1': [-66.0, -62.0, -58.0, -54.0, -50.0],
    },
  },
  nirSummary: SimulatorNIRSummary(nodeCount: 3, edgeCount: 2),
);

/// The spec text override used in run-triggering tests.
const _testSpec =
    'The network MUST contain an excitatory input population of 2 neurons';

class _TestSpecTextController extends SpecTextController {
  _TestSpecTextController(this._initialSpec);
  final String _initialSpec;

  @override
  String build() => _initialSpec;

  @override
  Future<void> set(String text) async {
    state = text;
  }
}

/// Stands in for the workspace's trained `.nir` file.
///
/// Run is gated on this: the CNL spec compiles to shape-only tensors, so without
/// a trained graph the run could only ever produce an empty raster. Tests that
/// exercise a run therefore need one, and the default supplies it.
const TrainedNirArtifact _trainedNir = TrainedNirArtifact(
  filename: 'model.nir',
  nirBase64: 'dHJhaW5lZA==',
  sha256: 'abc123',
);

Widget _wrap(
  Widget child, {
  List<Override> overrides = const [],
  bool withSpec = false,
  TrainedNirArtifact? trainedNir = _trainedNir,
}) {
  return ProviderScope(
    overrides: [
      if (withSpec)
        specTextProvider.overrideWith(() => _TestSpecTextController(_testSpec)),
      simulatorTrainedNirProvider.overrideWith((ref, _) async => trainedNir),
      ...overrides,
    ],
    child: MaterialApp(home: Scaffold(body: child)),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await ServerConfigService.initialize();
  });

  setUp(() {
    final TestWidgetsFlutterBinding binding =
        TestWidgetsFlutterBinding.ensureInitialized();
    // ignore: deprecated_member_use
    binding.window.physicalSizeTestValue = const Size(1024, 1024);
    // ignore: deprecated_member_use
    binding.window.devicePixelRatioTestValue = 1.0;
  });

  tearDown(() {
    final TestWidgetsFlutterBinding binding =
        TestWidgetsFlutterBinding.ensureInitialized();
    // ignore: deprecated_member_use
    binding.window.clearPhysicalSizeTestValue();
    // ignore: deprecated_member_use
    binding.window.clearDevicePixelRatioTestValue();
  });

  group('SimulatorPanel — capabilities loading', () {
    testWidgets('renders backend selector when capabilities load', (
      tester,
    ) async {
      final service = _FakeSimulatorService(
        caps: [
          _ready('lava_sim', 'Lava simulator'),
          _ready('snntorch_sim', 'snnTorch simulator'),
        ],
      );

      await tester.pumpWidget(
        _wrap(
          const SimulatorPanel(),
          overrides: [simulatorServiceProvider.overrideWithValue(service)],
        ),
      );
      // Allow async build() to complete
      await tester.pump();
      await tester.pump();

      expect(find.text('Lava simulator'), findsOneWidget);
    });

    testWidgets('resolves to backend selector after capabilities load', (
      tester,
    ) async {
      final service = _FakeSimulatorService(
        caps: [
          _ready('lava_sim', 'Lava simulator'),
          _ready('snntorch_sim', 'snnTorch simulator'),
        ],
      );

      await tester.pumpWidget(
        _wrap(
          const SimulatorPanel(),
          overrides: [simulatorServiceProvider.overrideWithValue(service)],
        ),
      );
      await tester.pumpAndSettle();

      // Both backend names are visible in the dropdown and the panel rendered without error.
      expect(find.text('Lava simulator'), findsOneWidget);
      expect(find.text('Run Simulation'), findsOneWidget);
    });

    testWidgets('shows error message when capabilities fail', (tester) async {
      final service = _ErrorSimulatorService();

      await tester.pumpWidget(
        _wrap(
          const SimulatorPanel(),
          overrides: [simulatorServiceProvider.overrideWithValue(service)],
        ),
      );
      // Wait for async initialization
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        find.textContaining('Could not load capabilities'),
        findsOneWidget,
      );
    });
  });

  group('SimulatorPanel — missing dependency state', () {
    testWidgets('shows install chip when backend is unavailable', (
      tester,
    ) async {
      final service = _FakeSimulatorService(
        caps: [
          _unavailable('lava_sim', 'Lava simulator'),
          _ready('snntorch_sim', 'snnTorch simulator'),
        ],
      );

      await tester.pumpWidget(
        _wrap(
          const SimulatorPanel(),
          overrides: [simulatorServiceProvider.overrideWithValue(service)],
        ),
      );
      await tester.pump();
      await tester.pump();

      // The install chip is visible and non-destructive
      expect(find.textContaining('Install'), findsOneWidget);
      // Run button still visible — panel is not broken
      expect(find.text('Run Simulation'), findsOneWidget);
    });
  });

  group('SimulatorPanel — idle state', () {
    testWidgets('shows empty placeholder before any run', (tester) async {
      final service = _FakeSimulatorService(
        caps: [
          _ready('lava_sim', 'Lava simulator'),
          _ready('snntorch_sim', 'snnTorch simulator'),
        ],
        runResult: _preflight(),
      );

      await tester.pumpWidget(
        _wrap(
          const SimulatorPanel(),
          overrides: [simulatorServiceProvider.overrideWithValue(service)],
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.textContaining('Select a backend'), findsOneWidget);
    });
  });

  group('SimulatorPanel — run results', () {
    testWidgets('locked deploy panel keeps activity results visible', (
      tester,
    ) async {
      final service = _FakeSimulatorService(
        caps: [_ready('snntorch_sim', 'snnTorch simulator')],
        runResult: _resultWithSpikesAndVoltages(),
      );

      await tester.pumpWidget(
        _wrap(
          const SimulatorPanel(
            initialBackend: 'snntorch_sim',
            showResults: true,
          ),
          overrides: [simulatorServiceProvider.overrideWithValue(service)],
          withSpec: true,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Run'));
      await tester.pumpAndSettle();

      expect(find.text('Activity'), findsOneWidget);
      expect(find.text('Spike Raster'), findsOneWidget);
      expect(find.text('Membrane Potential'), findsOneWidget);
      expect(
        find.textContaining('activity and report are in the Review step'),
        findsNothing,
      );
    });

    testWidgets('renders result tabs after a successful run', (tester) async {
      final service = _FakeSimulatorService(
        caps: [
          _ready('lava_sim', 'Lava simulator'),
          _ready('snntorch_sim', 'snnTorch simulator'),
        ],
        runResult: _preflight(),
      );

      await tester.pumpWidget(
        _wrap(
          const SimulatorPanel(),
          overrides: [simulatorServiceProvider.overrideWithValue(service)],
          withSpec: true,
        ),
      );
      await tester.pump();
      await tester.pump();

      // Tap Run Simulation
      await tester.tap(find.text('Run Simulation'));
      await tester.pumpAndSettle();

      // Tab bar is visible — Activity and Report are the two tabs.
      expect(find.text('Activity'), findsOneWidget);
      expect(find.text('Report'), findsOneWidget);
      // Support level badge
      expect(find.text('Exact'), findsOneWidget);
    });

    testWidgets('does not crash on 503 and shows error state', (tester) async {
      // Verifies that a missing-dependency 503 is handled gracefully: the panel
      // stays usable (Run Simulation button remains visible) and shows the error
      // icon without crashing.
      final service = _FakeSimulatorService(
        caps: [
          _ready('lava_sim', 'Lava simulator'),
          _ready('snntorch_sim', 'snnTorch simulator'),
        ],
        runError: const SimulatorApiException(
          503,
          '{"detail": {"error": "missing_dependency", "messages": ["Dependency not installed."], "items": [{"code": "missing_dependency", "message": "Dependency not installed.", "hint": "pip install lava-nc"}]}}',
        ),
      );

      await tester.pumpWidget(
        _wrap(
          const SimulatorPanel(),
          overrides: [simulatorServiceProvider.overrideWithValue(service)],
          withSpec: true,
        ),
      );
      await tester.pump();
      await tester.pump();

      await tester.tap(find.text('Run Simulation'));
      await tester.pumpAndSettle();

      // Panel must not crash — run button still visible and error icon shown
      expect(find.text('Run Simulation'), findsOneWidget);
      expect(find.text('Clear'), findsOneWidget);
      expect(find.byIcon(ZetaIcons.error_outline), findsOneWidget);
      expect(find.textContaining('Dependency not installed.'), findsWidgets);
      expect(find.textContaining('pip install lava-nc'), findsWidgets);
    });

    testWidgets(
      'locked backend updates when parent switches simulator targets',
      (tester) async {
        final service = _FakeSimulatorService(
          caps: [
            _ready('lava_sim', 'Lava simulator'),
            _ready('snntorch_sim', 'snnTorch simulator'),
          ],
          runResult: _preflight(),
        );

        await tester.pumpWidget(
          _wrap(
            const SimulatorPanel(initialBackend: 'lava_sim'),
            overrides: [simulatorServiceProvider.overrideWithValue(service)],
            withSpec: true,
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Run'));
        await tester.pumpAndSettle();

        await tester.pumpWidget(
          _wrap(
            const SimulatorPanel(initialBackend: 'snntorch_sim'),
            overrides: [simulatorServiceProvider.overrideWithValue(service)],
            withSpec: true,
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Run'));
        await tester.pumpAndSettle();

        expect(service.requests.map((r) => r.backendName), [
          'lava_sim',
          'snntorch_sim',
        ]);
      },
    );
  });

  group('SimulatorPanel — Activity tab', () {
    testWidgets('renders Activity tab with population selector', (
      tester,
    ) async {
      final service = _FakeSimulatorService(
        caps: [
          _ready('lava_sim', 'Lava simulator'),
          _ready('snntorch_sim', 'snnTorch simulator'),
        ],
        runResult: _resultWithSpikesAndVoltages(),
      );

      await tester.pumpWidget(
        _wrap(
          const SimulatorPanel(),
          overrides: [simulatorServiceProvider.overrideWithValue(service)],
          withSpec: true,
        ),
      );
      await tester.pump();
      await tester.pump();

      await tester.tap(find.text('Run Simulation'));
      await tester.pumpAndSettle();

      expect(find.text('Activity'), findsOneWidget);
      expect(find.text('Report'), findsOneWidget);

      // The Activity tab should be selected by default (first tab)
      expect(find.text('Population:'), findsOneWidget);
      expect(find.text('pop1'), findsWidgets); // in dropdown + in view
    });

    testWidgets(
      'shows spike raster and membrane potential labels when data is present',
      (tester) async {
        final service = _FakeSimulatorService(
          caps: [
            _ready('lava_sim', 'Lava simulator'),
            _ready('snntorch_sim', 'snnTorch simulator'),
          ],
          runResult: _resultWithSpikesAndVoltages(),
        );

        await tester.pumpWidget(
          _wrap(
            const SimulatorPanel(),
            overrides: [simulatorServiceProvider.overrideWithValue(service)],
            withSpec: true,
          ),
        );
        await tester.pump();
        await tester.pump();

        await tester.tap(find.text('Run Simulation'));
        await tester.pumpAndSettle();

        // Activity tab is selected — spike raster and membrane potential labels are visible
        expect(find.text('Spike Raster'), findsOneWidget);
        expect(find.text('Membrane Potential'), findsOneWidget);
      },
    );

    testWidgets(
      'Report tab shows Output Summary, Warnings, NIR Support as section headers',
      (tester) async {
        final service = _FakeSimulatorService(
          caps: [
            _ready('lava_sim', 'Lava simulator'),
            _ready('snntorch_sim', 'snnTorch simulator'),
          ],
          runResult: _resultWithSpikesAndVoltages(),
        );

        await tester.pumpWidget(
          _wrap(
            const SimulatorPanel(),
            overrides: [simulatorServiceProvider.overrideWithValue(service)],
            withSpec: true,
          ),
        );
        await tester.pump();
        await tester.pump();

        await tester.tap(find.text('Run Simulation'));
        await tester.pumpAndSettle();

        // Switch to Report tab
        await tester.tap(find.text('Report'));
        await tester.pumpAndSettle();

        expect(
          find.text('Output Summary', skipOffstage: false),
          findsOneWidget,
        );
        expect(find.text('Warnings', skipOffstage: false), findsOneWidget);
        expect(find.text('NIR Support', skipOffstage: false), findsOneWidget);
      },
    );

    testWidgets('shows no populations message when data is empty', (
      tester,
    ) async {
      final service = _FakeSimulatorService(
        caps: [_ready('lava_sim', 'Lava simulator')],
        runResult: _preflight(),
      );

      await tester.pumpWidget(
        _wrap(
          const SimulatorPanel(),
          overrides: [simulatorServiceProvider.overrideWithValue(service)],
          withSpec: true,
        ),
      );
      await tester.pump();
      await tester.pump();

      await tester.tap(find.text('Run Simulation'));
      await tester.pumpAndSettle();

      // Activity tab should be selected (first tab), shows empty state
      expect(find.text('No populations recorded.'), findsOneWidget);
    });
  });

  group('SimulatorPanel — trained weights', () {
    // The CNL spec stores tensor shape only, so a run without the workspace's
    // trained `.nir` simulates a network of zeros: it completes in milliseconds
    // and records nothing. Run is gated on it, and the payload carries it.

    testWidgets('Run is disabled and says why when nothing has been trained', (
      tester,
    ) async {
      final service = _FakeSimulatorService(
        caps: [_ready('snntorch_sim', 'snnTorch simulator')],
        runResult: _resultWithSpikesAndVoltages(),
      );

      await tester.pumpWidget(
        _wrap(
          const SimulatorPanel(initialBackend: 'snntorch_sim'),
          overrides: [simulatorServiceProvider.overrideWithValue(service)],
          withSpec: true,
          trainedNir: null,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Run'), warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(service.requests, isEmpty);
      expect(
        find.byWidgetPredicate(
          (w) => w is Tooltip && w.message == SimulatorRunGate.untrainedMessage,
        ),
        findsOneWidget,
      );
    });

    testWidgets('a run carries the trained graph to the backend', (
      tester,
    ) async {
      final service = _FakeSimulatorService(
        caps: [_ready('snntorch_sim', 'snnTorch simulator')],
        runResult: _resultWithSpikesAndVoltages(),
      );

      await tester.pumpWidget(
        _wrap(
          const SimulatorPanel(initialBackend: 'snntorch_sim'),
          overrides: [simulatorServiceProvider.overrideWithValue(service)],
          withSpec: true,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Run'));
      await tester.pumpAndSettle();

      expect(service.requests, hasLength(1));
      expect(service.requests.single.trainedNirBase64, _trainedNir.nirBase64);
      expect(
        service.requests.single.toJson()['trained_nir_base64'],
        _trainedNir.nirBase64,
      );
    });

    testWidgets('an empty raster shows the run\'s own explanation', (
      tester,
    ) async {
      final service = _FakeSimulatorService(
        caps: [_ready('snntorch_sim', 'snnTorch simulator')],
        runResult: _silentRunWithWarning(),
      );

      await tester.pumpWidget(
        _wrap(
          const SimulatorPanel(initialBackend: 'snntorch_sim'),
          overrides: [simulatorServiceProvider.overrideWithValue(service)],
          withSpec: true,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Run'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Every weight in this network is 0.0'),
        findsOneWidget,
      );
    });
  });
}
