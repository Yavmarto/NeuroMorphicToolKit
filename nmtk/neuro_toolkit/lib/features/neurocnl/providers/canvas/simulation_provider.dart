import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:neuro_toolkit/features/neurocnl/models/canvas/canvas.dart';
import 'package:neuro_toolkit/features/neurocnl/models/canvas/preview.dart';
import 'package:neuro_toolkit/features/neurocnl/models/canvas/validation.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/canvas/canvas_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/canvas/sync_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/canvas/validation_provider.dart';

part 'simulation_provider.g.dart';

enum SimulationStatus { idle, connecting, running, paused, completed, error }

enum PreviewTransportMode { none, webSocket, polling }

const _runningStatuses = {'queued', 'running'};
const _playbackTick = Duration(milliseconds: 33);
const _defaultStepMs = 25.0;
// bufferedFrames has no consumers today; cap it to the latest frame so a
// long-running/looping preview stream can't grow this list without bound.
const _kMaxBufferedFrames = 1;

List<PreviewPlaybackFrame> _appendBufferedFrame(
  List<PreviewPlaybackFrame> frames,
  PreviewPlaybackFrame frame,
) {
  final next = <PreviewPlaybackFrame>[...frames, frame];
  if (next.length > _kMaxBufferedFrames) {
    next.removeRange(0, next.length - _kMaxBufferedFrames);
  }
  return next;
}

class PreviewPlaybackFrame {
  const PreviewPlaybackFrame({
    required this.currentTimeMs,
    required this.playback,
  });

  final double currentTimeMs;
  final PreviewPlayback playback;
}

class SimulationState {
  const SimulationState({
    this.status = SimulationStatus.idle,
    this.transportMode = PreviewTransportMode.none,
    this.results,
    this.playback,
    this.error,
    this.currentTime = 0.0,
    this.speed = 0.5,
    this.selectedNodeId,
    this.bufferedFrames = const <PreviewPlaybackFrame>[],
    this.graphNodes = const <CanvasNode>[],
  });

  final SimulationStatus status;
  final PreviewTransportMode transportMode;
  final PreviewResponse? results;
  final PreviewPlayback? playback;
  final String? error;
  final double currentTime;
  final double speed;
  final String? selectedNodeId;
  final List<PreviewPlaybackFrame> bufferedFrames;
  // The canvas graph's nodes as of the last runPreview() call — carries
  // each node's position/width/height so a bulk (large-network) preview
  // can lay out one box per node matching its canvas geometry.
  final List<CanvasNode> graphNodes;

  double get durationMs => playback?.durationMs ?? results?.durationMs ?? 0.0;
  bool get hasPreview => playback != null || results != null;
  bool get isFetching =>
      status == SimulationStatus.connecting &&
      transportMode != PreviewTransportMode.none;
  bool get isPlayingBack =>
      status == SimulationStatus.running && hasPreview && !isFetching;
  bool get canStep => hasPreview && durationMs > 0;

  SimulationState copyWith({
    SimulationStatus? status,
    PreviewTransportMode? transportMode,
    PreviewResponse? results,
    bool clearResults = false,
    PreviewPlayback? playback,
    bool clearPlayback = false,
    String? error,
    bool clearError = false,
    double? currentTime,
    double? speed,
    String? selectedNodeId,
    bool clearSelectedNodeId = false,
    List<PreviewPlaybackFrame>? bufferedFrames,
    bool clearBufferedFrames = false,
    List<CanvasNode>? graphNodes,
  }) {
    return SimulationState(
      status: status ?? this.status,
      transportMode: transportMode ?? this.transportMode,
      results: clearResults ? null : (results ?? this.results),
      playback: clearPlayback ? null : (playback ?? this.playback),
      error: clearError ? null : (error ?? this.error),
      currentTime: currentTime ?? this.currentTime,
      speed: speed ?? this.speed,
      selectedNodeId: clearSelectedNodeId
          ? null
          : (selectedNodeId ?? this.selectedNodeId),
      bufferedFrames: clearBufferedFrames
          ? const <PreviewPlaybackFrame>[]
          : (bufferedFrames ?? this.bufferedFrames),
      graphNodes: graphNodes ?? this.graphNodes,
    );
  }
}

@riverpod
class SimulationController extends _$SimulationController {
  Timer? _playbackTimer;
  DateTime? _lastPlaybackTickAt;

  @override
  SimulationState build() {
    ref.onDispose(() {
      _stopPlaybackTimer();
    });
    return const SimulationState();
  }

  Future<void> runPreview() async {
    _stopPlaybackTimer();
    final validationState = ref.read(validationProvider);
    final graph = ref.read(canvasProvider).graph;

    ValidationResult validation;
    if (validationState is AsyncData<ValidationResult>) {
      validation = validationState.value;
    } else {
      state = state.copyWith(
        status: SimulationStatus.connecting,
        transportMode: PreviewTransportMode.none,
        clearError: true,
      );
      try {
        validation = await ref.read(apiClientProvider).validateGraph(graph);
      } catch (error) {
        state = state.copyWith(
          status: SimulationStatus.error,
          error: 'Validation failed: $error',
          transportMode: PreviewTransportMode.none,
        );
        return;
      }
    }

    if (!validation.valid) {
      state = state.copyWith(
        status: SimulationStatus.error,
        error: 'Cannot run simulation: Graph has validation errors.',
        transportMode: PreviewTransportMode.none,
      );
      return;
    }

    final backendSupport = validation.backendSupport;
    if (backendSupport != null && backendSupport.verdict == 'unsupported') {
      state = state.copyWith(
        status: SimulationStatus.error,
        error: backendSupport.warnings.isNotEmpty
            ? backendSupport.warnings.first
            : 'Cannot run simulation: the selected backend is unsupported.',
        transportMode: PreviewTransportMode.none,
      );
      return;
    }

    state = state.copyWith(
      status: SimulationStatus.connecting,
      transportMode: PreviewTransportMode.webSocket,
      clearError: true,
      clearResults: true,
      clearPlayback: true,
      clearBufferedFrames: true,
      currentTime: 0.0,
      graphNodes: graph.nodes,
    );

    try {
      await _runPreviewViaWebSocket(graph);
      return;
    } catch (error) {
      debugPrint('Preview websocket failed, falling back to polling: $error');
    }

    state = state.copyWith(
      status: SimulationStatus.connecting,
      transportMode: PreviewTransportMode.polling,
      clearError: true,
      clearResults: true,
      clearPlayback: true,
      clearBufferedFrames: true,
      currentTime: 0.0,
    );

    await _runPreviewViaPolling(graph);
  }

  Future<void> _runPreviewViaWebSocket(CanvasGraph graph) async {
    await for (final message
        in ref.read(apiClientProvider).streamPreview(graph)) {
      if (!ref.mounted) return;
      switch (message.type) {
        case PreviewSocketMessageType.status:
          state = state.copyWith(
            status: SimulationStatus.connecting,
            clearError: true,
          );
          break;
        case PreviewSocketMessageType.frame:
          final playback = message.playback;
          if (playback == null) {
            continue;
          }
          final currentTimeMs =
              message.currentTimeMs
                  ?.clamp(0.0, playback.durationMs)
                  .toDouble() ??
              state.currentTime;
          state = state.copyWith(
            status: SimulationStatus.connecting,
            playback: playback,
            currentTime: currentTimeMs,
            bufferedFrames: _appendBufferedFrame(
              state.bufferedFrames,
              PreviewPlaybackFrame(
                currentTimeMs: currentTimeMs,
                playback: playback,
              ),
            ),
            selectedNodeId: state.selectedNodeId ?? _defaultNodeId(playback),
          );
          break;
        case PreviewSocketMessageType.completion:
          final response = message.response;
          if (response == null) {
            throw StateError('Completion message did not include a response.');
          }
          final playback = response.playback;
          state = state.copyWith(
            status: SimulationStatus.completed,
            results: response,
            playback: playback,
            currentTime: 0.0,
            selectedNodeId: state.selectedNodeId ?? _defaultNodeId(playback),
          );
          return;
        case PreviewSocketMessageType.error:
          throw StateError(message.message ?? 'Preview websocket failed.');
      }
    }
  }

  Future<void> _runPreviewViaPolling(CanvasGraph graph) async {
    try {
      final apiClient = ref.read(apiClientProvider);
      var response = await apiClient.runPreview(graph);
      if (!ref.mounted) return;
      if (response.status == 'failed') {
        state = state.copyWith(
          status: SimulationStatus.error,
          error: response.error ?? 'Preview is unsupported for this backend.',
          transportMode: PreviewTransportMode.polling,
        );
        return;
      }

      final jobId = response.jobId;
      if (jobId != null) {
        for (var attempt = 0; attempt < 20; attempt += 1) {
          if (!_runningStatuses.contains(response.status)) {
            break;
          }
          await Future<void>.delayed(const Duration(milliseconds: 150));
          if (!ref.mounted) return;
          response = await apiClient.getSimulationStatus(jobId);
          if (!ref.mounted) return;
          final playback = response.playback;
          if (playback != null) {
            final currentTime = response.status == 'completed'
                ? 0.0
                : playback.durationMs;
            state = state.copyWith(
              status: SimulationStatus.connecting,
              playback: playback,
              currentTime: currentTime,
              selectedNodeId: state.selectedNodeId ?? _defaultNodeId(playback),
              bufferedFrames: response.status == 'completed'
                  ? state.bufferedFrames
                  : _appendBufferedFrame(
                      state.bufferedFrames,
                      PreviewPlaybackFrame(
                        currentTimeMs: playback.durationMs,
                        playback: playback,
                      ),
                    ),
            );
          }
        }
      }

      if (response.status == 'completed') {
        state = state.copyWith(
          status: SimulationStatus.completed,
          results: response,
          playback: response.playback,
          currentTime: 0.0,
          selectedNodeId:
              state.selectedNodeId ?? _defaultNodeId(response.playback),
        );
        return;
      }

      if (response.status == 'cancelled') {
        state = state.copyWith(
          status: SimulationStatus.error,
          error: 'Simulation was cancelled.',
          transportMode: PreviewTransportMode.polling,
        );
        return;
      }

      if (_runningStatuses.contains(response.status)) {
        state = state.copyWith(
          status: SimulationStatus.error,
          error: 'Simulation did not complete in time.',
          transportMode: PreviewTransportMode.polling,
        );
        return;
      }

      state = state.copyWith(
        status: SimulationStatus.error,
        error: response.error ?? 'Simulation failed.',
        transportMode: PreviewTransportMode.polling,
      );
    } catch (error) {
      debugPrint('Preview run failed: $error');
      if (!ref.mounted) return;
      state = state.copyWith(
        status: SimulationStatus.error,
        error: error.toString(),
        transportMode: PreviewTransportMode.polling,
      );
    }
  }

  void play() {
    if (!state.hasPreview || state.durationMs <= 0) {
      return;
    }
    final startTime = state.currentTime >= state.durationMs
        ? 0.0
        : state.currentTime;
    state = state.copyWith(
      status: SimulationStatus.running,
      currentTime: startTime,
    );
    _lastPlaybackTickAt = DateTime.now();
    _playbackTimer ??= Timer.periodic(_playbackTick, (_) => _advancePlayback());
  }

  void pause() {
    if (!state.hasPreview) {
      return;
    }
    _stopPlaybackTimer();
    state = state.copyWith(status: SimulationStatus.paused);
  }

  void stepForward() {
    if (!state.canStep) {
      return;
    }
    _stopPlaybackTimer();
    final nextTime = (state.currentTime + _defaultStepMs)
        .clamp(0.0, state.durationMs)
        .toDouble();
    state = state.copyWith(
      status: nextTime >= state.durationMs
          ? SimulationStatus.completed
          : SimulationStatus.paused,
      currentTime: nextTime,
    );
  }

  void reset() {
    _stopPlaybackTimer();
    if (!state.hasPreview) {
      state = const SimulationState();
      return;
    }
    state = state.copyWith(
      status: SimulationStatus.paused,
      currentTime: 0.0,
      clearError: true,
    );
  }

  void restoreSnapshot({
    Map<String, dynamic>? resultsJson,
    double currentTime = 0.0,
  }) {
    _stopPlaybackTimer();
    if (resultsJson == null) {
      state = SimulationState(currentTime: currentTime);
      return;
    }

    final results = PreviewResponse.fromJson(resultsJson);
    final playback = results.playback;
    final clampedTime = playback == null
        ? currentTime
        : currentTime.clamp(0.0, playback.durationMs).toDouble();
    state = SimulationState(
      status: SimulationStatus.completed,
      transportMode: PreviewTransportMode.none,
      results: results,
      playback: playback,
      currentTime: clampedTime,
      selectedNodeId: _defaultNodeId(playback),
    );
  }

  void setCurrentTime(double time) {
    if (!state.hasPreview) {
      return;
    }
    final duration = state.durationMs;
    state = state.copyWith(
      currentTime: duration <= 0 ? time : time.clamp(0.0, duration).toDouble(),
    );
  }

  void setSpeed(double speed) {
    state = state.copyWith(speed: speed);
  }

  void selectNode(String? nodeId) {
    state = state.copyWith(
      selectedNodeId: nodeId,
      clearSelectedNodeId: nodeId == null,
    );
  }

  void _advancePlayback() {
    if (!state.hasPreview || state.durationMs <= 0) {
      _stopPlaybackTimer();
      return;
    }

    final now = DateTime.now();
    final previous = _lastPlaybackTickAt ?? now;
    _lastPlaybackTickAt = now;
    final elapsedMs =
        now.difference(previous).inMilliseconds.toDouble() * state.speed;
    final nextTime = state.currentTime + elapsedMs;
    if (nextTime >= state.durationMs) {
      _stopPlaybackTimer();
      state = state.copyWith(
        status: SimulationStatus.completed,
        currentTime: state.durationMs,
      );
      return;
    }

    state = state.copyWith(
      status: SimulationStatus.running,
      currentTime: nextTime,
    );
  }

  void _stopPlaybackTimer() {
    _playbackTimer?.cancel();
    _playbackTimer = null;
    _lastPlaybackTickAt = null;
  }

  static String? _defaultNodeId(PreviewPlayback? playback) {
    if (playback == null || playback.nodes.isEmpty) {
      return null;
    }
    final activeNode = playback.nodes.where((node) => node.spikeCount > 0);
    if (activeNode.isNotEmpty) {
      return activeNode.first.nodeId;
    }
    return playback.nodes.first.nodeId;
  }
}

/// Backward-compat alias.
final simulationProvider = simulationControllerProvider;
