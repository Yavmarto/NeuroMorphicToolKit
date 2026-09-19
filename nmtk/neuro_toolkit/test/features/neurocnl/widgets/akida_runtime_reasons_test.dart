// The Akida Runtime panel must say *why* a host is not ready.
//
// `AkidaPairedHost.lastReadinessMessage`, `AkidaSdkVerification.sdkIssueDetail`,
// `.sdkIssues`, and `AkidaEnvironmentChecks` were all decoded from the launcher
// control / host payloads and rendered nowhere, so "Runtime mapping did not
// pass" and "Simulator Only" were the entire explanation a user got — a missing
// `cnn2snn` looked identical to an unplugged card. These tests pin the reasons
// to the screen.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:typed_data';

import 'package:neuro_toolkit/features/neurocnl/l10n/app_localizations.dart';
import 'package:neuro_toolkit/features/neurocnl/models/canvas/canvas.dart';
import 'package:neuro_toolkit/features/neurocnl/models/studio_result_session.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/api_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/canvas/canvas_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/studio_akida_deploy_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/studio_result_session_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/training_mode_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/training_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/workspace_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/screens/studio_screen.dart';
import 'package:neuro_toolkit/features/neurocnl/services/server_config_service.dart';
import 'package:neuro_toolkit/features/neurocnl/services/studio_akida_deploy_service.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/canvas/spike_playback_transport.dart';

import '../providers_test.mocks.dart';

/// A host that installed successfully but landed on the simulator — the exact
/// state the guide warns can never earn "Hardware verified".
const _degradedHost = AkidaPairedHost(
  id: 'akida-1',
  displayName: 'Bench Akida',
  host: '192.168.2.51',
  sshPort: 22,
  username: 'moosebun2',
  runtimeApiUrl: 'http://192.168.2.51:8002',
  controlApiUrl: 'http://192.168.2.51:8091',
  authMode: AkidaHostAuthMode.password,
  credentialRef: '',
  password: '',
  hasPassword: true,
  sshKeyPath: '',
  remoteInstallRoot: '/opt/neurochip-akida-host',
  serviceUser: 'neurochip',
  hostOs: 'Ubuntu 24.04',
  pythonVersion: '3.11.9',
  runtimeMode: AkidaRuntimeMode.remoteSdk,
  state: AkidaPairedHostState.simulatorOnly,
  lastReadinessMessage: 'No physical Akida device was enumerated on the host.',
  lastVerifiedAt: '2026-08-05T09:00:00Z',
  installedRuntimeVersion: '0.4.2',
  capabilitySnapshot: AkidaEnvironmentChecks(
    hostSupported: true,
    pythonSupported: true,
    tensorflowAvailable: true,
    cnn2snnAvailable: false,
    akidaModelsAvailable: false,
    recommendedRuntime: 'simulator_only',
  ),
);

void _restoreSourceSnapshot(
  ProviderContainer container, {
  String id = 'source-snapshot',
}) {
  container
      .read(studioResultSessionProvider.notifier)
      .restoreSnapshot(
        StudioResultSnapshot(
          id: id,
          completedAt: DateTime.utc(2026, 8, 10),
          provenance: const StudioResultProvenance(
            workspaceName: 'Akida test',
            modelFingerprint: 'model-a',
          ),
          platforms: const <String, StudioPlatformResult>{
            'lava_sim': StudioPlatformResult(
              platform: 'lava_sim',
              outcome: StudioPlatformOutcome.complete,
              history: <TrainingEpochEvent>[
                TrainingEpochEvent(epoch: 1, loss: 0.1),
              ],
            ),
          },
          selection: const StudioVisualizationSelection(platform: 'lava_sim'),
          isPartial: false,
        ),
      );
}

const _failedVerification = AkidaSdkVerification(
  sdkAvailable: true,
  sdkStatus: 'not_deployable',
  sdkIssues: ['cnn2snn is not installed', 'akida_models is not installed'],
  state: 'sdk_loading',
  runtimeTarget: 'software_fallback',
  sdkIssueDetail: 'Akida SDK components are missing on the remote host.',
  environmentChecks: AkidaEnvironmentChecks(
    hostSupported: true,
    pythonSupported: true,
    tensorflowAvailable: true,
    cnn2snnAvailable: false,
    akidaModelsAvailable: false,
    recommendedRuntime: 'simulator_only',
  ),
);

class _FixedStudioAkidaDeployController extends StudioAkidaDeployController {
  _FixedStudioAkidaDeployController(this._state);
  final StudioAkidaDeployState _state;
  StudioAkidaBundleArtifact? submittedBundle;

  @override
  StudioAkidaDeployState build() => _state;

  @override
  Future<void> submitBundle(StudioAkidaBundleArtifact artifact) async {
    submittedBundle = artifact;
  }
}

void main() {
  late MockApiClient mockApi;

  setUp(() async {
    WorkspaceController.debugSetDebounces(
      persist: Duration.zero,
      serverSync: Duration.zero,
    );
    SharedPreferences.setMockInitialValues({});
    ServerConfigService.debugResetForTests();
    await ServerConfigService.initialize();
    mockApi = MockApiClient();
    when(mockApi.getTemplates()).thenAnswer((_) async => const []);
  });

  /// [step] selects which Execute step to land on: `deployHardware` for setup
  /// and run controls, `deployReview` for the result charts — the Deploy step
  /// no longer renders results.
  Future<ProviderContainer> pumpAkidaPanel(
    WidgetTester tester,
    StudioAkidaDeployState state, {
    String step = 'deployHardware',
    Size size = const Size(1440, 900),
    _FixedStudioAkidaDeployController? controller,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(mockApi),
          workspaceBootstrapProvider.overrideWithValue(
            const WorkspaceBootstrap(
              initialLocation: '/?panel=deploy&target=akida',
            ),
          ),
          studioAkidaDeployProvider.overrideWith(
            () => controller ?? _FixedStudioAkidaDeployController(state),
          ),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: StudioScreen()),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));

    final container = ProviderScope.containerOf(
      tester.element(find.byType(StudioScreen)),
    );
    container.read(workspaceProvider.notifier)
      ..togglePlatform('akida')
      ..setActivePipelineStep(step);
    await tester.pumpAndSettle();

    final restoreDialog = find.text('Restore previous session?');
    if (restoreDialog.evaluate().isNotEmpty) {
      await tester.tap(find.text('Start fresh'));
      await tester.pumpAndSettle();
    }

    if (step == 'deployHardware') {
      final configure = find.byKey(const Key('hardware-target-open-akida'));
      if (configure.evaluate().isNotEmpty) {
        await tester.ensureVisible(configure);
        await tester.pumpAndSettle();
        await tester.tap(configure);
        await tester.pumpAndSettle();
      }
    }
    return container;
  }

  testWidgets('Akida configure dialog submits the selected Akida bundle', (
    WidgetTester tester,
  ) async {
    const bundle = StudioAkidaBundleArtifact(
      filename: 'model.akida-bundle.zip',
      bundleBase64: 'YnVuZGxl',
      sha256: 'bundle-sha',
      schemaVersion: 2,
    );
    final controller = _FixedStudioAkidaDeployController(
      const StudioAkidaDeployState(
        selectedHost: _degradedHost,
        bundleArtifact: bundle,
      ),
    );
    await pumpAkidaPanel(
      tester,
      const StudioAkidaDeployState(
        selectedHost: _degradedHost,
        bundleArtifact: bundle,
      ),
      size: const Size(390, 844),
      controller: controller,
    );

    final deployAction = find.byKey(const Key('akida-deploy-latest-bundle'));
    expect(deployAction, findsOneWidget);
    await tester.ensureVisible(deployAction);
    await tester.pumpAndSettle();
    await tester.tap(deployAction);
    await tester.pump();

    expect(controller.submittedBundle, bundle);
  });

  testWidgets('degraded host shows its readiness reason and env checks', (
    WidgetTester tester,
  ) async {
    await pumpAkidaPanel(
      tester,
      const StudioAkidaDeployState(selectedHost: _degradedHost),
    );

    expect(find.text('Simulator Only'), findsWidgets);
    expect(
      find.text('No physical Akida device was enumerated on the host.'),
      findsOneWidget,
      reason:
          'lastReadinessMessage is _describe_akida_preflight() output — the one '
          'line that says why the host is not Ready.',
    );
    // Per-component verdicts, so a missing SDK component is distinguishable
    // from an absent card. The heading no longer repeats the component names —
    // the badges below it carry those.
    expect(find.text('Runtime components'), findsOneWidget);
    expect(find.textContaining('Missing'), findsWidgets);
    // A missing component offers an in-app remedy rather than a dead end.
    expect(
      find.byKey(const Key('akida-install-missing-components')),
      findsOneWidget,
      reason:
          'the only other way to restore a missing runtime component is a '
          'terminal on the host, which end users never open.',
    );
  });

  testWidgets('failed SDK verification lists its issues and detail', (
    WidgetTester tester,
  ) async {
    await pumpAkidaPanel(
      tester,
      const StudioAkidaDeployState(
        selectedHost: _degradedHost,
        sdkVerification: _failedVerification,
      ),
    );

    expect(find.text('Runtime mapping did not pass.'), findsOneWidget);
    expect(
      find.text('Akida SDK components are missing on the remote host.'),
      findsOneWidget,
      reason: 'sdkIssueDetail was parsed and never rendered.',
    );
    expect(find.textContaining('cnn2snn is not installed'), findsWidgets);
    expect(
      find.textContaining('akida_models is not installed'),
      findsWidgets,
      reason:
          'Every entry of sdkIssues must reach the screen, not just the '
          'first.',
    );
  });

  testWidgets('a hardware-verified job renders the Physical Akida badge', (
    WidgetTester tester,
  ) async {
    // Cross-check for CEL-373: the CEL-372 backend run recorded
    // runtime_target=hardware + hardwareVerified=true. The deploy UI must
    // surface exactly that claim and never the simulator wording. The badge
    // text had no widget-level assertion before this.
    await pumpAkidaPanel(
      tester,
      const StudioAkidaDeployState(
        selectedHost: _degradedHost,
        deploymentJob: StudioAkidaModelJob(
          jobId: 'deploy-hw',
          stage: 'completed',
          progress: 100,
          message: 'Deployed on the AKD1000.',
          modelId: 'model-1',
          runtimeTarget: 'hardware',
          hardwareVerified: true,
          metrics: <String, double>{},
        ),
      ),
    );

    expect(find.text('Physical Akida verified'), findsOneWidget);
    expect(find.text('Simulator result'), findsNothing);
  });

  testWidgets('a simulator job never renders the Physical Akida badge', (
    WidgetTester tester,
  ) async {
    await pumpAkidaPanel(
      tester,
      const StudioAkidaDeployState(
        selectedHost: _degradedHost,
        deploymentJob: StudioAkidaModelJob(
          jobId: 'deploy-sim',
          stage: 'completed',
          progress: 100,
          message: 'Deployed on the Akida simulator.',
          modelId: 'model-1',
          runtimeTarget: 'akd1000_simulator',
          hardwareVerified: false,
          metrics: <String, double>{},
        ),
      ),
    );

    expect(find.text('Simulator result'), findsOneWidget);
    expect(find.text('Physical Akida verified'), findsNothing);
  });

  testWidgets('the two workflows are labelled separately', (
    WidgetTester tester,
  ) async {
    await pumpAkidaPanel(
      tester,
      const StudioAkidaDeployState(selectedHost: _degradedHost),
    );

    // Nine actions in one undivided wrap gave no hint which belong to the
    // MNIST/bundle walkthrough and which drive the CNL spec export.
    expect(find.text('Deployment setup'), findsOneWidget);
    expect(find.text('Advanced topology check'), findsOneWidget);
  });

  testWidgets('the spec-export group says its weights are placeholders', (
    WidgetTester tester,
  ) async {
    await pumpAkidaPanel(
      tester,
      const StudioAkidaDeployState(selectedHost: _degradedHost),
    );

    // "Independent of the bundle path" did not stop people expecting a
    // deployable model out of Generate Package, which maps the topology with
    // untrained weights.
    expect(find.textContaining('placeholder'), findsWidgets);
  });

  testWidgets('unmapped hardware layer counts use the truthful list fallback', (
    WidgetTester tester,
  ) async {
    await pumpAkidaPanel(
      tester,
      const StudioAkidaDeployState(
        selectedHost: _degradedHost,
        deploymentJob: StudioAkidaModelJob(
          jobId: 'deploy-1',
          stage: 'completed',
          progress: 100,
          message: 'Deployed.',
          modelId: 'model-1',
          runtimeTarget: 'hardware',
          hardwareVerified: true,
          metrics: <String, double>{},
        ),
        sampleResult: StudioAkidaSampleSnapshot(
          provenance: StudioAkidaResultProvenance(
            hostId: 'akida-1',
            modelId: 'model-1',
            runtimeTarget: 'hardware',
            hardwareVerified: true,
            sourceSnapshotId: 'source-snapshot',
          ),
          prediction: StudioAkidaModelPrediction(
            sampleIndex: 4,
            prediction: 7,
            label: 7,
            labelName: 'seven',
            outputs: <double>[0.1, 0.3, 2.4],
            runtimeTarget: 'hardware',
            hardwareVerified: true,
            telemetry: <String, dynamic>{'fps': 188.1},
            layerSpikes: <LayerSpikeStats>[
              LayerSpikeStats(name: 'unmapped_hidden', nzSpikes: 42),
            ],
          ),
        ),
        latestResultKind: StudioAkidaResultKind.sample,
      ),

      step: 'deployReview',
    );

    expect(find.text('Raw output activations'), findsOneWidget);
    expect(find.text('Layer activity'), findsOneWidget);
    expect(find.textContaining('42 spikes'), findsOneWidget);
    expect(find.text('Architecture'), findsOneWidget);
    expect(find.text('Grid'), findsOneWidget);
    expect(find.text('Raster'), findsOneWidget);
    expect(find.text('Weights'), findsOneWidget);
    expect(find.textContaining('Source run unavailable'), findsOneWidget);
    expect(find.textContaining('Complete a run in step 5'), findsOneWidget);
  });

  testWidgets('hardware Architecture maps aggregate activity to canvas nodes', (
    WidgetTester tester,
  ) async {
    final container = await pumpAkidaPanel(
      tester,
      const StudioAkidaDeployState(
        selectedHost: _degradedHost,
        deploymentJob: StudioAkidaModelJob(
          jobId: 'deploy-1',
          stage: 'completed',
          progress: 100,
          message: 'Deployed.',
          modelId: 'model-1',
          runtimeTarget: 'hardware',
          hardwareVerified: true,
          metrics: <String, double>{},
        ),
        sampleResult: StudioAkidaSampleSnapshot(
          provenance: StudioAkidaResultProvenance(
            hostId: 'akida-1',
            modelId: 'model-1',
            runtimeTarget: 'hardware',
            hardwareVerified: true,
            sourceSnapshotId: 'source-snapshot',
          ),
          prediction: StudioAkidaModelPrediction(
            sampleIndex: 4,
            prediction: 7,
            label: 7,
            labelName: 'seven',
            outputs: <double>[0.1, 0.3, 2.4],
            runtimeTarget: 'hardware',
            hardwareVerified: true,
            telemetry: <String, dynamic>{},
            layerSpikes: <LayerSpikeStats>[
              LayerSpikeStats(name: 'LIF 1', nzSpikes: 42),
            ],
          ),
        ),
        latestResultKind: StudioAkidaResultKind.sample,
      ),

      step: 'deployReview',
    );

    _restoreSourceSnapshot(container);

    container
        .read(canvasProvider.notifier)
        .setGraph(
          CanvasGraph(
            nodes: <CanvasNode>[
              CanvasNode(
                id: 'lif_1',
                componentId: 'lif_population',
                nirType: 'nir.LIF',
                label: 'LIF',
                parameters: const <String, dynamic>{'name': 'LIF 1'},
                position: const <double>[400, 300],
              ),
            ],
            edges: const <CanvasEdge>[],
            metadata: const <String, dynamic>{},
          ),
        );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Architecture'));
    await tester.pump();
    await tester.ensureVisible(find.text('Use Akida activity'));
    await tester.pump();
    await tester.tap(find.text('Use Akida activity'));
    await tester.pumpAndSettle();

    expect(container.read(trainingModeProvider), <String, double>{'lif_1': 1});
  });

  testWidgets('hardware fallback labels the selected source run', (
    WidgetTester tester,
  ) async {
    final container = await pumpAkidaPanel(
      tester,
      const StudioAkidaDeployState(selectedHost: _degradedHost),

      step: 'deployReview',
    );
    _restoreSourceSnapshot(container);
    await tester.pumpAndSettle();

    expect(find.textContaining('Source run · Lava'), findsOneWidget);
  });

  testWidgets('job metrics render with their own units, not as percentages', (
    WidgetTester tester,
  ) async {
    // Every metric used to be multiplied by 100 and suffixed '%', so latency
    // showed as "142.00%". This is the regression guard for that.
    await pumpAkidaPanel(
      tester,
      const StudioAkidaDeployState(
        selectedHost: _degradedHost,
        deploymentJob: StudioAkidaModelJob(
          jobId: 'bench-1',
          stage: 'completed',
          progress: 100,
          message: 'Benchmarked 2000 samples.',
          modelId: 'model-1',
          runtimeTarget: 'hardware',
          hardwareVerified: true,
          metrics: <String, double>{
            'akida_accuracy': 0.9650,
            'akida_sim_accuracy': 0.9750,
            'latency_ms': 1.42,
            'fps': 704.2,
          },
          totalSamples: 2000,
          classResults: <StudioAkidaClassResult>[
            StudioAkidaClassResult(
              label: 0,
              labelName: 'zero',
              support: 200,
              correct: 198,
            ),
            StudioAkidaClassResult(
              label: 1,
              labelName: 'one',
              support: 200,
              correct: 120,
            ),
          ],
        ),
        benchmarkResult: StudioAkidaBenchmarkSnapshot(
          provenance: StudioAkidaResultProvenance(
            hostId: 'akida-degraded',
            modelId: 'model-1',
            runtimeTarget: 'hardware',
            hardwareVerified: true,
          ),
          job: StudioAkidaModelJob(
            jobId: 'bench-1',
            stage: 'completed',
            progress: 100,
            message: 'Benchmarked 2000 samples.',
            modelId: 'model-1',
            runtimeTarget: 'hardware',
            hardwareVerified: true,
            metrics: <String, double>{
              'akida_accuracy': 0.9650,
              'akida_sim_accuracy': 0.9750,
              'latency_ms': 1.42,
              'fps': 704.2,
            },
            totalSamples: 2000,
            classResults: <StudioAkidaClassResult>[
              StudioAkidaClassResult(
                label: 0,
                labelName: 'zero',
                support: 200,
                correct: 198,
              ),
              StudioAkidaClassResult(
                label: 1,
                labelName: 'one',
                support: 200,
                correct: 120,
              ),
            ],
          ),
        ),
        latestResultKind: StudioAkidaResultKind.benchmark,
      ),

      step: 'deployReview',
    );

    // Accuracy keeps its percentage, and says where it came from. It appears
    // twice by design: once as the headline verdict, once as its own tile.
    expect(find.text('Accuracy on card (2000 samples)'), findsOneWidget);
    expect(find.text('96.50%'), findsNWidgets(2));
    expect(find.text('Accuracy in Akida simulator'), findsOneWidget);

    // The verdict states the comparison the user came for, rather than leaving
    // them to subtract two tiles.
    expect(find.text('On card across 2000 samples'), findsOneWidget);
    expect(
      find.textContaining('1.00 pp below the Akida simulator'),
      findsOneWidget,
    );

    // Performance metrics carry real units.
    expect(find.text('1.420 ms'), findsOneWidget);
    expect(find.text('704.2 fps'), findsOneWidget);
    expect(find.text('142.00%'), findsNothing);

    // Per-class results are listed, weakest class included, at the same
    // precision as the metric grid directly above it.
    expect(find.text('Accuracy by class'), findsOneWidget);
    expect(find.textContaining('zero'), findsWidgets);
    expect(find.textContaining('60.0%'), findsOneWidget);
  });

  testWidgets(
    'Akida replay auto-selects and never presents fake time controls',
    (WidgetTester tester) async {
      final visualization = StudioAkidaModelVisualization(
        modelId: 'model-1',
        mode: StudioAkidaVisualizationMode.sample,
        layers: const <StudioAkidaVisualizationLayer>[
          StudioAkidaVisualizationLayer(
            index: 1,
            name: 'Hidden',
            outputShape: <int>[3],
            weightShape: <int>[2, 3],
            weightBits: 8,
            visualizable: true,
          ),
        ],
        layerIndex: 1,
        layerName: 'Hidden',
        sampleIndex: 4,
        sampleCount: 1,
        available: true,
        activity: StudioAkidaCompressedArray(
          dtype: '|u1',
          shape: const <int>[3],
          bytes: Uint8List.fromList(<int>[0, 2, 5]),
        ),
        weights: StudioAkidaCompressedArray(
          dtype: '|i1',
          shape: const <int>[2, 3],
          bytes: Uint8List.fromList(<int>[1, 254, 3, 4, 251, 6]),
        ),
        weightBits: 8,
        provenance: 'akida_software_replay',
        relatedRuntimeTarget: 'hardware',
        hardwareVerified: false,
      );
      await pumpAkidaPanel(
        tester,
        StudioAkidaDeployState(
          selectedHost: _degradedHost,
          deploymentJob: const StudioAkidaModelJob(
            jobId: 'deploy-1',
            stage: 'completed',
            progress: 100,
            message: 'Deployed.',
            modelId: 'model-1',
            runtimeTarget: 'hardware',
            hardwareVerified: true,
            metrics: <String, double>{},
          ),
          sampleResult: const StudioAkidaSampleSnapshot(
            provenance: StudioAkidaResultProvenance(
              hostId: 'akida-1',
              modelId: 'model-1',
              runtimeTarget: 'hardware',
              hardwareVerified: true,
            ),
            prediction: StudioAkidaModelPrediction(
              sampleIndex: 4,
              prediction: 7,
              label: 7,
              labelName: 'seven',
              outputs: <double>[0.1, 2.4],
              runtimeTarget: 'hardware',
              hardwareVerified: true,
              telemetry: <String, dynamic>{},
            ),
          ),
          latestResultKind: StudioAkidaResultKind.sample,
          visualizationResult: visualization,
        ),

        step: 'deployReview',
      );

      // Provenance is one line of metadata now, not a stack of banners
      // restating what the page header already says.
      expect(
        find.textContaining('Replayed from the deployed Akida model'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('akida-architecture-view')), findsOneWidget);

      final replayViewSwitchPosition = tester.getTopLeft(
        find.text('Architecture'),
      );
      final replaySourceSwitchPosition = tester.getTopLeft(
        find.text('Akida replay'),
      );
      await tester.tap(find.text('Source run'));
      await tester.pumpAndSettle();
      expect(find.text('Architecture'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Akida replay')),
        replaySourceSwitchPosition,
      );
      expect(
        tester.getTopLeft(find.text('Architecture')),
        replayViewSwitchPosition,
      );
      expect(
        find.textContaining('Rendered from the source run'),
        findsOneWidget,
      );

      await tester.tap(find.text('Akida replay'));
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(find.text('Architecture')),
        replayViewSwitchPosition,
      );
      await tester.tap(find.text('Raster').last);
      await tester.pumpAndSettle();
      expect(
        find.text('Static neuron versus activation-count plot'),
        findsOneWidget,
      );
      expect(find.textContaining('ms'), findsNothing);
      expect(find.byType(SpikePlaybackTransport), findsNothing);
    },
  );

  testWidgets('unavailable Akida layer falls back without hiding the reason', (
    WidgetTester tester,
  ) async {
    await pumpAkidaPanel(
      tester,
      const StudioAkidaDeployState(
        selectedHost: _degradedHost,
        visualizationResult: StudioAkidaModelVisualization(
          modelId: 'model-1',
          mode: StudioAkidaVisualizationMode.sample,
          layers: <StudioAkidaVisualizationLayer>[
            StudioAkidaVisualizationLayer(
              index: 1,
              name: 'Branched',
              outputShape: <int>[],
              visualizable: false,
            ),
          ],
          layerIndex: 1,
          layerName: 'Branched',
          sampleCount: 1,
          available: false,
          unavailableReason: 'This layer cannot be isolated by the runtime.',
          provenance: 'akida_software_replay',
          relatedRuntimeTarget: 'hardware',
          hardwareVerified: false,
        ),
      ),

      step: 'deployReview',
    );

    expect(
      find.text('This layer cannot be isolated by the runtime.'),
      findsOneWidget,
    );
    expect(find.textContaining('Source run unavailable'), findsOneWidget);
  });
}
