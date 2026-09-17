import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:neuro_toolkit/features/neurocnl/models/canvas/canvas.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/canvas/canvas_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/coactivation_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/training_mode_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/services/coactivation_correlation.dart';
import 'package:neuro_toolkit/features/neurocnl/utils/force_directed_layout.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/brainviz_force_3d_view.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/canvas/spike_playback_transport.dart';

/// Results-tab brainviz: per-neuron force-directed layout driven by the same
/// raster export and shared playback clock as the Grid/Raster tabs, or — while
/// a training job is running — the live SSE spike-rate stream from
/// [trainingModeProvider].
class ResultsBrainvizPanel extends ConsumerStatefulWidget {
  const ResultsBrainvizPanel({
    super.key,
    required this.rasterId,
    required this.raster,
    required this.duration,
    this.playbackSession,
    this.playbackController,
    required this.onPlaybackComplete,
    this.isLoading = false,
    this.error,
    this.liveTraining = false,
  });

  final String rasterId;
  final Map<String, List<double>> raster;
  final double duration;
  final SpikePlaybackSession? playbackSession;
  final AnimationController? playbackController;
  final VoidCallback onPlaybackComplete;
  final bool isLoading;
  final String? error;

  /// When true and [trainingModeProvider] is streaming rates, the panel renders
  /// the canvas layer graph with incremental co-activation instead of the stored
  /// per-neuron raster playback path.
  final bool liveTraining;

  @override
  ConsumerState<ResultsBrainvizPanel> createState() =>
      _ResultsBrainvizPanelState();
}

class _ResultsBrainvizPanelState extends ConsumerState<ResultsBrainvizPanel>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late CanvasGraph _graph;
  final CoactivationWindow _window = CoactivationWindow(
    capacity: kCoactivationDefaultWindowCapacity,
    minSamples: 6,
  );
  CoactivationSnapshot _snapshot = const CoactivationSnapshot();
  int _lastFilledBin = -1;
  int _displayBin = -1;
  Map<String, double> _displayActivity = const <String, double>{};
  String _loadedRasterId = '';

  bool get _usesSharedClock => widget.playbackController != null;

  double get _currentTimeMs => _controller.value * widget.duration;

  @override
  void initState() {
    super.initState();
    _controller =
        widget.playbackController ??
        AnimationController(
          vsync: this,
          duration: spikePlaybackWallDuration(widget.duration, 1.0),
        );
    _controller.addListener(_onClock);
    _loadRaster();
  }

  @override
  void didUpdateWidget(covariant ResultsBrainvizPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.liveTraining && !oldWidget.liveTraining) {
      ref.read(coactivationProvider.notifier).reset();
      _window.clear();
      _snapshot = const CoactivationSnapshot();
      _lastFilledBin = -1;
    }
    if (widget.rasterId != oldWidget.rasterId ||
        widget.duration != oldWidget.duration) {
      _loadRaster();
    }
    if (widget.playbackController != oldWidget.playbackController) {
      _controller.removeListener(_onClock);
      _controller =
          widget.playbackController ??
          AnimationController(
            vsync: this,
            duration: spikePlaybackWallDuration(widget.duration, 1.0),
          );
      _controller.addListener(_onClock);
      _onClock();
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onClock);
    if (!_usesSharedClock) {
      _controller.dispose();
    }
    super.dispose();
  }

  void _loadRaster() {
    _loadedRasterId = widget.rasterId;
    _graph = neuronRasterGraph(widget.raster);
    _window.clear();
    _snapshot = const CoactivationSnapshot();
    _lastFilledBin = -1;
    _displayBin = -1;
    _displayActivity = const <String, double>{};
    if (!_usesSharedClock) {
      _controller
        ..stop()
        ..duration = spikePlaybackWallDuration(widget.duration, 1.0)
        ..value = 0;
    }
    _onClock();
  }

  void _onClock() {
    if (!mounted || widget.raster.isEmpty || widget.duration <= 0) return;

    final binMs = kCoactivationDefaultBinMs;
    final binCount = (widget.duration / binMs).ceil();
    if (binCount == 0) return;

    final timeMs = _currentTimeMs.clamp(0.0, widget.duration);
    final targetBin = (timeMs / binMs).floor().clamp(0, binCount - 1);

    var dirty = false;
    if (targetBin < _lastFilledBin) {
      _window.clear();
      _lastFilledBin = -1;
      _displayBin = -1;
      dirty = true;
    }

    while (_lastFilledBin < targetBin) {
      _lastFilledBin += 1;
      final sample = _binnedRatesForBin(_lastFilledBin, binMs);
      if (sample.isNotEmpty) {
        _window.addSample(sample);
        dirty = true;
      }
    }

    if (dirty) {
      _snapshot = CoactivationSnapshot.fromWindow(_window);
    }

    if (targetBin != _displayBin) {
      _displayBin = targetBin;
      _displayActivity = _binnedRatesForBin(targetBin, binMs);
      dirty = true;
    }

    if (dirty) {
      setState(() {});
    }
  }

  Map<String, double> _binnedRatesForBin(int bin, double binMs) {
    var peak = 0.0;
    final counts = <String, double>{};
    for (final entry in widget.raster.entries) {
      var count = 0.0;
      for (final spikeMs in entry.value) {
        final spikeBin = (spikeMs / binMs).floor();
        if (spikeBin == bin) count += 1;
      }
      counts[entry.key] = count;
      if (count > peak) peak = count;
    }
    if (peak <= 0) {
      return counts.map((id, _) => MapEntry(id, 0.0));
    }
    return counts.map((id, count) => MapEntry(id, count / peak));
  }

  bool _useLiveFeed(Map<String, double>? liveRates) =>
      widget.liveTraining && liveRates != null && liveRates.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final liveRates = ref.watch(trainingModeProvider);
    final useLive = _useLiveFeed(liveRates);

    if (widget.isLoading && widget.raster.isEmpty && !useLive) {
      return const Center(child: CircularProgressIndicator());
    }
    if (widget.error != null && !useLive) {
      return Center(child: Text(widget.error!));
    }
    if (!useLive && (widget.raster.isEmpty || widget.duration <= 0)) {
      if (widget.liveTraining) {
        return const Center(
          child: Text('Waiting for live training activations…'),
        );
      }
      return const Center(
        child: Text('No dynamics data available for this run.'),
      );
    }

    final graph = useLive ? ref.watch(canvasProvider).graph : _graph;
    final activity = useLive ? liveRates! : _displayActivity;
    final snapshot = useLive
        ? (ref.watch(coactivationProvider).snapshot ??
              const CoactivationSnapshot())
        : _snapshot;
    final clusterIndices = coactivationClusterIndices(snapshot);
    final viewKey = useLive ? 'live-training' : _loadedRasterId;

    return BrainvizForce3DView(
      key: ValueKey(viewKey),
      graph: graph,
      activity: activity,
      correlationMatrix: snapshot.correlations,
      nodeClusterIndices: clusterIndices.isEmpty ? null : clusterIndices,
      padding: 32,
    );
  }
}
