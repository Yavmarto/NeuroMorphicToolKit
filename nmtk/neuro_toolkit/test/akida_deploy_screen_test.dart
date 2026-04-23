import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';

import 'package:neuro_toolkit/models/module.dart';
import 'package:neuro_toolkit/providers/riverpod_providers.dart';
import 'package:neuro_toolkit/screens/akida_deploy_screen.dart';
import 'package:neuro_toolkit/services/akida_deploy_service.dart';
import 'package:neuro_toolkit/services/control_api_service.dart';
import 'package:neuro_toolkit/providers/akida_deploy_provider.dart'
    as deploy_provider;

// ---------------------------------------------------------------------------
// Minimal mock service (no network calls)
// ---------------------------------------------------------------------------

class _NopAkidaDeployService extends AkidaDeployService {
  @override
  Future<AkidaNetworkResponse> checkExportability({
    required String spec,
    required int weightBitWidth,
    String akidaVersion = 'akida1',
  }) async {
    return const AkidaNetworkResponse(
      supportState: AkidaSupportState.exportableScaffold,
      akidaVersion: 'akida1',
      topologyVerdict: 'ok',
      warnings: [],
      rejectionReasons: [],
    );
  }

  @override
  Future<String> downloadPackage({
    required Map<String, dynamic> mappedNetwork,
    required int bitWidth,
    required String outputDir,
    String? neurochipBaseUrl,
  }) async =>
      '/tmp/akida_deploy.zip';

  @override
  Future<AkidaDeployJob> getStatus() async =>
      const AkidaDeployJob(status: AkidaDeployJobStatus.notInitialised);

  @override
  Future<String> runNeurobenchJob({
    required String benchmarkId,
    required String networkPath,
    String target = 'simulation',
  }) async =>
      'job-001';

  @override
  Future<Map<String, dynamic>> getNeurobenchJobStatus(String jobId) async => {
        'status': 'complete',
      };

  @override
  void dispose() {}
}

class _FakeControlApiService extends ControlApiService {
  _FakeControlApiService({
    required Module module,
    this.remoteHosts = const <AkidaPairedHost>[],
    this.selectedAkidaHostId,
  }) : _module = module;

  Module _module;
  int prepareCalls = 0;
  final List<AkidaPairedHost> remoteHosts;
  String? selectedAkidaHostId;

  @override
  Future<Module> fetchModule(String moduleId) async => _module;

  @override
  Future<LauncherControlSettings> fetchSettings() async =>
      LauncherControlSettings(
        logLevel: 'info',
        mujocoAvailable: false,
        pythonAvailable: true,
        pynqBoards: const <PynqPairedBoard>[],
        akidaHosts: remoteHosts,
        selectedAkidaHostId: selectedAkidaHostId,
      );

  @override
  Future<void> updateSettings({
    String? logLevel,
    String? selectedAkidaHostId,
  }) async {
    this.selectedAkidaHostId = selectedAkidaHostId ?? this.selectedAkidaHostId;
  }

  @override
  Future<Module> prepareAkidaRuntime(String moduleId) async {
    prepareCalls += 1;
    _module = _module.copyWith(
      akidaRuntimeState: AkidaRuntimeState(
        status: 'ready',
        message: 'Akida runtime is prepared for local SDK verification.',
        preparedAt: '2026-04-22T10:00:00Z',
      ),
    );
    return _module;
  }
}

// ---------------------------------------------------------------------------
// Helper
// ---------------------------------------------------------------------------

Widget _buildTestApp(
  deploy_provider.AkidaDeployProvider provider, {
  TargetPlatform platform = TargetPlatform.android,
}) {
  return MaterialApp(
    theme: ThemeData(platform: platform),
    home: ProviderScope(
      overrides: [akidaDeployStateProvider.overrideWith((ref) => provider)],
      child: const AkidaDeployScreen(),
    ),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late Module neurochipModule;

  setUp(() {
    neurochipModule = Module(
      id: 'Neurochip',
      name: 'Neurochip',
      description: 'Hardware deployment',
      directory: '/tmp/Neurochip',
      akidaRuntime: const AkidaRuntimeConfig(
        supportedPlatforms: ['linux', 'windows'],
        pythonRange: '>=3.10,<3.13',
        requiredPackages: [
          'tensorflow==2.19.*',
          'akida==2.19.1',
          'cnn2snn==2.19.1',
          'akida-models==1.13.1',
        ],
        docsUrl: 'https://doc.brainchipinc.com/installation.html',
        localModeFallback: 'simulator_only',
      ),
      akidaRuntimeState: const AkidaRuntimeState(status: 'idle'),
    );
  });

  group('AkidaDeployScreen — Neurobench toggle', () {
    testWidgets('deploy config card shows enabled Neurobench switch', (
      tester,
    ) async {
      final provider = deploy_provider.AkidaDeployProvider(
        service: _NopAkidaDeployService(),
        controlApiService: _FakeControlApiService(module: neurochipModule),
        platformOverride: TargetPlatform.macOS,
      );
      await provider.checkExportability(
        spec: 'The sensory neuron MUST fire.',
        weightBitWidth: 8,
      );
      await tester.pumpWidget(_buildTestApp(provider));
      await tester.pumpAndSettle();

      // The deploy config card should be visible.
      expect(find.byType(Switch), findsWidgets);

      // Find the Neurobench switch specifically via its label.
      expect(
        find.text('Run Neurobench verification after deploy'),
        findsOneWidget,
      );
    });

    testWidgets('Neurobench switch is interactive (not hard-disabled)', (
      tester,
    ) async {
      final provider = deploy_provider.AkidaDeployProvider(
        service: _NopAkidaDeployService(),
        controlApiService: _FakeControlApiService(module: neurochipModule),
      );
      await provider.checkExportability(
        spec: 'The sensory neuron MUST fire.',
        weightBitWidth: 8,
      );
      await tester.pumpWidget(_buildTestApp(provider));
      await tester.pumpAndSettle();

      // Verify the old "not yet available" label is gone.
      expect(find.textContaining('not yet available'), findsNothing);
    });

    testWidgets(
      'setRunNeurobench toggles provider state and Switch reflects it',
      (tester) async {
        final controlApi = _FakeControlApiService(module: neurochipModule);
        final provider = deploy_provider.AkidaDeployProvider(
          service: _NopAkidaDeployService(),
          controlApiService: controlApi,
        );
        await provider.checkExportability(
          spec: 'The sensory neuron MUST fire.',
          weightBitWidth: 8,
        );
        expect(provider.runNeurobench, isFalse);

        await tester.pumpWidget(_buildTestApp(provider));
        await tester.pumpAndSettle();

        // Verify initial switch value is false.
        final switchWidget = tester
            .widgetList<Switch>(find.byType(Switch))
            .firstWhere((s) => s.onChanged != null);
        expect(switchWidget.value, isFalse);

        // Toggle via provider (same path the Switch.onChanged calls).
        provider.setRunNeurobench(true);
        await tester.pump();

        expect(provider.runNeurobench, isTrue);
        final switchWidgetAfter = tester
            .widgetList<Switch>(find.byType(Switch))
            .firstWhere((s) => s.onChanged != null);
        expect(switchWidgetAfter.value, isTrue);
      },
    );

    testWidgets('shows simulator-only guidance on macOS hosts', (tester) async {
      final provider = deploy_provider.AkidaDeployProvider(
        service: _NopAkidaDeployService(),
        controlApiService: _FakeControlApiService(module: neurochipModule),
      );
      await provider.checkExportability(
        spec: 'The sensory neuron MUST fire.',
        weightBitWidth: 4,
      );

      await tester.pumpWidget(
        _buildTestApp(provider, platform: TargetPlatform.macOS),
      );
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Use the local Neurochip module in simulator-only'),
        findsOneWidget,
      );
      expect(find.text('Prepare Akida Runtime'), findsNothing);
    });

    testWidgets(
      'shows explicit runtime mode choices and remote host selector',
      (tester) async {
        final provider = deploy_provider.AkidaDeployProvider(
          service: _NopAkidaDeployService(),
          controlApiService: _FakeControlApiService(
            module: neurochipModule,
            remoteHosts: const <AkidaPairedHost>[
              AkidaPairedHost(
                id: 'remote-akida-1',
                displayName: 'Remote Akida Linux',
                runtimeApiUrl: 'http://akida-linux:8002',
                authMode: AkidaHostAuthMode.none,
                credentialRef: '',
                hostOs: 'linux',
                pythonVersion: '3.11.8',
                runtimeMode: AkidaRuntimeMode.remoteSdk,
                state: AkidaPairedHostState.ready,
                lastReadinessMessage: 'Remote SDK ready',
                lastVerifiedAt: '',
              ),
            ],
            selectedAkidaHostId: 'remote-akida-1',
          ),
          platformOverride: TargetPlatform.windows,
        );
        await provider.checkExportability(
          spec: 'The sensory neuron MUST fire.',
          weightBitWidth: 4,
        );

        await tester.pumpWidget(
          _buildTestApp(provider, platform: TargetPlatform.windows),
        );
        await tester.pumpAndSettle();

        expect(find.text('Local simulator'), findsOneWidget);
        expect(find.text('Local SDK'), findsWidgets);
        expect(find.text('Remote SDK host'), findsOneWidget);

        provider.setRuntimeMode(deploy_provider.AkidaRuntimeMode.remoteSdk);
        await tester.pump();

        expect(find.text('Remembered remote host'), findsOneWidget);
        expect(
          find.textContaining('Selected runtime: Remote Akida Linux'),
          findsOneWidget,
        );
      },
    );

    testWidgets('offers local runtime preparation on supported hosts', (
      tester,
    ) async {
      final controlApi = _FakeControlApiService(module: neurochipModule);
      final provider = deploy_provider.AkidaDeployProvider(
        service: _NopAkidaDeployService(),
        controlApiService: controlApi,
        platformOverride: TargetPlatform.windows,
      );
      await provider.checkExportability(
        spec: 'The sensory neuron MUST fire.',
        weightBitWidth: 4,
      );

      await tester.pumpWidget(
        _buildTestApp(provider, platform: TargetPlatform.windows),
      );
      await tester.pumpAndSettle();

      expect(find.text('Prepare Akida Runtime'), findsOneWidget);
      await tester.ensureVisible(find.text('Prepare Akida Runtime'));
      await tester.tap(find.text('Prepare Akida Runtime'));
      await tester.pumpAndSettle();

      expect(controlApi.prepareCalls, 1);
      expect(
        find.text('Akida runtime is prepared for local SDK verification.'),
        findsOneWidget,
      );
    });
  });
}
