import 'package:flutter/material.dart';

import 'package:neuro_toolkit/features/neurocnl/models/studio_result_session.dart' show StudioResultView;
import 'package:neuro_toolkit/features/neurocnl/utils/npy_parser.dart' show NpyArray;
import 'package:neuro_toolkit/features/neurocnl/widgets/canvas/animated_snn_playback.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/canvas/spike_playback_transport.dart'
    show SpikePlaybackSession;
import 'package:neuro_toolkit/features/neurocnl/features/studio/workflow/steps/results_step/support.dart' show ResolvedActivityRaster;
import 'package:neuro_toolkit/features/neurocnl/features/studio/workflow/steps/results_step/tile_grid_playback.dart';

class NetworkPlaybackPanel extends StatelessWidget {
  const NetworkPlaybackPanel({
    super.key,
    required this.renderMode,
    required this.arrays,
    required this.selectedLayer,
    required this.resolved,
    required this.layerLabels,
    required this.isLoading,
    required this.error,
    required this.loadedEpoch,
    required this.playbackEpoch,
    required this.playbackSession,
    this.playbackController,
    required this.onPlaybackComplete,
  });

  final StudioResultView renderMode;
  final Map<String, NpyArray>? arrays;
  final String? selectedLayer;

  /// [selectedLayer]'s export, reduced by [_StudioResultVisualizerState].
  /// Resolving it here instead handed the playback widgets a new raster `Map`
  /// on every rebuild.
  final ResolvedActivityRaster resolved;

  final Map<String, String> layerLabels;
  final bool isLoading;
  final String? error;

  /// Epoch the loaded export came from. Reported by the epoch bar at the top of
  /// the screen, not here — epoch information belongs in exactly one place.
  final int? loadedEpoch;
  final int? playbackEpoch;
  final SpikePlaybackSession? playbackSession;

  /// Shared clock lifted into [_StudioResultVisualizerState] so one transport in
  /// the context bar drives both Raster and Grid. When null (no raster export),
  /// the views fall back to their own internal clock.
  final AnimationController? playbackController;
  final VoidCallback onPlaybackComplete;

  @override
  Widget build(BuildContext context) {
    final layer = selectedLayer;
    final data = arrays;

    if (isLoading && data == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (error != null) {
      return Center(child: Text(error!));
    }
    if (data == null || layer == null || data.isEmpty) {
      return const Center(
        child: Text('No dynamics data available for this run.'),
      );
    }

    if (resolved.rasterSource == null) {
      return const Center(
        child: Text('Playback unavailable for this training run.'),
      );
    }

    // Keyed on layer, scrubbed epoch, and loaded data version so switching any of them
    // rebuilds the playback state instead of replaying the previous selection.
    // The same string is the grid's data identity — see `TileGridPlayback.rasterId`.
    final rasterId = '$layer@$playbackEpoch@$loadedEpoch';
    final playbackKey = ValueKey(rasterId);
    return switch (renderMode) {
      StudioResultView.raster => AnimatedSnnPlayback(
        key: playbackKey,
        spikes: resolved.raster,
        duration: resolved.duration,
        populationName: layerLabels[layer] ?? layer,
        // The Layer dropdown above already names the population.
        showHeader: false,
        playbackSession: playbackSession,
        playbackController: playbackController,
        showTransport: false,
        onPlaybackComplete: onPlaybackComplete,
      ),
      // Grid is the default for anything that isn't the raster; the
      // architecture view never routes here.
      _ => TileGridPlayback(
        key: playbackKey,
        rasterId: rasterId,
        raster: resolved.raster,
        duration: resolved.duration,
        playbackSession: playbackSession,
        playbackController: playbackController,
        showTransport: false,
        onPlaybackComplete: onPlaybackComplete,
      ),
    };
  }
}
