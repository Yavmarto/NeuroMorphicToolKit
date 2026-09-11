import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:neuro_toolkit/features/neurocnl/models/canvas/preview.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/canvas/simulation_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/training_mode_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/services/coactivation_correlation.dart';

part 'coactivation_provider.g.dart';

/// Co-activation correlation state for the network view.
///
/// [snapshot] is the current correlation result (live or review). When
/// [reviewRates] is non-null the provider is in post-run review mode and
/// [reviewRates] carries the per-node rate series the renderer replays at the
/// simulation's current time.
class CoactivationState {
  const CoactivationState({this.snapshot, this.reviewRates, this.revision = 0});

  final CoactivationSnapshot? snapshot;
  final PlaybackRateSeries? reviewRates;
  final int revision;

  bool get isReview => reviewRates != null;

  CoactivationState copyWith({
    CoactivationSnapshot? snapshot,
    PlaybackRateSeries? reviewRates,
    int? revision,
    bool clearSnapshot = false,
    bool clearReview = false,
  }) {
    return CoactivationState(
      snapshot: clearSnapshot ? null : (snapshot ?? this.snapshot),
      reviewRates: clearReview ? null : (reviewRates ?? this.reviewRates),
      revision: revision ?? this.revision,
    );
  }
}

/// "Fire together, wire together" correlation over the per-layer spike rates
/// already streaming through [trainingModeProvider] (live) or a stored
/// [PreviewPlayback] (review).
///
/// Live ingestion is automatic: every non-empty `trainingModeProvider` write
/// appends a sample to the sliding window. When no live rates are present and
/// [simulationProvider] exposes a stored playback, the provider switches to
/// review mode and derives both a correlation snapshot and a replayable rate
/// series. A later live sample returns it to live mode.
///
/// The initial state is also seeded from whatever already exists when the
/// provider is first built (a live stream already running, or a playback that
/// finished before the network view mounted), because the `ref.listen` hooks
/// below only fire on *later* changes.
@riverpod
class CoactivationController extends _$CoactivationController {
  final CoactivationWindow _window = CoactivationWindow();
  bool _review = false;
  bool _seeded = false;

  @override
  CoactivationState build() {
    ref.listen<Map<String, double>?>(trainingModeProvider, (previous, next) {
      if (next == null || next.isEmpty) return;
      // A review snapshot stays intact through later live writes; callers
      // return to live mode explicitly with [reset].
      if (_review) return;
      _window.addSample(next);
      state = state.copyWith(
        snapshot: CoactivationSnapshot.fromWindow(_window),
        revision: state.revision + 1,
      );
    });

    ref.listen<SimulationState>(simulationProvider, (previous, next) {
      final playback = next.playback;
      if (playback == null || identical(previous?.playback, playback)) return;
      // Review mode only applies when no live rates are streaming.
      final live = ref.read(trainingModeProvider);
      if (live != null && live.isNotEmpty) return;
      loadPlayback(playback);
    });

    if (_seeded) return const CoactivationState();
    _seeded = true;

    final live = ref.read(trainingModeProvider);
    if (live != null && live.isNotEmpty) {
      _review = false;
      _window.addSample(live);
      return CoactivationState(
        snapshot: CoactivationSnapshot.fromWindow(_window),
      );
    }

    final playback = ref.read(simulationProvider).playback;
    if (playback != null) {
      final series = PlaybackRateSeries.fromPlayback(playback);
      _review = true;
      return CoactivationState(
        snapshot: CoactivationSnapshot.fromRateSeries(series),
        reviewRates: series,
      );
    }

    return const CoactivationState();
  }

  /// Switches to review mode and derives a correlation snapshot plus a rate
  /// series from [playback].
  void loadPlayback(PreviewPlayback playback) {
    _review = true;
    final series = PlaybackRateSeries.fromPlayback(playback);
    state = state.copyWith(
      snapshot: CoactivationSnapshot.fromRateSeries(series),
      reviewRates: series,
      revision: state.revision + 1,
    );
  }

  /// Returns to live mode and drops all accumulated evidence.
  void reset() {
    _review = false;
    _window.clear();
    state = const CoactivationState();
  }
}

/// Backward-compat alias consumed by the network view widgets.
final coactivationProvider = coactivationControllerProvider;
