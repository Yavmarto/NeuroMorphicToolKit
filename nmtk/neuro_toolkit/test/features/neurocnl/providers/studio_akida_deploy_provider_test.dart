import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/api_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/studio_akida_deploy_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/services/api_client.dart';
import 'package:neuro_toolkit/features/neurocnl/services/studio_akida_deploy_service.dart';
import 'package:neuro_toolkit/features/neurocnl/services/studio_target_registry_service.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';
import 'dart:typed_data';

class _FakeStudioAkidaDeployService extends StudioAkidaDeployService {
  _FakeStudioAkidaDeployService({
    required this.exportResult,
    this.readinessHost,
    this.submittedJob,
    this.prediction,
    this.latestArtifact,
    this.fetchedJobs = const <StudioAkidaModelJob>[],
    this.benchmarkJob,
    this.startedRuntimeUpdate,
    this.fetchedRuntimeUpdates = const <AkidaRuntimeUpdateJob>[],
  }) : super(
         apiClient: ApiClient(baseUrl: 'http://test'),
         targetRegistryService: StudioTargetRegistryService(),
       );

  final AkidaNetworkResponse exportResult;
  final AkidaPairedHost? readinessHost;
  final StudioAkidaModelJob? submittedJob;
  final StudioAkidaModelPrediction? prediction;
  final StudioAkidaBundleArtifact? latestArtifact;
  final List<StudioAkidaModelJob> fetchedJobs;
  final StudioAkidaModelJob? benchmarkJob;
  final AkidaRuntimeUpdateJob? startedRuntimeUpdate;
  final List<AkidaRuntimeUpdateJob> fetchedRuntimeUpdates;

  String? lastValidatedSpec;
  String? lastReadinessHostId;
  String? lastPackageRuntimeApiUrl;
  String? lastMapRuntimeApiUrl;
  String? lastMapHostId;
  String? lastRunHostId;
  List<double>? lastRunInputs;
  int validateCalls = 0;
  int packageCalls = 0;
  int mapCalls = 0;
  int runCalls = 0;
  int modelSampleCalls = 0;
  int discoverBundleCalls = 0;
  int fetchJobCalls = 0;
  int benchmarkCalls = 0;
  int visualizationCalls = 0;
  int? lastVisualizationLayer;
  String? lastBenchmarkModelId;
  int fetchRuntimeUpdateCalls = 0;

  @override
  Future<AkidaNetworkResponse> validate({
    required String spec,
    required int bitWidth,
    required String akidaVersion,
  }) async {
    validateCalls += 1;
    lastValidatedSpec = spec;
    return exportResult;
  }

  @override
  Future<AkidaPairedHost> checkHostReadiness(String hostId) async {
    lastReadinessHostId = hostId;
    return readinessHost!;
  }

  @override
  Future<Uint8List> generatePackage({
    required String runtimeApiUrl,
    required String credentialRef,
    required Map<String, dynamic> mappedNetwork,
    required int bitWidth,
  }) async {
    packageCalls += 1;
    lastPackageRuntimeApiUrl = runtimeApiUrl;
    return Uint8List.fromList(const <int>[1, 2, 3]);
  }

  @override
  Future<AkidaSdkVerification> mapRuntime({
    required String runtimeApiUrl,
    required String credentialRef,
    required Map<String, dynamic> mappedNetwork,
    required int bitWidth,
  }) async {
    mapCalls += 1;
    lastMapRuntimeApiUrl = runtimeApiUrl;
    return const AkidaSdkVerification(
      sdkAvailable: true,
      sdkStatus: 'deployable',
      sdkIssues: <String>[],
      state: 'mapped',
      runtimeTarget: 'hardware',
    );
  }

  @override
  Future<AkidaSdkVerification> mapHostRuntime({
    required String hostId,
    required Map<String, dynamic> mappedNetwork,
    required int bitWidth,
  }) async {
    mapCalls += 1;
    lastMapHostId = hostId;
    return const AkidaSdkVerification(
      sdkAvailable: true,
      sdkStatus: 'deployable',
      sdkIssues: <String>[],
      state: 'mapped',
      runtimeTarget: 'hardware',
    );
  }

  @override
  Future<StudioAkidaRunResult> runInference({
    required String runtimeApiUrl,
    required String credentialRef,
    required List<double> inputs,
    required String runtimeTarget,
  }) async {
    runCalls += 1;
    lastRunInputs = inputs;
    return const StudioAkidaRunResult(
      outputs: <double>[0.0, 1.0],
      telemetry: <String, dynamic>{'fps': 123.0},
      runtimeTarget: 'hardware',
    );
  }

  @override
  Future<StudioAkidaRunResult> runHostInference({
    required String hostId,
    required List<double> inputs,
  }) async {
    runCalls += 1;
    lastRunHostId = hostId;
    lastRunInputs = inputs;
    return const StudioAkidaRunResult(
      outputs: <double>[0.0, 1.0],
      telemetry: <String, dynamic>{'fps': 123.0},
      runtimeTarget: 'hardware',
    );
  }

  @override
  Future<StudioAkidaModelJob> submitModelBundle({
    required String hostId,
    required StudioAkidaBundleArtifact bundle,
  }) async {
    lastRunHostId = hostId;
    return submittedJob!;
  }

  @override
  Future<StudioAkidaModelJob> submitBenchmark({
    required String hostId,
    required String modelId,
  }) async {
    benchmarkCalls += 1;
    lastBenchmarkModelId = modelId;
    return benchmarkJob!;
  }

  @override
  Future<StudioAkidaBundleArtifact> discoverLatestBundle(
    String workspaceFolder,
  ) async {
    discoverBundleCalls += 1;
    return latestArtifact!;
  }

  @override
  Future<StudioAkidaModelJob> fetchModelJob({
    required String hostId,
    required String jobId,
  }) async {
    final index = fetchJobCalls;
    fetchJobCalls += 1;
    return fetchedJobs[index];
  }

  @override
  Future<StudioAkidaModelPrediction> runModelSample({
    required String hostId,
    required String modelId,
    required int sampleIndex,
  }) async {
    modelSampleCalls += 1;
    lastRunHostId = hostId;
    return prediction!;
  }

  @override
  Future<StudioAkidaModelVisualization> fetchVisualization({
    required String hostId,
    required String modelId,
    required StudioAkidaVisualizationMode mode,
    required int layerIndex,
    int? sampleIndex,
  }) async {
    visualizationCalls += 1;
    lastVisualizationLayer = layerIndex;
    return StudioAkidaModelVisualization(
      modelId: modelId,
      mode: mode,
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
      layerIndex: layerIndex,
      layerName: 'Hidden',
      sampleIndex: sampleIndex,
      sampleCount: mode == StudioAkidaVisualizationMode.sample ? 1 : 8,
      available: true,
      provenance: 'akida_software_replay',
      relatedRuntimeTarget: 'hardware',
      hardwareVerified: false,
    );
  }

  @override
  Future<AkidaRuntimeUpdateJob> startHostUpdate(String hostId) async {
    lastReadinessHostId = hostId;
    return startedRuntimeUpdate!;
  }

  @override
  Future<AkidaRuntimeUpdateJob> fetchHostUpdate({
    required String hostId,
    required String jobId,
  }) async {
    final index = fetchRuntimeUpdateCalls;
    fetchRuntimeUpdateCalls += 1;
    return fetchedRuntimeUpdates[index];
  }
}

void main() {
  const exportResult = AkidaNetworkResponse(
    supportState: AkidaSupportState.exportableScaffold,
    akidaVersion: 'akida2',
    topologyVerdict: 'faithful',
    warnings: <String>[],
    rejectionReasons: <String>[],
    mappedNetwork: <String, dynamic>{'graph': 'ok'},
  );

  const selectedHost = AkidaPairedHost(
    id: 'host-1',
    displayName: 'Akida Host',
    host: '10.0.0.9',
    sshPort: 22,
    username: 'neurochip',
    runtimeApiUrl: 'http://10.0.0.9:8002',
    controlApiUrl: 'http://10.0.0.9:8091',
    authMode: AkidaHostAuthMode.password,
    credentialRef: '',
    password: '',
    hasPassword: true,
    sshKeyPath: '',
    remoteInstallRoot: '/opt/neurochip-akida-host',
    serviceUser: 'neurochip',
    hostOs: 'linux',
    pythonVersion: '3.11',
    runtimeMode: AkidaRuntimeMode.remoteSdk,
    state: AkidaPairedHostState.bootstrapping,
    lastReadinessMessage: '',
    lastVerifiedAt: '',
  );

  const readyHost = AkidaPairedHost(
    id: 'host-1',
    displayName: 'Akida Host',
    host: '10.0.0.9',
    sshPort: 22,
    username: 'neurochip',
    runtimeApiUrl: 'http://10.0.0.9:8002',
    controlApiUrl: 'http://10.0.0.9:8091',
    authMode: AkidaHostAuthMode.password,
    credentialRef: '',
    password: '',
    hasPassword: true,
    sshKeyPath: '',
    remoteInstallRoot: '/opt/neurochip-akida-host',
    serviceUser: 'neurochip',
    hostOs: 'linux',
    pythonVersion: '3.11',
    runtimeMode: AkidaRuntimeMode.remoteSdk,
    state: AkidaPairedHostState.ready,
    lastReadinessMessage: 'preflight ready',
    lastVerifiedAt: '',
  );

  test(
    'checkReadiness with a selected host only refreshes host readiness',
    () async {
      final service = _FakeStudioAkidaDeployService(
        exportResult: exportResult,
        readinessHost: readyHost,
      );
      final container = ProviderContainer(
        overrides: [
          studioAkidaDeployServiceProvider.overrideWithValue(service),
        ],
      );
      final provider = container.read(
        studioAkidaDeployControllerProvider.notifier,
      )..selectHost(selectedHost);

      await provider.checkReadiness('population lif');

      expect(service.lastValidatedSpec, isNull);
      expect(service.validateCalls, 0);
      expect(service.lastReadinessHostId, 'host-1');
      expect(provider.state.selectedHost?.state, AkidaPairedHostState.ready);
      expect(provider.state.activityMessage, 'preflight ready');
      expect(provider.state.errorMessage, isNull);
    },
  );

  test('checkReadiness without a selected host checks exportability', () async {
    final service = _FakeStudioAkidaDeployService(exportResult: exportResult);
    final container = ProviderContainer(
      overrides: [studioAkidaDeployServiceProvider.overrideWithValue(service)],
    );
    final provider = container.read(
      studioAkidaDeployControllerProvider.notifier,
    );

    await provider.checkReadiness('population lif');

    expect(service.lastValidatedSpec, 'population lif');
    expect(service.validateCalls, 1);
    expect(service.lastReadinessHostId, isNull);
    expect(provider.state.activityMessage, exportResult.supportState.label);
    expect(provider.state.errorMessage, isNull);
  });

  test(
    'deploySelectedHost generates package without runtime mapping',
    () async {
      final service = _FakeStudioAkidaDeployService(exportResult: exportResult);
      final container = ProviderContainer(
        overrides: [
          studioAkidaDeployServiceProvider.overrideWithValue(service),
        ],
      );
      final provider = container.read(
        studioAkidaDeployControllerProvider.notifier,
      )..selectHost(selectedHost);

      await provider.deploySelectedHost('population lif');

      expect(service.validateCalls, 1);
      expect(service.packageCalls, 1);
      expect(service.mapCalls, 0);
      expect(provider.state.sdkVerification, isNull);
      expect(provider.state.phase, StudioAkidaDeployPhase.completed);
      expect(provider.state.activityMessage, 'Package generated.');
    },
  );

  const unsupportedExportResult = AkidaNetworkResponse(
    supportState: AkidaSupportState.unsupported,
    akidaVersion: 'akida1',
    topologyVerdict: 'unsupported',
    warnings: <String>[],
    rejectionReasons: <String>[
      'Layer \'hidden\' has 1000 neurons; Akida maps at most 256 per neural '
          'processor.',
    ],
  );

  test(
    'deploySelectedHost surfaces the rejection instead of doing nothing',
    () async {
      // Both action buttons used to return silently when the network could not
      // be mapped, so pressing them looked like a dead button.
      final service = _FakeStudioAkidaDeployService(
        exportResult: unsupportedExportResult,
      );
      final container = ProviderContainer(
        overrides: [
          studioAkidaDeployServiceProvider.overrideWithValue(service),
        ],
      );
      final provider = container.read(
        studioAkidaDeployControllerProvider.notifier,
      )..selectHost(selectedHost);

      await provider.deploySelectedHost('population lif');

      expect(service.packageCalls, 0);
      expect(provider.state.phase, StudioAkidaDeployPhase.failed);
      expect(
        provider.state.errorMessage,
        unsupportedExportResult.rejectionReasons.first,
      );
    },
  );

  test(
    'mapSelectedHost surfaces the rejection instead of doing nothing',
    () async {
      final service = _FakeStudioAkidaDeployService(
        exportResult: unsupportedExportResult,
      );
      final container = ProviderContainer(
        overrides: [
          studioAkidaDeployServiceProvider.overrideWithValue(service),
        ],
      );
      final provider = container.read(
        studioAkidaDeployControllerProvider.notifier,
      )..selectHost(selectedHost);

      await provider.mapSelectedHost('population lif');

      expect(service.mapCalls, 0);
      expect(provider.state.phase, StudioAkidaDeployPhase.failed);
      expect(
        provider.state.errorMessage,
        unsupportedExportResult.rejectionReasons.first,
      );
    },
  );

  test('akida version defaults to the AKD1000 generation', () async {
    final service = _FakeStudioAkidaDeployService(exportResult: exportResult);
    final container = ProviderContainer(
      overrides: [studioAkidaDeployServiceProvider.overrideWithValue(service)],
    );
    final provider = container.read(
      studioAkidaDeployControllerProvider.notifier,
    );

    // The backend gate defaults to akida1; a mismatched UI default meant the
    // panel and the gate could disagree about which generation was checked.
    expect(provider.state.akidaVersion, 'akida1');
  });

  test('mapSelectedHost maps runtime and records sdk verification', () async {
    final service = _FakeStudioAkidaDeployService(exportResult: exportResult);
    final container = ProviderContainer(
      overrides: [studioAkidaDeployServiceProvider.overrideWithValue(service)],
    );
    final provider = container.read(
      studioAkidaDeployControllerProvider.notifier,
    )..selectHost(selectedHost);

    await provider.mapSelectedHost('population lif');

    expect(service.validateCalls, 1);
    expect(service.packageCalls, 0);
    expect(service.mapCalls, 1);
    expect(service.lastMapHostId, 'host-1');
    expect(service.lastMapRuntimeApiUrl, isNull);
    expect(provider.state.sdkVerification, isNotNull);
    expect(provider.state.phase, StudioAkidaDeployPhase.completed);
    expect(
      provider.state.activityMessage,
      'Mapped to physical Akida hardware.',
    );
  });

  test(
    'mapSelectedHost seeds a default run vector from mapped population size',
    () async {
      final service = _FakeStudioAkidaDeployService(
        exportResult: const AkidaNetworkResponse(
          supportState: AkidaSupportState.exportableScaffold,
          akidaVersion: 'akida2',
          topologyVerdict: 'faithful',
          warnings: <String>[],
          rejectionReasons: <String>[],
          mappedNetwork: <String, dynamic>{
            'populations': <Map<String, dynamic>>[
              <String, dynamic>{'id': 'sensor', 'size': 4},
              <String, dynamic>{'id': 'motor', 'size': 2},
            ],
          },
        ),
      );
      final container = ProviderContainer(
        overrides: [
          studioAkidaDeployServiceProvider.overrideWithValue(service),
        ],
      );
      final provider = container.read(
        studioAkidaDeployControllerProvider.notifier,
      )..selectHost(selectedHost);

      await provider.mapSelectedHost('population lif');

      expect(provider.state.runInputVectorText, '1, 0, 0, 0');
    },
  );

  test(
    'runSelectedHost parses the input vector and stores run result',
    () async {
      final service = _FakeStudioAkidaDeployService(exportResult: exportResult);
      final container = ProviderContainer(
        overrides: [
          studioAkidaDeployServiceProvider.overrideWithValue(service),
        ],
      );
      final provider = container.read(
        studioAkidaDeployControllerProvider.notifier,
      )..selectHost(selectedHost);

      await provider.mapSelectedHost('population lif');
      provider.setRunInputVectorText('1, 0, 1');

      await provider.runSelectedHost();

      expect(service.runCalls, 1);
      expect(service.lastRunHostId, 'host-1');
      expect(service.lastRunInputs, <double>[1, 0, 1]);
      expect(provider.state.runResult, isNotNull);
      expect(provider.state.phase, StudioAkidaDeployPhase.completed);
      expect(
        provider.state.activityMessage,
        'Run completed on physical Akida hardware.',
      );
    },
  );

  test('bundle artifact and job JSON preserve the public contract', () {
    final artifact = StudioAkidaBundleArtifact.fromJson(const <String, dynamic>{
      'filename': 'mnist.akida-bundle.zip',
      'bundle_base64': 'UEs=',
      'sha256': 'abc',
    });
    final job = StudioAkidaModelJob.fromJson(const <String, dynamic>{
      'jobId': 'job-1',
      'stage': 'evaluation',
      'progress': 80,
      'message': 'Evaluating bundled samples.',
      'modelId': 'model-1',
      'runtimeTarget': 'hardware',
      'hardwareVerified': true,
      'metrics': <String, dynamic>{'pytorch_accuracy': 0.99},
    });

    expect(artifact.filename, 'mnist.akida-bundle.zip');
    expect(job.stage, 'evaluation');
    expect(job.metrics['pytorch_accuracy'], 0.99);
    expect(job.isTerminal, isFalse);
  });

  test('latest bundle discovery automatically submits the artifact', () async {
    const artifact = StudioAkidaBundleArtifact(
      filename: 'mnist.akida-bundle.zip',
      bundleBase64: 'UEs=',
      sha256: 'abc',
    );
    const completed = StudioAkidaModelJob(
      jobId: 'job-1',
      stage: 'completed',
      progress: 100,
      message: 'Done',
      modelId: 'model-1',
      runtimeTarget: 'hardware',
      hardwareVerified: true,
      metrics: <String, double>{},
    );
    final service = _FakeStudioAkidaDeployService(
      exportResult: exportResult,
      latestArtifact: artifact,
      submittedJob: completed,
    );
    final container = ProviderContainer(
      overrides: [studioAkidaDeployServiceProvider.overrideWithValue(service)],
    );
    addTearDown(container.dispose);
    final provider = container.read(
      studioAkidaDeployControllerProvider.notifier,
    )..selectHost(selectedHost);

    await provider.discoverAndSubmitBundle('workspace/notebooks');

    expect(service.discoverBundleCalls, 1);
    expect(provider.state.bundleArtifact, artifact);
    expect(provider.state.deploymentJob?.jobId, 'job-1');
    expect(provider.state.phase, StudioAkidaDeployPhase.completed);
  });

  test('model job polling surfaces typed progress phases', () async {
    const validating = StudioAkidaModelJob(
      jobId: 'job-1',
      stage: 'validation',
      progress: 0,
      message: 'Validating',
      runtimeTarget: 'unknown',
      hardwareVerified: false,
      metrics: <String, double>{},
    );
    const converting = StudioAkidaModelJob(
      jobId: 'job-1',
      stage: 'conversion',
      progress: 45,
      message: 'Converting',
      runtimeTarget: 'unknown',
      hardwareVerified: false,
      metrics: <String, double>{},
    );
    const completed = StudioAkidaModelJob(
      jobId: 'job-1',
      stage: 'completed',
      progress: 100,
      message: 'Done',
      modelId: 'model-1',
      runtimeTarget: 'hardware',
      hardwareVerified: true,
      metrics: <String, double>{},
    );
    final service = _FakeStudioAkidaDeployService(
      exportResult: exportResult,
      submittedJob: validating,
      fetchedJobs: const <StudioAkidaModelJob>[converting, completed],
    );
    final container = ProviderContainer(
      overrides: [studioAkidaDeployServiceProvider.overrideWithValue(service)],
    );
    addTearDown(container.dispose);
    final phases = <StudioAkidaDeployPhase>[];
    container.listen(
      studioAkidaDeployControllerProvider,
      (_, next) => phases.add(next.phase),
    );
    final provider = container.read(
      studioAkidaDeployControllerProvider.notifier,
    )..selectHost(selectedHost);

    await provider.submitBundle(
      const StudioAkidaBundleArtifact(
        filename: 'mnist.akida-bundle.zip',
        bundleBase64: 'UEs=',
        sha256: 'abc',
      ),
    );

    expect(phases, contains(StudioAkidaDeployPhase.validating));
    expect(phases, contains(StudioAkidaDeployPhase.converting));
    expect(phases.last, StudioAkidaDeployPhase.completed);
    expect(service.fetchJobCalls, 2);
  });

  group('Run Benchmark', () {
    const deployedJob = StudioAkidaModelJob(
      jobId: 'job-1',
      stage: 'completed',
      progress: 100,
      message: 'Done',
      modelId: 'model-1',
      runtimeTarget: 'hardware',
      hardwareVerified: true,
      metrics: <String, double>{'akida_accuracy': 0.97},
      totalSamples: 2000,
    );

    Future<StudioAkidaDeployController> deployed(
      _FakeStudioAkidaDeployService service,
    ) async {
      final container = ProviderContainer(
        overrides: [
          studioAkidaDeployServiceProvider.overrideWithValue(service),
        ],
      );
      addTearDown(container.dispose);
      // The controller is autoDispose, and runBenchmark polls across a 1s gap.
      // Without a live subscription it is torn down mid-poll and `state` throws.
      container.listen(studioAkidaDeployControllerProvider, (_, _) {});
      final provider = container.read(
        studioAkidaDeployControllerProvider.notifier,
      )..selectHost(selectedHost);
      await provider.submitBundle(
        const StudioAkidaBundleArtifact(
          filename: 'mnist.akida-bundle.zip',
          bundleBase64: 'UEs=',
          sha256: 'abc',
        ),
      );
      return provider;
    }

    test('polls to terminal and keeps the measured metrics', () async {
      const running = StudioAkidaModelJob(
        jobId: 'bench-1',
        stage: 'evaluation',
        progress: 0,
        message: 'Benchmarking 2000 samples.',
        modelId: 'model-1',
        runtimeTarget: 'hardware',
        hardwareVerified: true,
        metrics: <String, double>{},
      );
      const finished = StudioAkidaModelJob(
        jobId: 'bench-1',
        stage: 'completed',
        progress: 100,
        message: 'Benchmarked 2000 samples on model-1.',
        modelId: 'model-1',
        runtimeTarget: 'hardware',
        hardwareVerified: true,
        metrics: <String, double>{
          'akida_accuracy': 0.965,
          'latency_ms': 1.42,
          'fps': 704.2,
          'total_samples': 2000,
        },
        totalSamples: 2000,
        classResults: <StudioAkidaClassResult>[
          StudioAkidaClassResult(
            label: 0,
            labelName: 'zero',
            support: 200,
            correct: 198,
          ),
        ],
      );
      final service = _FakeStudioAkidaDeployService(
        exportResult: exportResult,
        submittedJob: deployedJob,
        benchmarkJob: running,
        fetchedJobs: const <StudioAkidaModelJob>[finished],
      );
      final provider = await deployed(service);

      await provider.runBenchmark();

      expect(service.benchmarkCalls, 1);
      expect(service.lastBenchmarkModelId, 'model-1');
      expect(provider.state.phase, StudioAkidaDeployPhase.completed);
      expect(provider.state.benchmarkResult?.job.metrics['latency_ms'], 1.42);
      expect(provider.state.benchmarkResult?.job.classResults, isNotNull);
      expect(service.visualizationCalls, 1);
      expect(
        provider.state.visualizationResult?.mode,
        StudioAkidaVisualizationMode.benchmark,
      );
      expect(provider.state.errorMessage, isNull);
    });

    test('a failed benchmark surfaces the host error code', () async {
      const running = StudioAkidaModelJob(
        jobId: 'bench-2',
        stage: 'evaluation',
        progress: 0,
        message: 'Benchmarking.',
        modelId: 'model-1',
        runtimeTarget: 'hardware',
        hardwareVerified: true,
        metrics: <String, double>{},
      );
      const failed = StudioAkidaModelJob(
        jobId: 'bench-2',
        stage: 'failed',
        progress: 100,
        message: 'The benchmark run failed on the host.',
        modelId: 'model-1',
        runtimeTarget: 'hardware',
        hardwareVerified: false,
        metrics: <String, double>{},
        errorCode: 'AKIDA_BENCHMARK_FAILED',
      );
      final service = _FakeStudioAkidaDeployService(
        exportResult: exportResult,
        submittedJob: deployedJob,
        benchmarkJob: running,
        fetchedJobs: const <StudioAkidaModelJob>[failed],
      );
      final provider = await deployed(service);

      await provider.runBenchmark();

      expect(provider.state.phase, StudioAkidaDeployPhase.failed);
      // errorCode used to be parsed and never rendered anywhere.
      expect(provider.state.errorMessage, contains('AKIDA_BENCHMARK_FAILED'));
    });

    test('a failed retry keeps the last successful benchmark', () async {
      const running = StudioAkidaModelJob(
        jobId: 'bench-retry',
        stage: 'evaluation',
        progress: 0,
        message: 'Benchmarking.',
        modelId: 'model-1',
        runtimeTarget: 'hardware',
        hardwareVerified: true,
        metrics: <String, double>{},
      );
      const finished = StudioAkidaModelJob(
        jobId: 'bench-retry',
        stage: 'completed',
        progress: 100,
        message: 'Benchmark complete.',
        modelId: 'model-1',
        runtimeTarget: 'hardware',
        hardwareVerified: true,
        metrics: <String, double>{'latency_ms': 1.25},
      );
      const failed = StudioAkidaModelJob(
        jobId: 'bench-retry',
        stage: 'failed',
        progress: 100,
        message: 'Retry failed.',
        modelId: 'model-1',
        runtimeTarget: 'hardware',
        hardwareVerified: false,
        metrics: <String, double>{},
        errorCode: 'AKIDA_BENCHMARK_FAILED',
      );
      final service = _FakeStudioAkidaDeployService(
        exportResult: exportResult,
        submittedJob: deployedJob,
        benchmarkJob: running,
        fetchedJobs: const <StudioAkidaModelJob>[finished, failed],
      );
      final provider = await deployed(service);

      await provider.runBenchmark();
      final successful = provider.state.benchmarkResult;
      await provider.runBenchmark();

      expect(successful?.job.metrics['latency_ms'], 1.25);
      expect(provider.state.benchmarkResult, same(successful));
      expect(provider.state.phase, StudioAkidaDeployPhase.failed);
    });

    test('deploying a different bundle invalidates prior results', () async {
      const running = StudioAkidaModelJob(
        jobId: 'bench-1',
        stage: 'evaluation',
        progress: 0,
        message: 'Benchmarking.',
        modelId: 'model-1',
        runtimeTarget: 'hardware',
        hardwareVerified: true,
        metrics: <String, double>{},
      );
      const finished = StudioAkidaModelJob(
        jobId: 'bench-1',
        stage: 'completed',
        progress: 100,
        message: 'Benchmark complete.',
        modelId: 'model-1',
        runtimeTarget: 'hardware',
        hardwareVerified: true,
        metrics: <String, double>{'latency_ms': 1.25},
      );
      final service = _FakeStudioAkidaDeployService(
        exportResult: exportResult,
        submittedJob: deployedJob,
        benchmarkJob: running,
        fetchedJobs: const <StudioAkidaModelJob>[finished],
      );
      final provider = await deployed(service);
      await provider.runBenchmark();

      await provider.submitBundle(
        const StudioAkidaBundleArtifact(
          filename: 'updated.akida-bundle.zip',
          bundleBase64: 'UEs-new=',
          sha256: 'different-sha',
        ),
      );

      expect(provider.state.benchmarkResult, isNull);
      expect(provider.state.sampleResult, isNull);
      expect(provider.state.latestResultKind, isNull);
    });

    test('refuses to benchmark before a model is deployed', () async {
      final service = _FakeStudioAkidaDeployService(exportResult: exportResult);
      final container = ProviderContainer(
        overrides: [
          studioAkidaDeployServiceProvider.overrideWithValue(service),
        ],
      );
      addTearDown(container.dispose);
      final provider = container.read(
        studioAkidaDeployControllerProvider.notifier,
      )..selectHost(selectedHost);

      await provider.runBenchmark();

      expect(service.benchmarkCalls, 0);
      expect(provider.state.errorMessage, isNotNull);
    });
  });

  test('completed physical model job enables sample prediction', () async {
    const job = StudioAkidaModelJob(
      jobId: 'job-1',
      stage: 'completed',
      progress: 100,
      message: 'Done',
      modelId: 'model-1',
      runtimeTarget: 'hardware',
      hardwareVerified: true,
      metrics: <String, double>{'akida_accuracy': 0.97},
    );
    const prediction = StudioAkidaModelPrediction(
      sampleIndex: 42,
      prediction: 7,
      label: 7,
      labelName: '7',
      outputs: <double>[0, 1],
      runtimeTarget: 'hardware',
      hardwareVerified: true,
      telemetry: <String, dynamic>{'fps': 123},
    );
    final service = _FakeStudioAkidaDeployService(
      exportResult: exportResult,
      submittedJob: job,
      prediction: prediction,
    );
    final container = ProviderContainer(
      overrides: [studioAkidaDeployServiceProvider.overrideWithValue(service)],
    );
    addTearDown(container.dispose);
    final provider = container.read(
      studioAkidaDeployControllerProvider.notifier,
    )..selectHost(selectedHost);

    await provider.submitBundle(
      const StudioAkidaBundleArtifact(
        filename: 'mnist.akida-bundle.zip',
        bundleBase64: 'UEs=',
        sha256: 'abc',
      ),
    );
    provider.setSampleIndex(42);
    await provider.runModelSample();

    expect(provider.state.deploymentJob?.hardwareVerified, isTrue);
    expect(provider.state.sampleResult?.prediction.prediction, 7);
    expect(service.modelSampleCalls, 1);
    expect(service.visualizationCalls, 1);
    expect(
      provider.state.visualizationResult?.provenance,
      'akida_software_replay',
    );
    expect(provider.state.visualizationResult?.hardwareVerified, isFalse);
  });

  test(
    'simulator completion never enables the hardware verified path',
    () async {
      const simulatorJob = StudioAkidaModelJob(
        jobId: 'job-1',
        stage: 'completed',
        progress: 100,
        message: 'Done',
        modelId: 'model-1',
        runtimeTarget: 'akd1000_simulator',
        hardwareVerified: false,
        metrics: <String, double>{'akida_accuracy': 0.97},
      );
      final service = _FakeStudioAkidaDeployService(
        exportResult: exportResult,
        submittedJob: simulatorJob,
      );
      final container = ProviderContainer(
        overrides: [
          studioAkidaDeployServiceProvider.overrideWithValue(service),
        ],
      );
      addTearDown(container.dispose);
      final provider = container.read(
        studioAkidaDeployControllerProvider.notifier,
      )..selectHost(selectedHost);

      await provider.submitBundle(
        const StudioAkidaBundleArtifact(
          filename: 'mnist.akida-bundle.zip',
          bundleBase64: 'UEs=',
          sha256: 'abc',
        ),
      );
      await provider.runModelSample();

      expect(provider.state.activityMessage, contains('not verified'));
      expect(provider.state.errorMessage, contains('physical-hardware'));
      expect(service.modelSampleCalls, 0);
    },
  );

  test('Install uses the asynchronous updater and exposes progress', () async {
    const queued = AkidaRuntimeUpdateJob(
      jobId: 'runtime-job',
      hostId: 'host-1',
      artifactVersion: '0.6.0',
      artifactSha256: 'abc',
      stage: 'queued',
      progress: 0,
      message: 'Queued',
      status: 'queued',
    );
    const completed = AkidaRuntimeUpdateJob(
      jobId: 'runtime-job',
      hostId: 'host-1',
      artifactVersion: '0.6.0',
      artifactSha256: 'abc',
      stage: 'completed',
      progress: 100,
      message: 'Ready',
      status: 'completed',
      installedVersion: '0.6.0',
      installMode: 'systemd',
    );
    final service = _FakeStudioAkidaDeployService(
      exportResult: exportResult,
      readinessHost: readyHost,
      startedRuntimeUpdate: queued,
      fetchedRuntimeUpdates: const <AkidaRuntimeUpdateJob>[completed],
    );
    final container = ProviderContainer(
      overrides: [studioAkidaDeployServiceProvider.overrideWithValue(service)],
    );
    addTearDown(container.dispose);
    final progress = <int>[];
    container.listen(studioAkidaDeployControllerProvider, (_, next) {
      final value = next.runtimeUpdateJob?.progress;
      if (value != null) progress.add(value);
    });
    final provider = container.read(
      studioAkidaDeployControllerProvider.notifier,
    )..selectHost(selectedHost);

    await provider.installSelectedHost();

    expect(service.lastReadinessHostId, 'host-1');
    expect(service.fetchRuntimeUpdateCalls, 1);
    expect(progress, containsAll(<int>[0, 100]));
    expect(provider.state.runtimeUpdateJob?.isCompleted, isTrue);
    expect(provider.state.selectedHost?.state, AkidaPairedHostState.ready);
    expect(provider.state.activityMessage, contains('0.6.0'));
  });
}
