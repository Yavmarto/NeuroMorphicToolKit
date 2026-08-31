import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

import 'package:neuro_toolkit/features/neurocnl/services/api_client.dart';
import 'package:neuro_toolkit/features/neurocnl/services/deploy_error_formatter.dart';
import 'package:neuro_toolkit/features/neurocnl/services/studio_target_registry_service.dart';

class StudioAkidaDeployException implements Exception {
  const StudioAkidaDeployException(this.message);

  final String message;

  @override
  String toString() => message;
}

class StudioAkidaRunResult {
  const StudioAkidaRunResult({
    required this.outputs,
    required this.telemetry,
    required this.runtimeTarget,
    this.executionTimeUs,
  });

  final List<double> outputs;
  final Map<String, dynamic> telemetry;
  final String runtimeTarget;
  final double? executionTimeUs;
}

class StudioAkidaBundleArtifact {
  const StudioAkidaBundleArtifact({
    required this.filename,
    required this.bundleBase64,
    required this.sha256,
    this.schemaVersion = 0,
  });

  final String filename;
  final String bundleBase64;
  final String sha256;

  /// The bundle's manifest `schemaVersion`, or 0 when it wasn't reported (a
  /// manually chosen file, or an older backend). Discovery picks the newest
  /// bundle by timestamp and a workspace can hold both a V1 companion bundle
  /// and a V2 canvas one, so showing this is how the user can tell which of the
  /// two they just submitted.
  final int schemaVersion;

  factory StudioAkidaBundleArtifact.fromJson(Map<String, dynamic> json) {
    return StudioAkidaBundleArtifact(
      filename: json['filename'] as String,
      bundleBase64: json['bundle_base64'] as String,
      sha256: json['sha256'] as String,
      schemaVersion: (json['schema_version'] as num?)?.toInt() ?? 0,
    );
  }
}

/// One class's share of an on-card evaluation.
///
/// Null on the job rather than an empty list when the host cannot produce it —
/// V1 bundles score via `akida.Model.evaluate`, which yields no per-sample
/// predictions to bucket.
class StudioAkidaClassResult {
  const StudioAkidaClassResult({
    required this.label,
    required this.labelName,
    required this.support,
    required this.correct,
  });

  final int label;
  final String labelName;

  /// Samples in the evaluation set whose true label is [label].
  final int support;

  /// Of those, how many the card classified correctly.
  final int correct;

  /// Fraction correct, or null when the set contains no sample of this class.
  double? get accuracy => support == 0 ? null : correct / support;

  factory StudioAkidaClassResult.fromJson(Map<String, dynamic> json) {
    return StudioAkidaClassResult(
      label: json['label'] as int,
      labelName: json['labelName'] as String? ?? '',
      support: json['support'] as int? ?? 0,
      correct: json['correct'] as int? ?? 0,
    );
  }
}

class StudioAkidaModelJob {
  const StudioAkidaModelJob({
    required this.jobId,
    required this.stage,
    required this.progress,
    required this.message,
    required this.runtimeTarget,
    required this.hardwareVerified,
    required this.metrics,
    this.modelId,
    this.totalSamples,
    this.classResults,
    this.deviceInfo,
    this.errorCode,
  });

  final String jobId;
  final String stage;
  final int progress;
  final String message;
  final String? modelId;
  final String runtimeTarget;
  final bool hardwareVerified;
  final Map<String, double> metrics;

  /// Samples the host actually scored. Used to label the accuracy row and to
  /// bound the sample-index input, which otherwise had no ceiling.
  final int? totalSamples;
  final List<StudioAkidaClassResult>? classResults;
  final String? deviceInfo;
  final String? errorCode;

  bool get isTerminal => stage == 'completed' || stage == 'failed';

  factory StudioAkidaModelJob.fromJson(Map<String, dynamic> json) {
    final rawMetrics =
        json['metrics'] as Map<String, dynamic>? ?? const <String, dynamic>{};
    final rawClassResults = json['classResults'] as List<dynamic>?;
    return StudioAkidaModelJob(
      jobId: json['jobId'] as String,
      stage: json['stage'] as String,
      progress: json['progress'] as int,
      message: json['message'] as String,
      modelId: json['modelId'] as String?,
      runtimeTarget: json['runtimeTarget'] as String? ?? 'unknown',
      hardwareVerified: json['hardwareVerified'] as bool? ?? false,
      metrics: rawMetrics.map(
        (key, value) => MapEntry(key, (value as num).toDouble()),
      ),
      totalSamples: (json['totalSamples'] as num?)?.toInt(),
      classResults: rawClassResults
          ?.map(
            (entry) =>
                StudioAkidaClassResult.fromJson(entry as Map<String, dynamic>),
          )
          .toList(growable: false),
      deviceInfo: json['deviceInfo'] as String?,
      errorCode: json['errorCode'] as String?,
    );
  }
}

/// Per-layer non-zero spike count from the Akida SDK after one hardware inference.
class LayerSpikeStats {
  const LayerSpikeStats({required this.name, required this.nzSpikes});

  final String name;
  final int nzSpikes;

  factory LayerSpikeStats.fromJson(Map<String, dynamic> json) {
    return LayerSpikeStats(
      name: json['name'] as String,
      nzSpikes: json['nzSpikes'] as int,
    );
  }
}

class StudioAkidaModelPrediction {
  const StudioAkidaModelPrediction({
    required this.sampleIndex,
    required this.prediction,
    required this.label,
    required this.labelName,
    required this.outputs,
    required this.runtimeTarget,
    required this.hardwareVerified,
    required this.telemetry,
    this.layerSpikes,
  });

  final int? sampleIndex;
  final int prediction;
  final int? label;
  final String labelName;
  final List<double> outputs;
  final String runtimeTarget;
  final bool hardwareVerified;
  final Map<String, dynamic> telemetry;

  /// Per-layer spike counts from the Akida SDK. Null when the SDK does not
  /// expose per-layer statistics (simulator mode or older SDK version).
  final List<LayerSpikeStats>? layerSpikes;

  factory StudioAkidaModelPrediction.fromJson(Map<String, dynamic> json) {
    final rawSpikes = json['layerSpikes'] as List<dynamic>?;
    return StudioAkidaModelPrediction(
      sampleIndex: json['sampleIndex'] as int?,
      prediction: json['prediction'] as int,
      label: json['label'] as int?,
      labelName: json['labelName'] as String,
      outputs: (json['outputs'] as List<dynamic>)
          .map((value) => (value as num).toDouble())
          .toList(growable: false),
      runtimeTarget: json['runtimeTarget'] as String,
      hardwareVerified: json['hardwareVerified'] as bool,
      telemetry:
          json['telemetry'] as Map<String, dynamic>? ??
          const <String, dynamic>{},
      layerSpikes: rawSpikes
          ?.map((e) => LayerSpikeStats.fromJson(e as Map<String, dynamic>))
          .toList(growable: false),
    );
  }
}

enum StudioAkidaVisualizationMode { sample, benchmark }

class StudioAkidaCompressedArray {
  StudioAkidaCompressedArray({
    required this.dtype,
    required this.shape,
    required this.bytes,
  });

  final String dtype;
  final List<int> shape;
  final Uint8List bytes;

  int get elementCount => shape.fold<int>(1, (total, value) => total * value);

  late final List<double> values = _decodeValues();

  List<double> _decodeValues() {
    final data = ByteData.sublistView(bytes);
    final output = List<double>.filled(elementCount, 0, growable: false);
    switch (dtype) {
      case '|u1':
      case '<u1':
        for (var index = 0; index < output.length; index++) {
          output[index] = data.getUint8(index).toDouble();
        }
      case '|i1':
      case '<i1':
        for (var index = 0; index < output.length; index++) {
          output[index] = data.getInt8(index).toDouble();
        }
      case '<f4':
      case '=f4':
        for (var index = 0; index < output.length; index++) {
          output[index] = data.getFloat32(index * 4, Endian.little);
        }
      case '<i4':
      case '=i4':
        for (var index = 0; index < output.length; index++) {
          output[index] = data.getInt32(index * 4, Endian.little).toDouble();
        }
      default:
        throw FormatException('Unsupported Akida array dtype: $dtype');
    }
    return output;
  }

  factory StudioAkidaCompressedArray.fromJson(Map<String, dynamic> json) {
    if (json['encoding'] != 'zlib+base64') {
      throw const FormatException('Unsupported Akida array encoding.');
    }
    final compressed = base64Decode(json['data'] as String);
    final decoded = const ZLibDecoder().decodeBytes(compressed);
    final shape = (json['shape'] as List<dynamic>)
        .map((value) => (value as num).toInt())
        .toList(growable: false);
    final result = StudioAkidaCompressedArray(
      dtype: json['dtype'] as String,
      shape: shape,
      bytes: decoded,
    );
    final itemSize = switch (result.dtype) {
      '<f4' || '=f4' || '<i4' || '=i4' => 4,
      '|u1' || '<u1' || '|i1' || '<i1' => 1,
      _ => throw FormatException(
        'Unsupported Akida array dtype: ${result.dtype}',
      ),
    };
    if (decoded.length != result.elementCount * itemSize) {
      throw const FormatException('Akida array shape does not match its data.');
    }
    return result;
  }
}

class StudioAkidaVisualizationLayer {
  const StudioAkidaVisualizationLayer({
    required this.index,
    required this.name,
    required this.outputShape,
    required this.visualizable,
    this.weightShape,
    this.weightBits,
  });

  final int index;
  final String name;
  final List<int> outputShape;
  final List<int>? weightShape;
  final int? weightBits;
  final bool visualizable;

  factory StudioAkidaVisualizationLayer.fromJson(Map<String, dynamic> json) {
    List<int>? intList(String key) => (json[key] as List<dynamic>?)
        ?.map((value) => (value as num).toInt())
        .toList(growable: false);
    return StudioAkidaVisualizationLayer(
      index: (json['index'] as num).toInt(),
      name: json['name'] as String,
      outputShape: intList('outputShape') ?? const <int>[],
      weightShape: intList('weightShape'),
      weightBits: (json['weightBits'] as num?)?.toInt(),
      visualizable: json['visualizable'] as bool? ?? true,
    );
  }
}

class StudioAkidaModelVisualization {
  const StudioAkidaModelVisualization({
    required this.modelId,
    required this.mode,
    required this.layers,
    required this.layerIndex,
    required this.layerName,
    required this.sampleCount,
    required this.available,
    required this.provenance,
    required this.relatedRuntimeTarget,
    required this.hardwareVerified,
    this.sampleIndex,
    this.unavailableReason,
    this.activity,
    this.raster,
    this.weights,
    this.weightBits,
  });

  final String modelId;
  final StudioAkidaVisualizationMode mode;
  final List<StudioAkidaVisualizationLayer> layers;
  final int layerIndex;
  final String layerName;
  final int? sampleIndex;
  final int sampleCount;
  final bool available;
  final String? unavailableReason;
  final StudioAkidaCompressedArray? activity;
  final StudioAkidaCompressedArray? raster;
  final StudioAkidaCompressedArray? weights;
  final int? weightBits;
  final String provenance;
  final String relatedRuntimeTarget;
  final bool hardwareVerified;

  factory StudioAkidaModelVisualization.fromJson(Map<String, dynamic> json) {
    StudioAkidaCompressedArray? array(String key) {
      final value = json[key];
      return value is Map<String, dynamic>
          ? StudioAkidaCompressedArray.fromJson(value)
          : null;
    }

    return StudioAkidaModelVisualization(
      modelId: json['modelId'] as String,
      mode: StudioAkidaVisualizationMode.values.byName(json['mode'] as String),
      layers: (json['layers'] as List<dynamic>)
          .map(
            (value) => StudioAkidaVisualizationLayer.fromJson(
              value as Map<String, dynamic>,
            ),
          )
          .toList(growable: false),
      layerIndex: (json['layerIndex'] as num).toInt(),
      layerName: json['layerName'] as String,
      sampleIndex: (json['sampleIndex'] as num?)?.toInt(),
      sampleCount: (json['sampleCount'] as num).toInt(),
      available: json['available'] as bool,
      unavailableReason: json['unavailableReason'] as String?,
      activity: array('activity'),
      raster: array('raster'),
      weights: array('weights'),
      weightBits: (json['weightBits'] as num?)?.toInt(),
      provenance: json['provenance'] as String,
      relatedRuntimeTarget: json['relatedRuntimeTarget'] as String,
      hardwareVerified: json['hardwareVerified'] as bool,
    );
  }
}

class StudioAkidaDeployService {
  StudioAkidaDeployService({
    required ApiClient apiClient,
    required StudioTargetRegistryService targetRegistryService,
  }) : _apiClient = apiClient,
       _targetRegistryService = targetRegistryService;

  final ApiClient _apiClient;
  final StudioTargetRegistryService _targetRegistryService;

  Future<String> createMnistCompanion(String workspacePath) async {
    try {
      final result = await _apiClient.generateAkidaMnistNotebook(
        workspacePath: workspacePath,
      );
      if (result.jupyterUrl.isNotEmpty) return result.jupyterUrl;
      final host = Uri.tryParse(_apiClient.baseUrl)?.host;
      return 'http://${host?.isNotEmpty == true ? host : 'localhost'}:8008/lab/tree/'
          '${result.workspaceFolder}/';
    } catch (error) {
      throw StudioAkidaDeployException(
        formatDeployError(
          error,
          serviceName: 'NeuroStudio',
          action: 'creating the Akida MNIST notebook',
        ),
      );
    }
  }

  Future<StudioAkidaBundleArtifact> discoverLatestBundle(
    String workspaceFolder,
  ) async {
    try {
      final result = await _apiClient.latestAkidaBundle(workspaceFolder);
      return StudioAkidaBundleArtifact.fromJson(result);
    } catch (error) {
      throw StudioAkidaDeployException(
        formatDeployError(
          error,
          serviceName: 'NeuroStudio',
          action: 'finding the latest Akida model bundle',
        ),
      );
    }
  }

  Future<StudioAkidaModelJob> submitModelBundle({
    required String hostId,
    required StudioAkidaBundleArtifact bundle,
  }) async {
    try {
      final result = await _targetRegistryService
          .submitAkidaModelJobViaLauncher(
            hostId: hostId,
            filename: bundle.filename,
            bundleBase64: bundle.bundleBase64,
            sha256: bundle.sha256,
          );
      return StudioAkidaModelJob.fromJson(result);
    } catch (error) {
      throw StudioAkidaDeployException(
        formatDeployError(
          error,
          serviceName: 'Akida host',
          action: 'starting model conversion',
        ),
      );
    }
  }

  Future<StudioAkidaModelJob> fetchModelJob({
    required String hostId,
    required String jobId,
  }) async {
    try {
      final result = await _targetRegistryService.fetchAkidaModelJobViaLauncher(
        hostId: hostId,
        jobId: jobId,
      );
      return StudioAkidaModelJob.fromJson(result);
    } catch (error) {
      throw StudioAkidaDeployException(
        formatDeployError(
          error,
          serviceName: 'Akida host',
          action: 'checking model conversion progress',
        ),
      );
    }
  }

  /// Start a whole-dataset benchmark on an already-deployed model.
  ///
  /// Returns a job to poll with [fetchModelJob]; the run can take far longer
  /// than any request timeout on the path to the host.
  Future<StudioAkidaModelJob> submitBenchmark({
    required String hostId,
    required String modelId,
  }) async {
    try {
      final result = await _targetRegistryService
          .startAkidaModelBenchmarkViaLauncher(
            hostId: hostId,
            modelId: modelId,
          );
      return StudioAkidaModelJob.fromJson(result);
    } catch (error) {
      throw StudioAkidaDeployException(
        formatDeployError(
          error,
          serviceName: 'Akida host',
          action: 'starting the benchmark run',
        ),
      );
    }
  }

  Future<StudioAkidaModelPrediction> runModelSample({
    required String hostId,
    required String modelId,
    required int sampleIndex,
  }) async {
    try {
      final result = await _targetRegistryService
          .runAkidaModelInferenceViaLauncher(
            hostId: hostId,
            modelId: modelId,
            sampleIndex: sampleIndex,
          );
      return StudioAkidaModelPrediction.fromJson(result);
    } catch (error) {
      throw StudioAkidaDeployException(
        formatDeployError(
          error,
          serviceName: 'Akida host',
          action: 'running the selected MNIST sample',
        ),
      );
    }
  }

  Future<StudioAkidaModelVisualization> fetchVisualization({
    required String hostId,
    required String modelId,
    required StudioAkidaVisualizationMode mode,
    required int layerIndex,
    int? sampleIndex,
  }) async {
    try {
      final result = await _targetRegistryService
          .fetchAkidaModelVisualizationViaLauncher(
            hostId: hostId,
            modelId: modelId,
            mode: mode.name,
            layerIndex: layerIndex,
            sampleIndex: sampleIndex,
          );
      return StudioAkidaModelVisualization.fromJson(result);
    } catch (error) {
      throw StudioAkidaDeployException(
        formatDeployError(
          error,
          serviceName: 'Akida host',
          action: 'replaying the deployed model visualization',
        ),
      );
    }
  }

  Future<AkidaNetworkResponse> validate({
    required String spec,
    required int bitWidth,
    required String akidaVersion,
  }) async {
    try {
      final result = await _apiClient.getAkidaDeployability(
        spec,
        bitWidth: bitWidth,
        akidaVersion: akidaVersion,
      );
      return AkidaNetworkResponse.fromJson(result);
    } catch (error) {
      throw StudioAkidaDeployException(
        formatDeployError(
          error,
          serviceName: 'NeuroStudio',
          action: 'checking Akida exportability',
        ),
      );
    }
  }

  Future<AkidaPairedHost> checkHostReadiness(String hostId) async {
    try {
      return await _targetRegistryService.fetchAkidaHostPreflight(hostId);
    } catch (error) {
      throw StudioAkidaDeployException(
        formatDeployError(
          error,
          serviceName: 'launcher control service',
          action: 'checking Akida host readiness',
        ),
      );
    }
  }

  Future<AkidaRuntimeUpdateJob> startHostUpdate(String hostId) async {
    try {
      return await _targetRegistryService.startAkidaRuntimeUpdate(hostId);
    } catch (error) {
      throw StudioAkidaDeployException(
        formatDeployError(
          error,
          serviceName: 'launcher control service',
          action: 'installing the Akida runtime',
        ),
      );
    }
  }

  Future<AkidaRuntimeUpdateJob> fetchHostUpdate({
    required String hostId,
    required String jobId,
  }) async {
    try {
      return await _targetRegistryService.fetchAkidaRuntimeUpdate(
        hostId: hostId,
        jobId: jobId,
      );
    } catch (error) {
      throw StudioAkidaDeployException(
        formatDeployError(
          error,
          serviceName: 'launcher control service',
          action: 'checking Akida runtime update progress',
        ),
      );
    }
  }

  Future<List<int>> generatePackage({
    required String runtimeApiUrl,
    required String credentialRef,
    required Map<String, dynamic> mappedNetwork,
    required int bitWidth,
  }) async {
    try {
      return await _targetRegistryService.downloadAkidaPackage(
        runtimeApiUrl: runtimeApiUrl,
        credentialRef: credentialRef,
        mappedNetwork: mappedNetwork,
        bitWidth: bitWidth,
      );
    } catch (error) {
      throw StudioAkidaDeployException(
        formatDeployError(
          error,
          serviceName: 'Neurochip',
          action: 'generating the Akida package',
        ),
      );
    }
  }

  Future<AkidaSdkVerification> mapRuntime({
    required String runtimeApiUrl,
    required String credentialRef,
    required Map<String, dynamic> mappedNetwork,
    required int bitWidth,
  }) async {
    try {
      return await _targetRegistryService.mapAkidaRuntime(
        runtimeApiUrl: runtimeApiUrl,
        credentialRef: credentialRef,
        mappedNetwork: mappedNetwork,
        bitWidth: bitWidth,
      );
    } catch (error) {
      throw StudioAkidaDeployException(
        formatDeployError(
          error,
          serviceName: 'Neurochip',
          action: 'mapping the Akida runtime',
        ),
      );
    }
  }

  Future<AkidaSdkVerification> mapHostRuntime({
    required String hostId,
    required Map<String, dynamic> mappedNetwork,
    required int bitWidth,
  }) async {
    try {
      return await _targetRegistryService.mapAkidaRuntimeViaLauncher(
        hostId: hostId,
        mappedNetwork: mappedNetwork,
        bitWidth: bitWidth,
      );
    } catch (error) {
      throw StudioAkidaDeployException(
        formatDeployError(
          error,
          serviceName: 'launcher control service',
          action: 'mapping the Akida runtime',
        ),
      );
    }
  }

  Future<StudioAkidaRunResult> runInference({
    required String runtimeApiUrl,
    required String credentialRef,
    required List<double> inputs,
    required String runtimeTarget,
  }) async {
    try {
      final response = await _targetRegistryService.runAkidaInference(
        runtimeApiUrl: runtimeApiUrl,
        credentialRef: credentialRef,
        inputs: inputs,
      );
      final rawOutputs =
          response['outputs'] as List<dynamic>? ?? const <dynamic>[];
      final telemetry =
          response['telemetry'] as Map<String, dynamic>? ??
          const <String, dynamic>{};
      final rawExecutionTimeUs = response['execution_time_us'];
      final executionTimeUs = rawExecutionTimeUs is num
          ? rawExecutionTimeUs.toDouble()
          : null;
      final resolvedRuntimeTarget =
          (response['runtime_target'] as String?)?.trim().isNotEmpty == true
          ? (response['runtime_target'] as String).trim()
          : runtimeTarget;
      return StudioAkidaRunResult(
        outputs: rawOutputs.map((value) => (value as num).toDouble()).toList(),
        telemetry: telemetry,
        runtimeTarget: resolvedRuntimeTarget,
        executionTimeUs: executionTimeUs,
      );
    } catch (error) {
      throw StudioAkidaDeployException(
        formatDeployError(
          error,
          serviceName: 'Neurochip',
          action: 'running Akida inference',
        ),
      );
    }
  }

  Future<StudioAkidaRunResult> runHostInference({
    required String hostId,
    required List<double> inputs,
  }) async {
    try {
      final response = await _targetRegistryService
          .runAkidaInferenceViaLauncher(hostId: hostId, inputs: inputs);
      final rawOutputs =
          response['outputs'] as List<dynamic>? ?? const <dynamic>[];
      final telemetry =
          response['telemetry'] as Map<String, dynamic>? ??
          const <String, dynamic>{};
      final rawExecutionTimeUs = response['execution_time_us'];
      final executionTimeUs = rawExecutionTimeUs is num
          ? rawExecutionTimeUs.toDouble()
          : null;
      final runtimeTarget =
          (response['runtime_target'] as String?)?.trim().isNotEmpty == true
          ? (response['runtime_target'] as String).trim()
          : 'unknown';
      return StudioAkidaRunResult(
        outputs: rawOutputs.map((value) => (value as num).toDouble()).toList(),
        telemetry: telemetry,
        runtimeTarget: runtimeTarget,
        executionTimeUs: executionTimeUs,
      );
    } catch (error) {
      throw StudioAkidaDeployException(
        formatDeployError(
          error,
          serviceName: 'launcher control service',
          action: 'running Akida inference',
        ),
      );
    }
  }
}
