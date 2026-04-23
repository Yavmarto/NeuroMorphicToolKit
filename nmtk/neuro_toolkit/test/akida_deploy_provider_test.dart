import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';

import 'package:neuro_toolkit/models/module.dart';
import 'package:neuro_toolkit/services/akida_deploy_service.dart';
import 'package:neuro_toolkit/services/control_api_service.dart';
import 'package:neuro_toolkit/providers/akida_deploy_provider.dart'
    as deploy_provider;

class _RecordingAkidaDeployService extends AkidaDeployService {
  _RecordingAkidaDeployService({required this.verificationResponse});

  final AkidaSdkVerification verificationResponse;
  String? lastDownloadBaseUrl;
  String? lastVerifyBaseUrl;

  @override
  Future<AkidaNetworkResponse> checkExportability({
    required String spec,
    required int weightBitWidth,
    String akidaVersion = 'akida1',
  }) async {
    return const AkidaNetworkResponse(
      supportState: AkidaSupportState.exportableScaffold,
      akidaVersion: 'akida1',
      topologyVerdict: 'faithful',
      warnings: <String>[],
      rejectionReasons: <String>[],
      mappedNetwork: <String, dynamic>{'layers': <Object>[]},
    );
  }

  @override
  Future<String> downloadPackage({
    required Map<String, dynamic> mappedNetwork,
    required int bitWidth,
    required String outputDir,
    String? neurochipBaseUrl,
  }) async {
    lastDownloadBaseUrl = neurochipBaseUrl ?? localNeurochipBaseUrl;
    return '$outputDir/akida_deploy.zip';
  }

  @override
  Future<AkidaSdkVerification> verifySdk({
    Map<String, dynamic>? mappedNetwork,
    int bitWidth = 4,
    String? neurochipBaseUrl,
  }) async {
    lastVerifyBaseUrl = neurochipBaseUrl ?? localNeurochipBaseUrl;
    return verificationResponse;
  }

  @override
  void dispose() {}
}

class _ProviderControlApiService extends ControlApiService {
  _ProviderControlApiService({
    required this.module,
    this.remoteHosts = const <AkidaPairedHost>[],
    this.selectedAkidaHostId,
  });

  final Module module;
  final List<AkidaPairedHost> remoteHosts;
  String? selectedAkidaHostId;

  @override
  Future<Module> fetchModule(String moduleId) async => module;

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
}

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
        requiredPackages: <String>[
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

  test(
    'startDeploy routes scaffold and verify requests to selected remote host',
    () async {
      final service = _RecordingAkidaDeployService(
        verificationResponse: const AkidaSdkVerification(
          sdkAvailable: true,
          sdkStatus: 'deployable',
          sdkIssues: <String>[],
          state: 'mapped',
          runtimeTarget: 'akd1000_simulator',
        ),
      );
      final provider = deploy_provider.AkidaDeployProvider(
        service: service,
        controlApiService: _ProviderControlApiService(
          module: neurochipModule,
          remoteHosts: const <AkidaPairedHost>[
            AkidaPairedHost(
              id: 'remote-akida-1',
              displayName: 'Remote Akida Linux',
              host: 'akida-linux',
              sshPort: 22,
              username: 'operator',
              runtimeApiUrl: 'http://akida-linux:8002',
              controlApiUrl: 'http://akida-linux:8090',
              authMode: AkidaHostAuthMode.none,
              credentialRef: '',
              password: '',
              hasPassword: false,
              sshKeyPath: '',
              remoteInstallRoot: '/opt/neurochip-akida-host',
              serviceUser: 'neurochip',
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

      await provider.refreshRuntimeSetup();
      provider.setRuntimeMode(deploy_provider.AkidaRuntimeMode.remoteSdk);
      provider.selectRemoteHost('remote-akida-1');
      await provider.checkExportability(
        spec: 'The sensory neuron MUST fire.',
        weightBitWidth: 4,
      );
      await provider.startDeploy(
        mappedNetwork: provider.exportResult!.mappedNetwork!,
        bitWidth: 4,
        outputDir: '/tmp',
      );

      expect(service.lastDownloadBaseUrl, 'http://akida-linux:8002');
      expect(service.lastVerifyBaseUrl, 'http://akida-linux:8002');
      expect(provider.currentStep, deploy_provider.AkidaDeployStep.done);
    },
  );

  test(
    'local simulator mode keeps requests on the local Neurochip runtime and treats simulator fallback as expected',
    () async {
      final service = _RecordingAkidaDeployService(
        verificationResponse: const AkidaSdkVerification(
          sdkAvailable: false,
          sdkStatus: 'not_available',
          sdkIssues: <String>['sdk_not_available'],
          state: 'not_initialised',
          runtimeTarget: 'software_fallback',
        ),
      );
      final provider = deploy_provider.AkidaDeployProvider(
        service: service,
        controlApiService: _ProviderControlApiService(module: neurochipModule),
        platformOverride: TargetPlatform.android,
      );

      await provider.refreshRuntimeSetup();
      await provider.checkExportability(
        spec: 'The sensory neuron MUST fire.',
        weightBitWidth: 4,
      );
      await provider.startDeploy(
        mappedNetwork: provider.exportResult!.mappedNetwork!,
        bitWidth: 4,
        outputDir: '/tmp',
      );

      expect(
        provider.runtimeMode,
        deploy_provider.AkidaRuntimeMode.localSimulator,
      );
      expect(service.lastDownloadBaseUrl, 'http://localhost:8002');
      expect(service.lastVerifyBaseUrl, 'http://localhost:8002');
      expect(provider.isExpectedLocalSimulatorOutcome, isTrue);
      expect(provider.currentStep, deploy_provider.AkidaDeployStep.done);
    },
  );
}
