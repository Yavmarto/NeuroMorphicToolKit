import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

import 'package:neuro_toolkit/features/neurocnl/providers/api_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/studio_result_session_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/services/studio_akida_deploy_service.dart';

part 'studio_akida_deploy_provider.g.dart';

enum StudioAkidaDeployPhase {
  idle,
  validating,
  installing,
  packaging,
  mapping,
  quantizing,
  converting,
  evaluating,
  running,
  completed,
  failed,
}

enum StudioAkidaResultKind { sample, benchmark }

class StudioAkidaResultProvenance {
  const StudioAkidaResultProvenance({
    required this.hostId,
    required this.modelId,
    required this.runtimeTarget,
    required this.hardwareVerified,
    this.sourceSnapshotId,
  });

  final String hostId;
  final String modelId;
  final String runtimeTarget;
  final bool hardwareVerified;
  final String? sourceSnapshotId;
}

class StudioAkidaSampleSnapshot {
  const StudioAkidaSampleSnapshot({
    required this.provenance,
    required this.prediction,
  });

  final StudioAkidaResultProvenance provenance;
  final StudioAkidaModelPrediction prediction;
}

class StudioAkidaBenchmarkSnapshot {
  const StudioAkidaBenchmarkSnapshot({
    required this.provenance,
    required this.job,
  });

  final StudioAkidaResultProvenance provenance;
  final StudioAkidaModelJob job;
}

/// Immutable state for [StudioAkidaDeployController].
class StudioAkidaDeployState {
  const StudioAkidaDeployState({
    this.phase = StudioAkidaDeployPhase.idle,
    this.selectedHost,
    this.exportResult,
    this.sdkVerification,
    this.runResult,
    this.bundleArtifact,
    this.deploymentJob,
    this.deployedSourceSnapshotId,
    this.operationJob,
    this.runtimeUpdateJob,
    this.sampleResult,
    this.benchmarkResult,
    this.latestResultKind,
    this.visualizationResult,
    this.visualizationError,
    this.isLoadingVisualization = false,
    this.sampleIndex = 0,
    this.bitWidth = 4,
    // AKD1000 is an Akida 1 part, and it is the only board this toolkit
    // targets. Defaulting to akida2 disagreed with the backend's own akida1
    // default, so the panel and the gate could report different verdicts.
    this.akidaVersion = 'akida1',
    this.activityMessage,
    this.errorMessage,
    this.runInputVectorText = '',
  });

  final StudioAkidaDeployPhase phase;
  final AkidaPairedHost? selectedHost;
  final AkidaNetworkResponse? exportResult;
  final AkidaSdkVerification? sdkVerification;
  final StudioAkidaRunResult? runResult;
  final StudioAkidaBundleArtifact? bundleArtifact;
  final StudioAkidaModelJob? deploymentJob;
  final String? deployedSourceSnapshotId;

  /// Current conversion or benchmark operation. A failed retry never replaces
  /// [deploymentJob], [sampleResult], or [benchmarkResult].
  final StudioAkidaModelJob? operationJob;
  final AkidaRuntimeUpdateJob? runtimeUpdateJob;
  final StudioAkidaSampleSnapshot? sampleResult;
  final StudioAkidaBenchmarkSnapshot? benchmarkResult;
  final StudioAkidaResultKind? latestResultKind;
  final StudioAkidaModelVisualization? visualizationResult;
  final String? visualizationError;
  final bool isLoadingVisualization;
  final int sampleIndex;
  final int bitWidth;
  final String akidaVersion;
  final String? activityMessage;
  final String? errorMessage;
  final String runInputVectorText;

  bool get isBusy =>
      phase == StudioAkidaDeployPhase.validating ||
      phase == StudioAkidaDeployPhase.installing ||
      phase == StudioAkidaDeployPhase.packaging ||
      phase == StudioAkidaDeployPhase.mapping ||
      phase == StudioAkidaDeployPhase.quantizing ||
      phase == StudioAkidaDeployPhase.converting ||
      phase == StudioAkidaDeployPhase.evaluating ||
      phase == StudioAkidaDeployPhase.running;

  /// True while a sample or benchmark run is in flight, as opposed to a
  /// deploy-side operation (packaging, mapping, converting…). The two report
  /// their progress next to different buttons, in different panes.
  bool get isRunning =>
      phase == StudioAkidaDeployPhase.evaluating ||
      phase == StudioAkidaDeployPhase.running;

  /// Provenance of the most recent result, whichever kind produced it.
  StudioAkidaResultProvenance? get latestProvenance =>
      switch (latestResultKind) {
        StudioAkidaResultKind.sample => sampleResult?.provenance,
        StudioAkidaResultKind.benchmark => benchmarkResult?.provenance,
        null => null,
      };

  /// Did the most recent result actually touch physical silicon?
  ///
  /// Result provenance wins over the deployment job's flag: the two can
  /// disagree, and the result is the more specific claim. Everything that
  /// states this fact reads it from here, so the UI cannot claim verified
  /// hardware in one banner and separate runtime reporting in another.
  bool get hardwareVerified =>
      latestProvenance?.hardwareVerified ??
      deploymentJob?.hardwareVerified ??
      false;

  StudioAkidaDeployState copyWith({
    StudioAkidaDeployPhase? phase,
    AkidaPairedHost? selectedHost,
    bool clearSelectedHost = false,
    AkidaNetworkResponse? exportResult,
    bool clearExportResult = false,
    AkidaSdkVerification? sdkVerification,
    bool clearSdkVerification = false,
    StudioAkidaRunResult? runResult,
    bool clearRunResult = false,
    StudioAkidaBundleArtifact? bundleArtifact,
    bool clearBundleArtifact = false,
    StudioAkidaModelJob? deploymentJob,
    bool clearDeploymentJob = false,
    String? deployedSourceSnapshotId,
    bool clearDeployedSourceSnapshotId = false,
    StudioAkidaModelJob? operationJob,
    bool clearOperationJob = false,
    AkidaRuntimeUpdateJob? runtimeUpdateJob,
    bool clearRuntimeUpdateJob = false,
    StudioAkidaSampleSnapshot? sampleResult,
    bool clearSampleResult = false,
    StudioAkidaBenchmarkSnapshot? benchmarkResult,
    bool clearBenchmarkResult = false,
    StudioAkidaResultKind? latestResultKind,
    bool clearLatestResultKind = false,
    StudioAkidaModelVisualization? visualizationResult,
    bool clearVisualizationResult = false,
    String? visualizationError,
    bool clearVisualizationError = false,
    bool? isLoadingVisualization,
    int? sampleIndex,
    int? bitWidth,
    String? akidaVersion,
    String? activityMessage,
    bool clearActivityMessage = false,
    String? errorMessage,
    bool clearErrorMessage = false,
    String? runInputVectorText,
  }) {
    return StudioAkidaDeployState(
      phase: phase ?? this.phase,
      selectedHost: clearSelectedHost
          ? null
          : (selectedHost ?? this.selectedHost),
      exportResult: clearExportResult
          ? null
          : (exportResult ?? this.exportResult),
      sdkVerification: clearSdkVerification
          ? null
          : (sdkVerification ?? this.sdkVerification),
      runResult: clearRunResult ? null : (runResult ?? this.runResult),
      bundleArtifact: clearBundleArtifact
          ? null
          : (bundleArtifact ?? this.bundleArtifact),
      deploymentJob: clearDeploymentJob
          ? null
          : (deploymentJob ?? this.deploymentJob),
      deployedSourceSnapshotId: clearDeployedSourceSnapshotId
          ? null
          : (deployedSourceSnapshotId ?? this.deployedSourceSnapshotId),
      operationJob: clearOperationJob
          ? null
          : (operationJob ?? this.operationJob),
      runtimeUpdateJob: clearRuntimeUpdateJob
          ? null
          : (runtimeUpdateJob ?? this.runtimeUpdateJob),
      sampleResult: clearSampleResult
          ? null
          : (sampleResult ?? this.sampleResult),
      benchmarkResult: clearBenchmarkResult
          ? null
          : (benchmarkResult ?? this.benchmarkResult),
      latestResultKind: clearLatestResultKind
          ? null
          : (latestResultKind ?? this.latestResultKind),
      visualizationResult: clearVisualizationResult
          ? null
          : (visualizationResult ?? this.visualizationResult),
      visualizationError: clearVisualizationError
          ? null
          : (visualizationError ?? this.visualizationError),
      isLoadingVisualization:
          isLoadingVisualization ?? this.isLoadingVisualization,
      sampleIndex: sampleIndex ?? this.sampleIndex,
      bitWidth: bitWidth ?? this.bitWidth,
      akidaVersion: akidaVersion ?? this.akidaVersion,
      activityMessage: clearActivityMessage
          ? null
          : (activityMessage ?? this.activityMessage),
      errorMessage: clearErrorMessage
          ? null
          : (errorMessage ?? this.errorMessage),
      runInputVectorText: runInputVectorText ?? this.runInputVectorText,
    );
  }
}

@riverpod
class StudioAkidaDeployController extends _$StudioAkidaDeployController {
  StudioAkidaDeployService get _service =>
      ref.read(studioAkidaDeployServiceProvider);

  @override
  StudioAkidaDeployState build() => const StudioAkidaDeployState();

  void _fail(Object error) {
    if (!ref.mounted) return;
    state = state.copyWith(
      phase: StudioAkidaDeployPhase.failed,
      errorMessage: error.toString(),
    );
  }

  void selectHost(AkidaPairedHost? host) {
    final changed = host?.id != state.selectedHost?.id;
    state = state.copyWith(
      selectedHost: host,
      clearSelectedHost: host == null,
      clearSdkVerification: true,
      clearRunResult: true,
      clearDeploymentJob: changed,
      clearDeployedSourceSnapshotId: changed,
      clearOperationJob: changed,
      clearSampleResult: changed,
      clearBenchmarkResult: changed,
      clearLatestResultKind: changed,
      clearVisualizationResult: changed,
      clearVisualizationError: changed,
      runInputVectorText: '',
      clearActivityMessage: true,
      clearErrorMessage: true,
    );
  }

  void setBitWidth(int bitWidth) {
    state = state.copyWith(
      bitWidth: bitWidth,
      clearExportResult: true,
      clearSdkVerification: true,
      clearRunResult: true,
      runInputVectorText: '',
    );
  }

  void setAkidaVersion(String version) {
    state = state.copyWith(
      akidaVersion: version,
      clearExportResult: true,
      clearSdkVerification: true,
      clearRunResult: true,
      runInputVectorText: '',
    );
  }

  void setRunInputVectorText(String value) {
    state = state.copyWith(runInputVectorText: value);
  }

  void setSampleIndex(int value) {
    state = state.copyWith(sampleIndex: value);
  }

  void selectBundle(StudioAkidaBundleArtifact artifact) {
    final changed = artifact.sha256 != state.bundleArtifact?.sha256;
    state = state.copyWith(
      phase: StudioAkidaDeployPhase.idle,
      bundleArtifact: artifact,
      clearDeploymentJob: changed,
      clearDeployedSourceSnapshotId: changed,
      clearOperationJob: changed,
      clearSampleResult: changed,
      clearBenchmarkResult: changed,
      clearLatestResultKind: changed,
      clearVisualizationResult: changed,
      clearVisualizationError: changed,
      activityMessage: 'Selected ${artifact.filename}.',
      clearErrorMessage: true,
    );
  }

  Future<String?> createMnistCompanion(String workspacePath) async {
    state = state.copyWith(
      activityMessage: 'Creating the full-MNIST Akida companion notebook.',
      clearErrorMessage: true,
    );
    try {
      final url = await _service.createMnistCompanion(workspacePath);
      if (!ref.mounted) return null;
      state = state.copyWith(
        activityMessage:
            'Companion notebook ready. Run all cells to create the bundle.',
      );
      return url;
    } catch (error) {
      _fail(error);
      return null;
    }
  }

  /// Surfaces a client-side rejection (e.g. a wrong filename) in the same place
  /// host-side failures appear, so the user reads one status line either way.
  void reportBundleRejected(String message) {
    state = state.copyWith(
      phase: StudioAkidaDeployPhase.failed,
      errorMessage: message,
    );
  }

  Future<void> discoverLatestBundle(String workspaceFolder) async {
    // Announce the lookup before awaiting it. Without this the button set no
    // phase and no message until the request came back, so a slow or failing
    // discovery was indistinguishable from a click that did nothing at all.
    state = state.copyWith(
      phase: StudioAkidaDeployPhase.validating,
      activityMessage: 'Looking for the latest bundle in $workspaceFolder…',
      clearErrorMessage: true,
    );
    try {
      final artifact = await _service.discoverLatestBundle(workspaceFolder);
      if (!ref.mounted) return;
      final changed = artifact.sha256 != state.bundleArtifact?.sha256;
      state = state.copyWith(
        phase: StudioAkidaDeployPhase.idle,
        bundleArtifact: artifact,
        clearDeploymentJob: changed,
        clearDeployedSourceSnapshotId: changed,
        clearOperationJob: changed,
        clearSampleResult: changed,
        clearBenchmarkResult: changed,
        clearLatestResultKind: changed,
        clearVisualizationResult: changed,
        clearVisualizationError: changed,
        activityMessage: 'Latest bundle ready: ${artifact.filename}.',
      );
    } catch (error) {
      _fail(error);
    }
  }

  Future<void> discoverAndSubmitBundle(String workspaceFolder) async {
    await discoverLatestBundle(workspaceFolder);
    if (!ref.mounted) return;
    final artifact = state.bundleArtifact;
    if (artifact != null && state.errorMessage == null) {
      await submitBundle(artifact);
    }
  }

  Future<void> submitBundle(StudioAkidaBundleArtifact artifact) async {
    final host = state.selectedHost;
    if (host == null) {
      state = state.copyWith(
        errorMessage: 'Select or create an Akida host first.',
      );
      return;
    }
    final changed = artifact.sha256 != state.bundleArtifact?.sha256;
    final sourceSnapshotId = ref
        .read(studioResultSessionProvider)
        .persistableSnapshot
        ?.id;
    state = state.copyWith(
      phase: StudioAkidaDeployPhase.validating,
      bundleArtifact: artifact,
      clearDeploymentJob: changed,
      clearDeployedSourceSnapshotId: changed,
      clearSampleResult: changed,
      clearBenchmarkResult: changed,
      clearLatestResultKind: changed,
      clearVisualizationResult: changed,
      clearVisualizationError: changed,
      activityMessage: 'Validating ${artifact.filename}.',
      clearErrorMessage: true,
    );
    try {
      var job = await _service.submitModelBundle(
        hostId: host.id,
        bundle: artifact,
      );
      while (!job.isTerminal) {
        if (!ref.mounted) return;
        state = state.copyWith(
          phase: _phaseForModelStage(job.stage),
          operationJob: job,
          activityMessage: job.message,
        );
        await Future<void>.delayed(const Duration(seconds: 1));
        job = await _service.fetchModelJob(hostId: host.id, jobId: job.jobId);
      }
      if (!ref.mounted) return;
      if (job.stage == 'failed') {
        state = state.copyWith(
          phase: StudioAkidaDeployPhase.failed,
          operationJob: job,
          errorMessage: job.message,
        );
        return;
      }
      state = state.copyWith(
        phase: StudioAkidaDeployPhase.completed,
        deploymentJob: job,
        deployedSourceSnapshotId: sourceSnapshotId,
        operationJob: job,
        clearSampleResult: true,
        clearBenchmarkResult: true,
        clearLatestResultKind: true,
        clearVisualizationResult: true,
        clearVisualizationError: true,
        activityMessage: job.hardwareVerified
            ? 'Hardware verified on ${job.deviceInfo ?? 'physical Akida'}.'
            : 'Conversion completed in simulator mode; hardware is not verified.',
      );
    } catch (error) {
      _fail(error);
    }
  }

  StudioAkidaDeployPhase _phaseForModelStage(String stage) {
    return switch (stage) {
      'validation' => StudioAkidaDeployPhase.validating,
      'quantization' => StudioAkidaDeployPhase.quantizing,
      'conversion' => StudioAkidaDeployPhase.converting,
      'mapping' => StudioAkidaDeployPhase.mapping,
      'evaluation' => StudioAkidaDeployPhase.evaluating,
      'completed' => StudioAkidaDeployPhase.completed,
      _ => StudioAkidaDeployPhase.failed,
    };
  }

  Future<void> runModelSample() async {
    final host = state.selectedHost;
    final job = state.deploymentJob;
    if (host == null || job?.modelId == null || job?.hardwareVerified != true) {
      state = state.copyWith(
        errorMessage:
            'Complete physical-hardware conversion before sample inference.',
      );
      return;
    }
    state = state.copyWith(
      phase: StudioAkidaDeployPhase.running,
      activityMessage:
          'Running sample ${state.sampleIndex} on physical Akida hardware.',
      clearErrorMessage: true,
      clearVisualizationResult: true,
      clearVisualizationError: true,
    );
    try {
      final prediction = await _service.runModelSample(
        hostId: host.id,
        modelId: job!.modelId!,
        sampleIndex: state.sampleIndex,
      );
      if (!ref.mounted) return;
      state = state.copyWith(
        phase: StudioAkidaDeployPhase.completed,
        sampleResult: StudioAkidaSampleSnapshot(
          provenance: StudioAkidaResultProvenance(
            hostId: host.id,
            modelId: job.modelId!,
            runtimeTarget: prediction.runtimeTarget,
            hardwareVerified: prediction.hardwareVerified,
            sourceSnapshotId: state.deployedSourceSnapshotId,
          ),
          prediction: prediction,
        ),
        latestResultKind: StudioAkidaResultKind.sample,
        activityMessage: 'Physical inference completed.',
      );
      await _loadVisualization(
        hostId: host.id,
        modelId: job.modelId!,
        mode: StudioAkidaVisualizationMode.sample,
        sampleIndex: state.sampleIndex,
      );
    } catch (error) {
      _fail(error);
    }
  }

  /// Re-score the whole bundled evaluation set on the card, with timing.
  ///
  /// Re-submitting the bundle cannot do this: the host dedupes on the bundle
  /// checksum and hands back the original job. This drives the dedicated
  /// benchmark job instead, reusing the same poll loop as conversion.
  Future<void> runBenchmark() async {
    final host = state.selectedHost;
    final job = state.deploymentJob;
    if (host == null || job?.modelId == null) {
      state = state.copyWith(
        errorMessage: 'Deploy a model bundle before running a benchmark.',
      );
      return;
    }
    state = state.copyWith(
      phase: StudioAkidaDeployPhase.evaluating,
      activityMessage: job!.hardwareVerified
          ? 'Benchmarking the full evaluation set on the card.'
          : 'Benchmarking the full evaluation set in the Akida simulator.',
      clearErrorMessage: true,
      clearVisualizationResult: true,
      clearVisualizationError: true,
    );
    try {
      var benchmark = await _service.submitBenchmark(
        hostId: host.id,
        modelId: job.modelId!,
      );
      while (!benchmark.isTerminal) {
        if (!ref.mounted) return;
        state = state.copyWith(
          operationJob: benchmark,
          activityMessage: benchmark.message,
        );
        await Future<void>.delayed(const Duration(seconds: 1));
        benchmark = await _service.fetchModelJob(
          hostId: host.id,
          jobId: benchmark.jobId,
        );
      }
      if (!ref.mounted) return;
      if (benchmark.stage == 'failed') {
        state = state.copyWith(
          phase: StudioAkidaDeployPhase.failed,
          operationJob: benchmark,
          // errorCode is the actionable half of a host failure and was never
          // shown anywhere before.
          errorMessage: benchmark.errorCode == null
              ? benchmark.message
              : '${benchmark.message} (${benchmark.errorCode})',
        );
        return;
      }
      state = state.copyWith(
        phase: StudioAkidaDeployPhase.completed,
        operationJob: benchmark,
        benchmarkResult: StudioAkidaBenchmarkSnapshot(
          provenance: StudioAkidaResultProvenance(
            hostId: host.id,
            modelId: job.modelId!,
            runtimeTarget: benchmark.runtimeTarget,
            hardwareVerified: benchmark.hardwareVerified,
            sourceSnapshotId: state.deployedSourceSnapshotId,
          ),
          job: benchmark,
        ),
        latestResultKind: StudioAkidaResultKind.benchmark,
        activityMessage: benchmark.message,
      );
      await _loadVisualization(
        hostId: host.id,
        modelId: job.modelId!,
        mode: StudioAkidaVisualizationMode.benchmark,
      );
    } catch (error) {
      _fail(error);
    }
  }

  Future<void> selectVisualizationLayer(int layerIndex) async {
    final host = state.selectedHost;
    final job = state.deploymentJob;
    final kind = state.latestResultKind;
    if (host == null || job?.modelId == null || kind == null) return;
    await _loadVisualization(
      hostId: host.id,
      modelId: job!.modelId!,
      mode: kind == StudioAkidaResultKind.sample
          ? StudioAkidaVisualizationMode.sample
          : StudioAkidaVisualizationMode.benchmark,
      sampleIndex: kind == StudioAkidaResultKind.sample
          ? state.sampleIndex
          : null,
      layerIndex: layerIndex,
    );
  }

  Future<void> _loadVisualization({
    required String hostId,
    required String modelId,
    required StudioAkidaVisualizationMode mode,
    int layerIndex = 1,
    int? sampleIndex,
  }) async {
    state = state.copyWith(
      isLoadingVisualization: true,
      clearVisualizationError: true,
    );
    try {
      final result = await _service.fetchVisualization(
        hostId: hostId,
        modelId: modelId,
        mode: mode,
        layerIndex: layerIndex,
        sampleIndex: sampleIndex,
      );
      if (!ref.mounted) return;
      state = state.copyWith(
        visualizationResult: result,
        isLoadingVisualization: false,
      );
    } catch (error) {
      if (!ref.mounted) return;
      state = state.copyWith(
        isLoadingVisualization: false,
        clearVisualizationResult: true,
        visualizationError: error.toString(),
      );
    }
  }

  String _readinessActivityMessage(
    AkidaNetworkResponse exportResult, {
    AkidaPairedHost? host,
  }) {
    if (host == null) return exportResult.supportState.label;
    final hostMessage = host.lastReadinessMessage.trim();
    if (host.state == AkidaPairedHostState.ready) {
      return '${exportResult.supportState.label} Host is ready for deploy.';
    }
    if (hostMessage.isNotEmpty) {
      return '${exportResult.supportState.label} $hostMessage';
    }
    return '${exportResult.supportState.label} Host state: ${host.state.label}.';
  }

  String _mappingActivityMessage(AkidaSdkVerification verification) {
    if (!verification.isDeployable) return 'Runtime mapping did not pass.';
    return switch (verification.runtimeTarget) {
      'hardware' => 'Mapped to physical Akida hardware.',
      'akd1000_simulator' => 'Mapped to AKD1000 simulator.',
      'software_fallback' => 'Mapped to software fallback runtime.',
      _ => 'Runtime mapped.',
    };
  }

  List<double> _parseRunInputVector() {
    final raw = state.runInputVectorText.trim();
    if (raw.isEmpty) {
      throw const FormatException('Enter at least one numeric input value.');
    }
    final values = raw
        .split(',')
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .map(double.parse)
        .toList(growable: false);
    if (values.isEmpty) {
      throw const FormatException('Enter at least one numeric input value.');
    }
    return values;
  }

  String _defaultRunInputVectorText(Map<String, dynamic>? mappedNetwork) {
    final populations = mappedNetwork?['populations'];
    if (populations is List && populations.isNotEmpty) {
      final firstPopulation = populations.first;
      if (firstPopulation is Map<String, dynamic>) {
        final size = firstPopulation['size'];
        if (size is int && size > 0) {
          return List<String>.generate(
            size,
            (index) => index == 0 ? '1' : '0',
            growable: false,
          ).join(', ');
        }
      }
    }
    return '1';
  }

  /// Message explaining why the network cannot be mapped, or null when it can.
  ///
  /// Both Generate Package and Map Runtime used to `return` here with no state
  /// change, so pressing either on an unsupported network looked like a dead
  /// button. The backend already sends actionable rejection sentences — this
  /// just puts the first one where the user can see it.
  String? _blockingReason() {
    final result = state.exportResult;
    if (result == null) {
      return 'Could not check this network against Akida. Press Check '
          'Readiness to try again.';
    }
    if (result.supportState == AkidaSupportState.unsupported ||
        result.mappedNetwork == null) {
      if (result.rejectionReasons.isNotEmpty) {
        return result.rejectionReasons.first;
      }
      if (result.warnings.isNotEmpty) {
        return result.warnings.first;
      }
      return 'This network cannot be mapped onto Akida.';
    }
    return null;
  }

  Future<void> validate(String spec) async {
    state = state.copyWith(
      phase: StudioAkidaDeployPhase.validating,
      activityMessage: 'Checking Akida scaffold exportability.',
      clearErrorMessage: true,
    );
    try {
      final result = await _service.validate(
        spec: spec,
        bitWidth: state.bitWidth,
        akidaVersion: state.akidaVersion,
      );
      if (!ref.mounted) return;
      state = state.copyWith(
        exportResult: result,
        phase: StudioAkidaDeployPhase.idle,
        activityMessage: result.supportState.label,
      );
    } catch (error) {
      _fail(error);
    }
  }

  Future<void> checkReadiness(String spec) async {
    final host = state.selectedHost;
    state = state.copyWith(
      phase: StudioAkidaDeployPhase.validating,
      activityMessage: host == null
          ? 'Checking Akida scaffold exportability.'
          : 'Checking Akida host readiness.',
      clearErrorMessage: true,
    );
    try {
      if (host == null) {
        final result = await _service.validate(
          spec: spec,
          bitWidth: state.bitWidth,
          akidaVersion: state.akidaVersion,
        );
        if (!ref.mounted) return;
        state = state.copyWith(
          exportResult: result,
          phase: StudioAkidaDeployPhase.idle,
          activityMessage: result.supportState.label,
        );
        return;
      }
      final refreshedHost = await _service.checkHostReadiness(host.id);
      if (!ref.mounted) return;
      final exportResult = state.exportResult;
      final String msg;
      if (exportResult != null) {
        msg = _readinessActivityMessage(exportResult, host: refreshedHost);
      } else if (refreshedHost.lastReadinessMessage.trim().isNotEmpty) {
        msg = refreshedHost.lastReadinessMessage.trim();
      } else {
        msg = 'Host state: ${refreshedHost.state.label}.';
      }
      state = state.copyWith(
        selectedHost: refreshedHost,
        phase: StudioAkidaDeployPhase.idle,
        activityMessage: msg,
      );
    } catch (error) {
      _fail(error);
    }
  }

  Future<void> installSelectedHost() async {
    final host = state.selectedHost;
    if (host == null) {
      state = state.copyWith(
        errorMessage: 'Select or create an Akida host first.',
      );
      return;
    }
    state = state.copyWith(
      phase: StudioAkidaDeployPhase.installing,
      activityMessage: 'Installing Neurochip runtime on ${host.displayName}.',
      clearErrorMessage: true,
      clearRuntimeUpdateJob: true,
    );
    try {
      var update = await _service.startHostUpdate(host.id);
      while (!update.isTerminal) {
        if (!ref.mounted) return;
        state = state.copyWith(
          runtimeUpdateJob: update,
          activityMessage: update.message,
        );
        await Future<void>.delayed(const Duration(seconds: 1));
        update = await _service.fetchHostUpdate(
          hostId: host.id,
          jobId: update.jobId,
        );
      }
      if (!ref.mounted) return;
      if (update.isFailed) {
        state = state.copyWith(
          phase: StudioAkidaDeployPhase.failed,
          runtimeUpdateJob: update,
          errorMessage: update.recovery.isEmpty
              ? update.message
              : '${update.message} ${update.recovery}',
        );
        return;
      }
      final updatedHost = await _service.checkHostReadiness(host.id);
      if (!ref.mounted) return;
      state = state.copyWith(
        selectedHost: updatedHost,
        runtimeUpdateJob: update,
        phase: StudioAkidaDeployPhase.idle,
        activityMessage:
            'Neurochip ${update.installedVersion} installed. '
            '${updatedHost.lastReadinessMessage}',
      );
    } catch (error) {
      _fail(error);
    }
  }

  Future<void> deploySelectedHost(String spec) async {
    final host = state.selectedHost;
    if (host == null) {
      state = state.copyWith(
        errorMessage: 'Select or create an Akida host first.',
      );
      return;
    }
    final exportResult = state.exportResult;
    if (exportResult == null ||
        exportResult.supportState == AkidaSupportState.unsupported ||
        exportResult.mappedNetwork == null) {
      await validate(spec);
      if (!ref.mounted) return;
    }
    final blockingReason = _blockingReason();
    if (blockingReason != null) {
      state = state.copyWith(
        phase: StudioAkidaDeployPhase.failed,
        errorMessage: blockingReason,
      );
      return;
    }
    final readyExportResult = state.exportResult!;
    state = state.copyWith(
      phase: StudioAkidaDeployPhase.packaging,
      activityMessage: 'Generating Akida package for ${host.displayName}.',
      clearErrorMessage: true,
    );
    try {
      await _service.generatePackage(
        runtimeApiUrl: host.runtimeApiUrl,
        credentialRef: host.credentialRef,
        mappedNetwork: readyExportResult.mappedNetwork!,
        bitWidth: state.bitWidth,
      );
      if (!ref.mounted) return;
      state = state.copyWith(
        phase: StudioAkidaDeployPhase.completed,
        activityMessage: 'Package generated.',
      );
    } catch (error) {
      _fail(error);
    }
  }

  Future<void> mapSelectedHost(String spec) async {
    final host = state.selectedHost;
    if (host == null) {
      state = state.copyWith(
        errorMessage: 'Select or create an Akida host first.',
      );
      return;
    }
    final exportResult = state.exportResult;
    if (exportResult == null ||
        exportResult.supportState == AkidaSupportState.unsupported ||
        exportResult.mappedNetwork == null) {
      await validate(spec);
      if (!ref.mounted) return;
    }
    final blockingReason = _blockingReason();
    if (blockingReason != null) {
      state = state.copyWith(
        phase: StudioAkidaDeployPhase.failed,
        errorMessage: blockingReason,
      );
      return;
    }
    final readyExportResult = state.exportResult!;
    state = state.copyWith(
      phase: StudioAkidaDeployPhase.mapping,
      activityMessage: 'Mapping Akida runtime on ${host.displayName}.',
      clearErrorMessage: true,
    );
    try {
      final verification = await _service.mapHostRuntime(
        hostId: host.id,
        mappedNetwork: readyExportResult.mappedNetwork!,
        bitWidth: state.bitWidth,
      );
      if (!ref.mounted) return;
      state = state.copyWith(
        sdkVerification: verification,
        clearRunResult: true,
        runInputVectorText: verification.isDeployable
            ? _defaultRunInputVectorText(readyExportResult.mappedNetwork)
            : '',
        phase: verification.isDeployable
            ? StudioAkidaDeployPhase.completed
            : StudioAkidaDeployPhase.idle,
        activityMessage: _mappingActivityMessage(verification),
      );
    } catch (error) {
      _fail(error);
    }
  }

  Future<void> runSelectedHost() async {
    final host = state.selectedHost;
    final verification = state.sdkVerification;
    if (host == null) {
      state = state.copyWith(
        errorMessage: 'Select or create an Akida host first.',
      );
      return;
    }
    if (verification == null || !verification.isDeployable) {
      state = state.copyWith(
        errorMessage: 'Map the Akida runtime before running inference.',
      );
      return;
    }
    late final List<double> inputs;
    try {
      inputs = _parseRunInputVector();
    } catch (error) {
      state = state.copyWith(
        phase: StudioAkidaDeployPhase.idle,
        errorMessage: error.toString().replaceFirst('FormatException: ', ''),
      );
      return;
    }
    state = state.copyWith(
      phase: StudioAkidaDeployPhase.running,
      activityMessage: 'Running Akida inference on ${host.displayName}.',
      clearErrorMessage: true,
    );
    try {
      final result = await _service.runHostInference(
        hostId: host.id,
        inputs: inputs,
      );
      if (!ref.mounted) return;
      state = state.copyWith(
        runResult: result,
        phase: StudioAkidaDeployPhase.completed,
        activityMessage: switch (result.runtimeTarget) {
          'hardware' => 'Run completed on physical Akida hardware.',
          'akd1000_simulator' => 'Run completed on AKD1000 simulator.',
          'software_fallback' => 'Run completed on software fallback runtime.',
          _ => 'Run completed.',
        },
      );
    } catch (error) {
      _fail(error);
    }
  }
}

/// Backward-compat alias.
final studioAkidaDeployProvider = studioAkidaDeployControllerProvider;
