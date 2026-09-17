// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'preview.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

PreviewRequest _$PreviewRequestFromJson(Map<String, dynamic> json) =>
    PreviewRequest(
      graph: CanvasGraph.fromJson(json['graph'] as Map<String, dynamic>),
      durationMs: (json['duration_ms'] as num?)?.toDouble() ?? 500.0,
    );

Map<String, dynamic> _$PreviewRequestToJson(PreviewRequest instance) =>
    <String, dynamic>{
      'graph': instance.graph.toJson(),
      'duration_ms': instance.durationMs,
    };

PreviewSpikeEvent _$PreviewSpikeEventFromJson(Map<String, dynamic> json) =>
    PreviewSpikeEvent(
      nodeId: json['node_id'] as String,
      neuronId: json['neuron_id'] as String,
      neuronIndex: (json['neuron_index'] as num).toInt(),
      timeMs: (json['time_ms'] as num).toDouble(),
    );

Map<String, dynamic> _$PreviewSpikeEventToJson(PreviewSpikeEvent instance) =>
    <String, dynamic>{
      'node_id': instance.nodeId,
      'neuron_id': instance.neuronId,
      'neuron_index': instance.neuronIndex,
      'time_ms': instance.timeMs,
    };

PreviewEdgeEvent _$PreviewEdgeEventFromJson(Map<String, dynamic> json) =>
    PreviewEdgeEvent(
      sourceNodeId: json['source_node_id'] as String,
      targetNodeId: json['target_node_id'] as String,
      weight: (json['weight'] as num).toDouble(),
      delayMs: (json['delay_ms'] as num).toDouble(),
      timeMs: (json['time_ms'] as num).toDouble(),
    );

Map<String, dynamic> _$PreviewEdgeEventToJson(PreviewEdgeEvent instance) =>
    <String, dynamic>{
      'source_node_id': instance.sourceNodeId,
      'target_node_id': instance.targetNodeId,
      'weight': instance.weight,
      'delay_ms': instance.delayMs,
      'time_ms': instance.timeMs,
    };

PreviewNodePlayback _$PreviewNodePlaybackFromJson(Map<String, dynamic> json) =>
    PreviewNodePlayback(
      nodeId: json['node_id'] as String,
      spikeTrains:
          (json['spike_trains'] as Map<String, dynamic>?)?.map(
            (k, e) => MapEntry(
              k,
              (e as List<dynamic>).map((e) => (e as num).toDouble()).toList(),
            ),
          ) ??
          const <String, List<double>>{},
      voltageTraces:
          (json['voltage_traces'] as Map<String, dynamic>?)?.map(
            (k, e) => MapEntry(
              k,
              (e as List<dynamic>).map((e) => (e as num).toDouble()).toList(),
            ),
          ) ??
          const <String, List<double>>{},
      spikeCount: (json['spike_count'] as num?)?.toInt() ?? 0,
    );

Map<String, dynamic> _$PreviewNodePlaybackToJson(
  PreviewNodePlayback instance,
) => <String, dynamic>{
  'node_id': instance.nodeId,
  'spike_trains': instance.spikeTrains,
  'voltage_traces': instance.voltageTraces,
  'spike_count': instance.spikeCount,
};

PreviewPlaybackSummary _$PreviewPlaybackSummaryFromJson(
  Map<String, dynamic> json,
) => PreviewPlaybackSummary(
  totalSpikes: (json['total_spikes'] as num?)?.toInt() ?? 0,
  activeNodeCount: (json['active_node_count'] as num?)?.toInt() ?? 0,
  edgeEventCount: (json['edge_event_count'] as num?)?.toInt() ?? 0,
);

Map<String, dynamic> _$PreviewPlaybackSummaryToJson(
  PreviewPlaybackSummary instance,
) => <String, dynamic>{
  'total_spikes': instance.totalSpikes,
  'active_node_count': instance.activeNodeCount,
  'edge_event_count': instance.edgeEventCount,
};

PreviewPlayback _$PreviewPlaybackFromJson(
  Map<String, dynamic> json,
) => PreviewPlayback(
  durationMs: (json['duration_ms'] as num).toDouble(),
  sampleCount: (json['sample_count'] as num?)?.toInt() ?? 0,
  nodes:
      (json['nodes'] as List<dynamic>?)
          ?.map((e) => PreviewNodePlayback.fromJson(e as Map<String, dynamic>))
          .toList() ??
      const <PreviewNodePlayback>[],
  spikeEvents:
      (json['spike_events'] as List<dynamic>?)
          ?.map((e) => PreviewSpikeEvent.fromJson(e as Map<String, dynamic>))
          .toList() ??
      const <PreviewSpikeEvent>[],
  edgeEvents:
      (json['edge_events'] as List<dynamic>?)
          ?.map((e) => PreviewEdgeEvent.fromJson(e as Map<String, dynamic>))
          .toList() ??
      const <PreviewEdgeEvent>[],
  summary: json['summary'] == null
      ? const PreviewPlaybackSummary()
      : PreviewPlaybackSummary.fromJson(
          json['summary'] as Map<String, dynamic>,
        ),
  bulkSpikeFrame: _bulkSpikeFrameFromJson(json['bulk_spike_frame']),
);

Map<String, dynamic> _$PreviewPlaybackToJson(PreviewPlayback instance) =>
    <String, dynamic>{
      'duration_ms': instance.durationMs,
      'sample_count': instance.sampleCount,
      'nodes': instance.nodes.map((e) => e.toJson()).toList(),
      'spike_events': instance.spikeEvents.map((e) => e.toJson()).toList(),
      'edge_events': instance.edgeEvents.map((e) => e.toJson()).toList(),
      'summary': instance.summary.toJson(),
      'bulk_spike_frame': _bulkSpikeFrameToJson(instance.bulkSpikeFrame),
    };

PreviewResponse _$PreviewResponseFromJson(Map<String, dynamic> json) =>
    PreviewResponse(
      jobId: json['job_id'] as String?,
      status: json['status'] as String,
      error: json['error'] as String?,
      results:
          json['results'] as Map<String, dynamic>? ?? const <String, dynamic>{},
      playback: json['playback'] == null
          ? null
          : PreviewPlayback.fromJson(json['playback'] as Map<String, dynamic>),
      metrics: json['metrics'] as Map<String, dynamic>?,
      backendSupport: json['backend_support'] == null
          ? null
          : BackendSupport.fromJson(
              json['backend_support'] as Map<String, dynamic>,
            ),
      generatorFidelity: json['generator_fidelity'] == null
          ? null
          : GeneratorFidelitySummary.fromJson(
              json['generator_fidelity'] as Map<String, dynamic>,
            ),
    );

Map<String, dynamic> _$PreviewResponseToJson(PreviewResponse instance) =>
    <String, dynamic>{
      'job_id': instance.jobId,
      'status': instance.status,
      'error': instance.error,
      'results': instance.results,
      'playback': instance.playback?.toJson(),
      'metrics': instance.metrics,
      'backend_support': instance.backendSupport?.toJson(),
      'generator_fidelity': instance.generatorFidelity?.toJson(),
    };
