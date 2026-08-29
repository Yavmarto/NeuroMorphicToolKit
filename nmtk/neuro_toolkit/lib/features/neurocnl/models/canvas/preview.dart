import 'package:json_annotation/json_annotation.dart';
import 'package:neuro_toolkit/features/neurocnl/models/canvas/bulk_spike_frame.dart';

import 'package:neuro_toolkit/features/neurocnl/models/canvas/canvas.dart';
import 'package:neuro_toolkit/features/neurocnl/models/canvas/validation.dart';

part 'preview.g.dart';

// BulkSpikeFrame is a hand-written class (not @JsonSerializable), so
// json_serializable's codegen needs explicit bridging functions here.
BulkSpikeFrame? _bulkSpikeFrameFromJson(Object? json) =>
    json is Map<String, dynamic> ? BulkSpikeFrame.fromJson(json) : null;
Object? _bulkSpikeFrameToJson(BulkSpikeFrame? frame) =>
    null; // not sent client->server

@JsonSerializable(explicitToJson: true)
class PreviewRequest {
  final CanvasGraph graph;
  @JsonKey(name: 'duration_ms')
  final double durationMs;

  PreviewRequest({required this.graph, this.durationMs = 500.0});

  factory PreviewRequest.fromJson(Map<String, dynamic> json) =>
      _$PreviewRequestFromJson(json);
  Map<String, dynamic> toJson() => _$PreviewRequestToJson(this);
}

@JsonSerializable()
class PreviewSpikeEvent {
  @JsonKey(name: 'node_id')
  final String nodeId;
  @JsonKey(name: 'neuron_id')
  final String neuronId;
  @JsonKey(name: 'neuron_index')
  final int neuronIndex;
  @JsonKey(name: 'time_ms')
  final double timeMs;

  const PreviewSpikeEvent({
    required this.nodeId,
    required this.neuronId,
    required this.neuronIndex,
    required this.timeMs,
  });

  factory PreviewSpikeEvent.fromJson(Map<String, dynamic> json) =>
      _$PreviewSpikeEventFromJson(json);
  Map<String, dynamic> toJson() => _$PreviewSpikeEventToJson(this);
}

@JsonSerializable()
class PreviewEdgeEvent {
  @JsonKey(name: 'source_node_id')
  final String sourceNodeId;
  @JsonKey(name: 'target_node_id')
  final String targetNodeId;
  final double weight;
  @JsonKey(name: 'delay_ms')
  final double delayMs;
  @JsonKey(name: 'time_ms')
  final double timeMs;

  const PreviewEdgeEvent({
    required this.sourceNodeId,
    required this.targetNodeId,
    required this.weight,
    required this.delayMs,
    required this.timeMs,
  });

  factory PreviewEdgeEvent.fromJson(Map<String, dynamic> json) =>
      _$PreviewEdgeEventFromJson(json);
  Map<String, dynamic> toJson() => _$PreviewEdgeEventToJson(this);
}

@JsonSerializable()
class PreviewNodePlayback {
  @JsonKey(name: 'node_id')
  final String nodeId;
  @JsonKey(name: 'spike_trains')
  final Map<String, List<double>> spikeTrains;
  @JsonKey(name: 'voltage_traces')
  final Map<String, List<double>> voltageTraces;
  @JsonKey(name: 'spike_count')
  final int spikeCount;

  const PreviewNodePlayback({
    required this.nodeId,
    this.spikeTrains = const <String, List<double>>{},
    this.voltageTraces = const <String, List<double>>{},
    this.spikeCount = 0,
  });

  factory PreviewNodePlayback.fromJson(Map<String, dynamic> json) =>
      _$PreviewNodePlaybackFromJson(json);
  Map<String, dynamic> toJson() => _$PreviewNodePlaybackToJson(this);
}

@JsonSerializable()
class PreviewPlaybackSummary {
  @JsonKey(name: 'total_spikes')
  final int totalSpikes;
  @JsonKey(name: 'active_node_count')
  final int activeNodeCount;
  @JsonKey(name: 'edge_event_count')
  final int edgeEventCount;

  const PreviewPlaybackSummary({
    this.totalSpikes = 0,
    this.activeNodeCount = 0,
    this.edgeEventCount = 0,
  });

  factory PreviewPlaybackSummary.fromJson(Map<String, dynamic> json) =>
      _$PreviewPlaybackSummaryFromJson(json);
  Map<String, dynamic> toJson() => _$PreviewPlaybackSummaryToJson(this);
}

@JsonSerializable(explicitToJson: true)
class PreviewPlayback {
  @JsonKey(name: 'duration_ms')
  final double durationMs;
  @JsonKey(name: 'sample_count')
  final int sampleCount;
  final List<PreviewNodePlayback> nodes;
  @JsonKey(name: 'spike_events')
  final List<PreviewSpikeEvent> spikeEvents;
  @JsonKey(name: 'edge_events')
  final List<PreviewEdgeEvent> edgeEvents;
  final PreviewPlaybackSummary summary;
  @JsonKey(
    name: 'bulk_spike_frame',
    fromJson: _bulkSpikeFrameFromJson,
    toJson: _bulkSpikeFrameToJson,
  )
  final BulkSpikeFrame? bulkSpikeFrame;

  const PreviewPlayback({
    required this.durationMs,
    this.sampleCount = 0,
    this.nodes = const <PreviewNodePlayback>[],
    this.spikeEvents = const <PreviewSpikeEvent>[],
    this.edgeEvents = const <PreviewEdgeEvent>[],
    this.summary = const PreviewPlaybackSummary(),
    this.bulkSpikeFrame,
  });

  factory PreviewPlayback.fromJson(Map<String, dynamic> json) =>
      _$PreviewPlaybackFromJson(json);
  Map<String, dynamic> toJson() => _$PreviewPlaybackToJson(this);

  factory PreviewPlayback.fromLegacyResults(
    Map<String, dynamic> results, {
    required double durationMs,
  }) {
    final nodes = <PreviewNodePlayback>[];
    final spikeEvents = <PreviewSpikeEvent>[];
    for (final entry in results.entries) {
      final nodeId = entry.key;
      final rawNode = entry.value;
      if (rawNode is! Map<String, dynamic>) {
        continue;
      }

      final rawSpikes = rawNode['spikes'];
      final rawVoltages = rawNode['voltage'];
      final spikeTrains = <String, List<double>>{};
      final voltageTraces = <String, List<double>>{};

      if (rawSpikes is List) {
        for (var index = 0; index < rawSpikes.length; index += 1) {
          final neuronId = '$nodeId:$index';
          final times = (rawSpikes[index] as List? ?? const <dynamic>[])
              .map((value) => ((value as num?) ?? 0).toDouble())
              .toList();
          spikeTrains[neuronId] = times;
          for (final timeMs in times) {
            spikeEvents.add(
              PreviewSpikeEvent(
                nodeId: nodeId,
                neuronId: neuronId,
                neuronIndex: index,
                timeMs: timeMs,
              ),
            );
          }
        }
      }

      if (rawVoltages is List) {
        for (var index = 0; index < rawVoltages.length; index += 1) {
          final neuronId = '$nodeId:$index';
          voltageTraces[neuronId] =
              (rawVoltages[index] as List? ?? const <dynamic>[])
                  .map((value) => ((value as num?) ?? 0).toDouble())
                  .toList();
        }
      }

      nodes.add(
        PreviewNodePlayback(
          nodeId: nodeId,
          spikeTrains: spikeTrains,
          voltageTraces: voltageTraces,
          spikeCount: spikeTrains.values.fold<int>(
            0,
            (sum, times) => sum + times.length,
          ),
        ),
      );
    }

    return PreviewPlayback(
      durationMs: durationMs,
      sampleCount: nodes.isEmpty
          ? 0
          : nodes.first.voltageTraces.values.fold<int>(
              0,
              (maxCount, trace) =>
                  trace.length > maxCount ? trace.length : maxCount,
            ),
      nodes: nodes,
      spikeEvents: spikeEvents..sort((a, b) => a.timeMs.compareTo(b.timeMs)),
      edgeEvents: const <PreviewEdgeEvent>[],
      summary: PreviewPlaybackSummary(
        totalSpikes: spikeEvents.length,
        activeNodeCount: nodes.where((node) => node.spikeCount > 0).length,
        edgeEventCount: 0,
      ),
    );
  }

  PreviewNodePlayback? nodeById(String nodeId) {
    for (final node in nodes) {
      if (node.nodeId == nodeId) {
        return node;
      }
    }
    return null;
  }
}

enum PreviewSocketMessageType { status, frame, completion, error }

class PreviewSocketMessage {
  const PreviewSocketMessage._({
    required this.type,
    this.status,
    this.message,
    this.currentTimeMs,
    this.playback,
    this.response,
  });

  final PreviewSocketMessageType type;
  final String? status;
  final String? message;
  final double? currentTimeMs;
  final PreviewPlayback? playback;
  final PreviewResponse? response;

  factory PreviewSocketMessage.fromJson(Map<String, dynamic> json) {
    final typeValue = json['type'] as String? ?? 'error';
    final type = switch (typeValue) {
      'status' => PreviewSocketMessageType.status,
      'frame' => PreviewSocketMessageType.frame,
      'completion' => PreviewSocketMessageType.completion,
      _ => PreviewSocketMessageType.error,
    };

    return PreviewSocketMessage._(
      type: type,
      status: json['status'] as String?,
      message: json['message'] as String?,
      currentTimeMs: (json['current_time_ms'] as num?)?.toDouble(),
      playback: json['playback'] is Map<String, dynamic>
          ? PreviewPlayback.fromJson(json['playback'] as Map<String, dynamic>)
          : null,
      response: json['response'] is Map<String, dynamic>
          ? PreviewResponse.fromJson(json['response'] as Map<String, dynamic>)
          : null,
    );
  }
}

@JsonSerializable(explicitToJson: true)
class PreviewResponse {
  @JsonKey(name: 'job_id')
  final String? jobId;
  final String status;
  final String? error;
  final Map<String, dynamic> results;
  final PreviewPlayback? playback;
  final Map<String, dynamic>? metrics;
  @JsonKey(name: 'backend_support')
  final BackendSupport? backendSupport;
  @JsonKey(name: 'generator_fidelity')
  final GeneratorFidelitySummary? generatorFidelity;

  const PreviewResponse({
    this.jobId,
    required this.status,
    this.error,
    this.results = const <String, dynamic>{},
    this.playback,
    this.metrics,
    this.backendSupport,
    this.generatorFidelity,
  });

  factory PreviewResponse.fromJson(Map<String, dynamic> json) {
    final decoded = _$PreviewResponseFromJson(json);
    return decoded.playback == null && decoded.results.isNotEmpty
        ? PreviewResponse(
            jobId: decoded.jobId,
            status: decoded.status,
            error: decoded.error,
            results: decoded.results,
            playback: PreviewPlayback.fromLegacyResults(
              decoded.results,
              durationMs: _inferDurationMs(decoded),
            ),
            metrics: decoded.metrics,
            backendSupport: decoded.backendSupport,
            generatorFidelity: decoded.generatorFidelity,
          )
        : decoded;
  }

  Map<String, dynamic> toJson() => _$PreviewResponseToJson(this);

  double get durationMs => playback?.durationMs ?? _inferDurationMs(this);

  static double _inferDurationMs(PreviewResponse response) {
    final metricValue = response.metrics?['simulation_time_ms'];
    if (metricValue is num) {
      return metricValue.toDouble();
    }

    var latest = 0.0;
    for (final node in response.results.values) {
      if (node is! Map<String, dynamic>) {
        continue;
      }
      final rawSpikes = node['spikes'];
      if (rawSpikes is! List) {
        continue;
      }
      for (final spikeTrain in rawSpikes) {
        if (spikeTrain is! List || spikeTrain.isEmpty) {
          continue;
        }
        final candidate = ((spikeTrain.last as num?) ?? 0).toDouble();
        if (candidate > latest) {
          latest = candidate;
        }
      }
    }
    return latest > 0 ? latest : 500.0;
  }
}
