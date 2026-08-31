import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart' hide AppTheme;

import 'package:neuro_toolkit/features/neurocnl/models/studio_result_visualization.dart'
    show StudioVisualizationContext;
import 'package:neuro_toolkit/features/neurocnl/providers/api_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/canvas/canvas_provider.dart'
    show CanvasTab, canvasProvider;
import 'package:neuro_toolkit/features/neurocnl/providers/canvas/simulation_provider.dart' as canvas_sim;
import 'package:neuro_toolkit/features/neurocnl/providers/studio_result_session_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/training_mode_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/screens/canvas/canvas_screen.dart';
import 'package:neuro_toolkit/features/neurocnl/services/api_client.dart' show ActivityFetchException;
import 'package:neuro_toolkit/features/neurocnl/theme/app_theme.dart';
import 'package:neuro_toolkit/features/neurocnl/utils/canvas_projection_utils.dart'
    show matchSpikeRatesToNodeIds, resolveActivityLayerLabels;
import 'package:neuro_toolkit/features/neurocnl/utils/npy_parser.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/canvas/spike_playback_transport.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/studio_overlay_metrics.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/deployment/deployment_feature.dart' show targetLabel;
import 'package:neuro_toolkit/features/neurocnl/features/studio/shared/studio_shared.dart' show KeepAliveWrapper;
import 'package:neuro_toolkit/features/neurocnl/features/studio/workflow/workflow_feature.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/workflow/steps/activity_comparison_data.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/workflow/steps/platform_summary.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/workflow/steps/results_comparison/comparison_view.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/workflow/steps/results_step/network_playback_panel.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/workflow/steps/results_step/support.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/workflow/steps/results_step/weights_view_tab.dart';

class StudioResultVisualizer extends ConsumerStatefulWidget {
  const StudioResultVisualizer({
    super.key,
    required this.visualizationContext,
    this.controlledView,
    this.showViewSwitch = true,
    this.showDataSourceDisplay = true,
    this.applyOverlayInset = true,
  });

  final StudioVisualizationContext visualizationContext;
  final StudioResultView? controlledView;
  final bool showViewSwitch;
  final bool showDataSourceDisplay;
  final bool applyOverlayInset;

  @override
  ConsumerState<StudioResultVisualizer> createState() =>
      _StudioResultVisualizerState();
}

class _StudioResultVisualizerState extends ConsumerState<StudioResultVisualizer>
    with SingleTickerProviderStateMixin {
  String? _activePlatform;
  int _scrubberEpoch = 0;
  late StudioResultView _view;
  bool _useHardwareArchitecture = false;
  bool _compareMode = false;
  ActivityComparisonData? _activityComparison;
  late final SpikePlaybackSession _epochPlaybackSession;
  bool _loopEpochPlayback = true;

  // ── Shared playback clock ──────────────────────────────────────────────
  // The play/pause + progress transport lives in the context bar next to the
  // epoch indicator, but the clock that drives Raster and Grid used to be owned
  // by each view's own AnimationController. Lifting it here means one transport
  // can show (and drive) both views, and position survives a Grid/Raster switch.
  late final AnimationController _playbackController;

  /// The data identity (`layer@epoch@loadedEpoch`) the clock is currently bound
  /// to; the transport and both views read the same clock, so a change of clip
  /// resets it (restart paused) instead of replaying the previous selection.
  String _clipId = '';
  double _clipDurationMs = 0.0;

  /// Newest scrubber max index, recorded during `build` so the clock's
  /// completion listener can advance epochs.
  int _scrubMaxIndex = 0;

  // ── Activity export, owned here rather than in each consumer ────────────
  // The main playback panel and the sidebar's Dynamics tab render the same
  // export, and each used to fetch its own copy with its own bucket selection.
  // That meant two HTTP requests per epoch, a layer picker in one place that
  // didn't move the other, and — because the sidebar's fetch ran once in
  // initState with no epoch — a sidebar permanently pinned to the last
  // captured epoch while the main view showed an earlier one. One fetch here
  // keeps them honest, and gives the epoch scrubber the captured-epoch list it
  // needs to draw its tick marks.
  Map<String, NpyArray>? _activityArrays;
  String? _selectedLayer;
  List<int> _availableEpochs = const [];
  int? _loadedEpoch;
  bool _isLoadingActivity = false;
  String? _activityError;
  // Guards against a slow response for a previously-selected epoch landing
  // after a newer one and clobbering it.
  int _activityRequestId = 0;
  // The (platform, resolved epoch) a fetch has already been started for, so the
  // per-build post-frame trigger doesn't refire for a target already handled.
  String? _activityRequestKey;

  // Memoised on the *identity* of the source array, which is stable for as long
  // as one export is loaded. Both consumers (playback panel and the sidebar's
  // Dynamics tab) render the same bucket, so a cache of one serves both and the
  // parse happens once per export instead of twice per build.
  NpyArray? _resolvedRasterSource;
  ResolvedActivityRaster? _resolvedRaster;

  /// The selected layer's raster, resolved at most once per loaded export.
  ///
  /// Read from `build()`. It caches rather than mutating anything observable —
  /// which is the point: handing playback a stable raster identity is what stops
  /// an unrelated rebuild from rewinding it.
  ResolvedActivityRaster get _activityRaster {
    final layer = _selectedLayer;
    final source = layer == null ? null : _activityArrays?[layer];
    final cached = _resolvedRaster;
    if (cached != null && identical(source, _resolvedRasterSource)) {
      return cached;
    }
    _resolvedRasterSource = source;
    return _resolvedRaster = resolveActivityRaster(source);
  }

  // Cached notifier reference — safe to call in dispose() without using ref.
  late TrainingMode _trainingModeNotifier;

  @override
  void initState() {
    super.initState();
    _view = widget.controlledView ?? StudioResultView.grid;
    _restoreSelection(
      widget.visualizationContext.sourceSnapshot?.selection,
      restoreView: widget.controlledView == null,
    );
    _trainingModeNotifier = ref.read(trainingModeProvider.notifier);
    _epochPlaybackSession = SpikePlaybackSession()
      ..addListener(_onEpochPlaybackSessionChanged);
    _playbackController = AnimationController(
      vsync: this,
      duration: Duration.zero,
    );
    _playbackController.addStatusListener(_onPlaybackStatusChanged);
  }

  @override
  void didUpdateWidget(covariant StudioResultVisualizer oldWidget) {
    super.didUpdateWidget(oldWidget);
    final previous = oldWidget.visualizationContext.sourceSnapshot;
    final next = widget.visualizationContext.sourceSnapshot;
    if (previous?.id != next?.id) {
      _restoreSelection(
        next?.selection,
        restoreView: widget.controlledView == null,
      );
      _resetActivityExport();
      _useHardwareArchitecture = false;
    }
    if (widget.visualizationContext.matchedHardwareOverlay == null) {
      _useHardwareArchitecture = false;
    }
    if (widget.controlledView != null &&
        widget.controlledView != oldWidget.controlledView) {
      _view = widget.controlledView!;
      if (_view == StudioResultView.architecture) _stopEpochPlayback();
    }
  }

  void _restoreSelection(
    StudioVisualizationSelection? selection, {
    bool restoreView = true,
  }) {
    if (selection == null) return;
    if (restoreView) _view = selection.view;
    _activePlatform = selection.platform;
    _scrubberEpoch = selection.epochIndex;
    _selectedLayer = selection.layer;
  }

  void _persistSelection({
    StudioResultView? view,
    String? platform,
    int? epochIndex,
    String? layer,
    bool clearLayer = false,
  }) {
    final snapshot = widget.visualizationContext.sourceSnapshot;
    if (snapshot == null) return;
    ref
        .read(studioResultSessionProvider.notifier)
        .updateSelection(
          snapshot.selection.copyWith(
            view: view ?? _view,
            platform: platform ?? _activePlatform,
            epochIndex: epochIndex ?? _scrubberEpoch,
            layer: layer ?? _selectedLayer,
            clearLayer: clearLayer,
          ),
        );
  }

  void _resetActivityExport() {
    _activityArrays = null;
    _selectedLayer = null;
    _availableEpochs = const <int>[];
    _loadedEpoch = null;
    _activityError = null;
    _activityRequestKey = null;
    _resolvedRasterSource = null;
    _resolvedRaster = null;
  }

  @override
  void dispose() {
    _playbackController
      ..removeStatusListener(_onPlaybackStatusChanged)
      ..dispose();
    _epochPlaybackSession
      ..removeListener(_onEpochPlaybackSessionChanged)
      ..dispose();
    // Leaving results — clear spike-rate overlay so canvas returns to normal.
    _trainingModeNotifier.clearDeferred();
    super.dispose();
  }

  void _onEpochPlaybackSessionChanged() {
    _syncPlaybackController();
    if (mounted) setState(() {});
  }

  /// Reflects play/pause and speed from the session onto the shared clock.
  /// Mirrors the per-view `_syncPlaybackSession` the two playback views used to
  /// own before the clock was lifted here.
  void _syncPlaybackController() {
    final session = _epochPlaybackSession;
    if (_clipDurationMs <= 0) return;
    final progress = _playbackController.value;
    _playbackController
      ..stop()
      ..duration = spikePlaybackWallDuration(_clipDurationMs, session.speed)
      ..value = progress;
    if (session.isPlaying && !MediaQuery.disableAnimationsOf(context)) {
      _playbackController.forward(from: progress >= 1.0 ? 0.0 : null);
    }
  }

  /// Advances to the next epoch when a clip finishes while the session is
  /// playing — the clock's replacement for the per-view completion handlers.
  void _onPlaybackStatusChanged(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    if (!_epochPlaybackSession.isPlaying) return;
    _advanceEpochPlayback(_scrubMaxIndex);
  }

  /// Returns the shared playback clock, (re)binding it to [clipId]'s data when
  /// the identity or duration changes (new layer, epoch or export).
  ///
  /// The actual rebind is deferred to after this frame: mutating the clock here
  /// would notify the context bar's transport (an `AnimatedBuilder` on this
  /// controller) mid-build.
  AnimationController _clockFor(String clipId, double durationMs) {
    if (_clipId == clipId && _clipDurationMs == durationMs) {
      return _playbackController;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _bindClock(clipId, durationMs);
    });
    return _playbackController;
  }

  /// Points the shared clock at [clipId]'s export, restarting from zero (paused
  /// unless the session is already playing, so auto-advance resumes seamlessly).
  void _bindClock(String clipId, double durationMs) {
    if (_clipId == clipId && _clipDurationMs == durationMs) return;
    _clipId = clipId;
    _clipDurationMs = durationMs;
    final session = _epochPlaybackSession;
    _playbackController
      ..stop()
      ..duration = spikePlaybackWallDuration(durationMs, session.speed)
      ..value = 0.0;
    if (session.isPlaying &&
        durationMs > 0 &&
        !MediaQuery.disableAnimationsOf(context)) {
      _playbackController.forward(from: 0.0);
    }
  }

  void _onPlaybackSeek(double ms) {
    _epochPlaybackSession.setPlaying(false);
    _playbackController.stop();
    _playbackController.value = _clipDurationMs <= 0
        ? 0.0
        : (ms / _clipDurationMs).clamp(0.0, 1.0);
  }

  /// The play/pause + progress transport, shown in the context bar next to the
  /// epoch indicator and shared by the Raster and Grid views. Scoped rebuild on
  /// the clock and session keeps the per-tick cost down to just this row.
  Widget _buildPlaybackTransport(double durationMs) {
    final session = _epochPlaybackSession;
    return AnimatedBuilder(
      animation: Listenable.merge([_playbackController, session]),
      builder: (context, _) => SpikePlaybackTransport(
        isPlaying: session.isPlaying,
        speed: session.speed,
        currentTimeMs: _playbackController.value * durationMs,
        duration: durationMs,
        onTogglePlay: session.toggle,
        onSpeedChanged: session.setSpeed,
        onSeek: _onPlaybackSeek,
      ),
    );
  }

  Widget _buildLayerDropdown(
    Map<String, String> layerLabels,
    TextStyle? labelStyle,
  ) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Layer', style: labelStyle),
        const SizedBox(width: 6),
        DropdownButton<String>(
          value: _selectedLayer,
          isDense: true,
          underline: const SizedBox.shrink(),
          items: [
            for (final entry in layerLabels.entries)
              DropdownMenuItem(value: entry.key, child: Text(entry.value)),
          ],
          onChanged: (v) {
            if (v != null) {
              setState(() => _selectedLayer = v);
              _persistSelection(layer: v);
            }
          },
        ),
      ],
    );
  }

  Widget _buildEpochRow(
    TrainingEpochEvent? selectedEpoch,
    int totalEpochs,
    ZetaColors colors,
    TextStyle? labelStyle,
  ) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Epoch ${selectedEpoch?.epoch ?? 1} / $totalEpochs',
          style: labelStyle,
        ),
        const SizedBox(width: 4),
        IconButton(
          tooltip: 'Loop',
          icon: Icon(
            ZetaIcons.repeat,
            size: 18,
            color: _loopEpochPlayback ? colors.mainPrimary : colors.mainSubtle,
          ),
          onPressed: () =>
              setState(() => _loopEpochPlayback = !_loopEpochPlayback),
        ),
      ],
    );
  }

  void _stopEpochPlayback() => _epochPlaybackSession.setPlaying(false);

  void _advanceEpochPlayback(int maxIndex) {
    if (!_epochPlaybackSession.isPlaying) return;
    if (_scrubberEpoch < maxIndex) {
      setState(() => _scrubberEpoch++);
      _persistSelection();
      return;
    }
    if (_loopEpochPlayback) {
      setState(() => _scrubberEpoch = 0);
      _persistSelection();
    } else {
      _stopEpochPlayback();
    }
  }

  /// Closest captured epoch to [target]; `null` when nothing is captured yet
  /// or the scrubber has no epoch. Activity is only captured every few epochs
  /// (`_ACTIVITY_CAPTURE_CADENCE_EPOCHS` in `notebook.py`), so requesting the
  /// exact scrubbed epoch would usually 404.
  int? _nearestCapturedEpoch(int? target) {
    if (target == null || _availableEpochs.isEmpty) return null;
    return _availableEpochs.reduce(
      (a, b) => (a - target).abs() <= (b - target).abs() ? a : b,
    );
  }

  /// Fetches the activity export for [platform] at (the nearest capture to)
  /// [epoch].
  ///
  /// Called from a post-frame callback on every build, so it must be a strict
  /// no-op once a given (platform, epoch) has been handled — anything that
  /// unconditionally calls `setState` here turns into an infinite
  /// build -> setState -> build loop.
  Future<void> _loadActivity(String platform, int? epoch) async {
    final jobId = widget
        .visualizationContext
        .sourceSnapshot
        ?.platforms[platform]
        ?.completedJob
        ?.jobId;
    if (jobId == null) {
      // No run for this platform. Record it once; repeating the setState every
      // frame would spin forever.
      if (_activityError == null) {
        setState(() {
          _isLoadingActivity = false;
          _activityError =
              'Detailed activity is no longer available. Run again to '
              'regenerate details.';
        });
      }
      return;
    }

    final requestEpoch = _nearestCapturedEpoch(epoch) ?? epoch;
    final requestKey = '$platform@$requestEpoch';
    // Already loaded, already in flight, or already failed for this exact
    // target — nothing to do.
    if (requestKey == _activityRequestKey) return;
    _activityRequestKey = requestKey;

    final requestId = ++_activityRequestId;
    setState(() {
      _isLoadingActivity = true;
      _activityError = null;
    });

    try {
      final client = ref.read(apiClientProvider);
      final result = await client.getTrainingActivityNpy(
        jobId,
        epoch: requestEpoch,
      );
      final arrays = NpyParser.extractActivityArrays(result.bytes);
      if (!mounted || requestId != _activityRequestId) return;
      setState(() {
        _activityArrays = arrays;
        if (result.availableEpochs.isNotEmpty) {
          _availableEpochs = result.availableEpochs;
        }
        _loadedEpoch = result.servedEpoch ?? requestEpoch;
        _isLoadingActivity = false;
        // Keep the user's layer choice across epochs; only fall back when it
        // no longer exists in the newly-loaded export.
        if (_selectedLayer == null || !arrays.containsKey(_selectedLayer)) {
          _selectedLayer = arrays.keys.isNotEmpty ? arrays.keys.first : null;
        }
      });
    } on ActivityFetchException catch (e) {
      if (!mounted || requestId != _activityRequestId) return;
      // The requested epoch wasn't captured — learn which ones were and retry
      // once against the nearest of those.
      if (e.availableEpochs.isNotEmpty) {
        setState(() => _availableEpochs = e.availableEpochs);
        final retryEpoch = _nearestCapturedEpoch(epoch);
        if (retryEpoch != null && retryEpoch != requestEpoch) {
          await _loadActivity(platform, epoch);
          return;
        }
      }
      setState(() {
        _isLoadingActivity = false;
        _activityError =
            'This activity artifact is no longer available. Run again to '
            'regenerate details.';
      });
    } catch (_) {
      if (!mounted || requestId != _activityRequestId) return;
      setState(() {
        _isLoadingActivity = false;
        _activityError =
            'Activity could not be loaded. Run again to regenerate details.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final visualizationContext = widget.visualizationContext;
    final snapshot = visualizationContext.sourceSnapshot;
    final history =
        snapshot?.history ?? const <String, List<TrainingEpochEvent>>{};
    final platforms =
        snapshot?.platforms.entries
            .where((entry) => entry.value.hasResultData)
            .map((entry) => entry.key)
            .toList(growable: false) ??
        const <String>[];
    final colors = Zeta.of(context).colors;

    if (snapshot == null || platforms.isEmpty) {
      return _buildNoDataView(context, colors);
    }

    final active =
        _activePlatform != null && platforms.contains(_activePlatform)
        ? _activePlatform!
        : platforms.first;
    final epochs = history[active] ?? const <TrainingEpochEvent>[];

    // The scrubber walks real training epochs only. `epochs` is every event
    // the run streamed — one per training epoch, one per validation pass, and
    // one per eval *test batch* (whose `epoch` field is a batch index, not an
    // epoch). Scrubbing that raw list is why a 5-epoch run showed
    // "Epoch 6 / 27" while the sidebar reported 5 epochs. Filtering to the
    // train phase matches the sidebar's own `trainEpochs` split and makes the
    // label a real epoch number.
    final scrubEpochs = epochs.where((e) => e.phase == 'train').toList();

    final maxIndex = scrubEpochs.isEmpty ? 0 : scrubEpochs.length - 1;
    _scrubMaxIndex = maxIndex;
    if (_scrubberEpoch > maxIndex) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _scrubberEpoch = maxIndex);
      });
    }

    final selectedEpoch = scrubEpochs.isEmpty
        ? null
        : scrubEpochs[_scrubberEpoch.clamp(0, maxIndex)];
    // Only compute summaries when compare mode is active (or when determining if compare is available)
    final comparableHistory = <String, List<TrainingEpochEvent>>{
      for (final platform in platforms) platform: history[platform] ?? const [],
    };
    final canCompare = comparableHistory.length >= 2;
    final summaries = (canCompare)
        ? computePlatformSummaries(comparableHistory)
        : const <PlatformSummary>[];

    // ── Compare mode ──────────────────────────────────────────────────────
    if (_compareMode && canCompare) {
      return Stack(
        children: [
          ComparisonView(
            summaries: summaries,
            activityComparison: _activityComparison,
          ),
          Positioned(
            top: 12,
            left: 16,
            child: CompareToggleChip(
              compareMode: true,
              onTap: () => setState(() => _compareMode = false),
            ),
          ),
        ],
      );
    }

    // Drive spike-rate overlay on the canvas — resolve backend rate keys to
    // canvas node ids, same as the live-training write site in run_step.dart.
    // Also clears when the selected epoch carries no rates: this used to only
    // ever write, so badges from a previous epoch lingered on the diagram and
    // silently misattributed themselves to the epoch now selected.
    final hardwareOverlay = visualizationContext.matchedHardwareOverlay;
    final architectureRates =
        _useHardwareArchitecture && hardwareOverlay != null
        ? hardwareOverlay.activity
        : selectedEpoch?.layerSpikeRates ?? const <String, double>{};
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final rates = architectureRates;
      if (rates.isEmpty) {
        ref.read(trainingModeProvider.notifier).clear();
        return;
      }
      final nodes = ref.read(canvasProvider).graph.nodes;
      final mapped = matchSpikeRatesToNodeIds(rates, nodes);
      if (mapped.isNotEmpty) {
        ref.read(trainingModeProvider.notifier).setRates(mapped);
      }
    });

    // Kick off / refresh the shared activity fetch for the selected epoch.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _loadActivity(active, selectedEpoch?.epoch);
      }
    });

    final layerLabels = resolveActivityLayerLabels(
      _activityArrays?.keys ?? const <String>[],
      ref.watch(canvasProvider).graph.nodes,
    );

    final contextLabelStyle = Theme.of(context).textTheme.labelSmall?.copyWith(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final bool isCompact =
            constraints.maxWidth < NmtkShellTokens.compactBreakpoint;
        final jobId = snapshot.platforms[active]?.completedJob?.jobId;
        final sourceLabel = 'Source run · ${targetLabel(active)}';
        final visualizationLabel =
            _view == StudioResultView.architecture &&
                _useHardwareArchitecture &&
                hardwareOverlay != null
            ? hardwareOverlay.provenance.label
            : sourceLabel;
        final sourceUnavailable =
            jobId == null && _view != StudioResultView.architecture
            ? 'Detailed result artifact is no longer available. Run again to '
                  'regenerate details.'
            : null;
        final showResultHeader =
            widget.showViewSwitch ||
            widget.showDataSourceDisplay ||
            (_view == StudioResultView.architecture &&
                hardwareOverlay != null) ||
            platforms.length > 1 ||
            canCompare;

        final topInset = widget.applyOverlayInset
            ? StudioOverlayMetrics.maybeOf(context)?.stepperBottom ?? 0
            : 0.0;

        // Shared playback clock for the Raster and Grid views. Only meaningful
        // once a raster export is loaded; the transport shows in the context bar
        // right next to the epoch indicator, and both views consume this clock.
        final playbackClip = _activityRaster;
        final showPlaybackTransport =
            playbackClip.rasterSource != null &&
            _view != StudioResultView.architecture &&
            playbackClip.duration > 1;
        final playbackClock = showPlaybackTransport
            ? _clockFor(
                '$_selectedLayer@${selectedEpoch?.epoch}@$_loadedEpoch',
                playbackClip.duration,
              )
            : null;

        return Padding(
          padding: EdgeInsets.only(top: topInset),
          child: Column(
            children: [
              // ── The one tab row: Architecture | Grid | Raster ────────────
              // A single flat row of siblings. Platform tabs and the compare
              // toggle sit to the right in a visually distinct style, since
              // they select *which run*, not which view of it.
              if (showResultHeader)
                Container(
                  key: const Key('studio-result-source-header'),
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: AppTheme.borderOf(context)),
                    ),
                  ),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        if (widget.showViewSwitch)
                          ResultsViewSwitch(
                            view: _view,
                            onChanged: (v) {
                              if (v == StudioResultView.architecture) {
                                _stopEpochPlayback();
                              }
                              setState(() => _view = v);
                              _persistSelection(view: v);
                            },
                          ),
                        if (_view == StudioResultView.architecture &&
                            hardwareOverlay != null) ...[
                          const SizedBox(width: 8),
                          ResultsPlatformTab(
                            label: _useHardwareArchitecture
                                ? 'Use source activity'
                                : 'Use Akida activity',
                            selected: _useHardwareArchitecture,
                            onTap: () {
                              setState(
                                () => _useHardwareArchitecture =
                                    !_useHardwareArchitecture,
                              );
                            },
                          ),
                        ],
                        if (widget.showViewSwitch) const SizedBox(width: 8),
                        if (widget.showDataSourceDisplay)
                          NmtkInfoChip(
                            icon:
                                _useHardwareArchitecture &&
                                    _view == StudioResultView.architecture
                                ? ZetaIcons.memory
                                : ZetaIcons.analytics,
                            label: 'Data',
                            value: visualizationLabel,
                          ),
                        if (platforms.length > 1) ...[
                          const SizedBox(width: 8),
                          for (final p in platforms)
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ResultsPlatformTab(
                                label: targetLabel(p),
                                selected: p == active,
                                onTap: () {
                                  _stopEpochPlayback();
                                  setState(() {
                                    _activePlatform = p;
                                    _scrubberEpoch = 0;
                                    // Different run: the previous run's export and
                                    // its captured-epoch list no longer apply.
                                    _activityArrays = null;
                                    _selectedLayer = null;
                                    _availableEpochs = const [];
                                    _loadedEpoch = null;
                                    _activityError = null;
                                    _activityRequestKey = null;
                                  });
                                  _persistSelection(
                                    platform: p,
                                    epochIndex: 0,
                                    clearLayer: true,
                                  );
                                },
                              ),
                            ),
                        ],
                        if (canCompare) ...[
                          const SizedBox(width: 8),
                          CompareToggleChip(
                            compareMode: _compareMode,
                            onTap: () {
                              final enabling = !_compareMode;
                              setState(() => _compareMode = enabling);
                              if (enabling) _fetchActivityComparison();
                            },
                          ),
                        ],
                      ],
                    ),
                  ),
                ),

              // ── Context bar: which layer, which epoch ───────────────────
              // Everything that qualifies what the visualization below is
              // showing, in one compact row at the top. This used to be split
              // between a layer row here, an epoch card floating over the
              // bottom of the visualization, and a "nearest capture" note
              // inside the view itself. Deliberately outside the tab row's
              // horizontal SingleChildScrollView: a slider inside a horizontal
              // scrollable fights it for drag gestures. On compact widths the
              // layer picker and epoch scrubber stack instead of sharing one
              // row — a single row with both plus the scrubber overflowed at
              // phone widths.
              if ((_view != StudioResultView.architecture &&
                      layerLabels.length > 1) ||
                  scrubEpochs.length > 1)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                  child: isCompact
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (_view != StudioResultView.architecture &&
                                layerLabels.length > 1) ...[
                              _buildLayerDropdown(
                                layerLabels,
                                contextLabelStyle,
                              ),
                              const SizedBox(height: 4),
                            ],
                            if (scrubEpochs.length > 1) ...[
                              _buildEpochRow(
                                selectedEpoch,
                                scrubEpochs.length,
                                colors,
                                contextLabelStyle,
                              ),
                            ],
                            if (showPlaybackTransport) ...[
                              const SizedBox(height: 8),
                              _buildPlaybackTransport(playbackClip.duration),
                            ],
                          ],
                        )
                      : Row(
                          children: [
                            if (_view != StudioResultView.architecture &&
                                layerLabels.length > 1) ...[
                              _buildLayerDropdown(
                                layerLabels,
                                contextLabelStyle,
                              ),
                              const SizedBox(width: 16),
                            ],
                            if (scrubEpochs.length > 1) ...[
                              _buildEpochRow(
                                selectedEpoch,
                                scrubEpochs.length,
                                colors,
                                contextLabelStyle,
                              ),
                            ],
                            if (showPlaybackTransport) ...[
                              const SizedBox(width: 16),
                              SizedBox(
                                width: 360,
                                child: _buildPlaybackTransport(
                                  playbackClip.duration,
                                ),
                              ),
                            ],
                          ],
                        ),
                ),

              // ── Content area ────────────────────────────────────────────
              Expanded(
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: IndexedStack(
                        index: _view.stackIndex,
                        children: [
                          const KeepAliveWrapper(
                            child: CanvasScreen(
                              lockedTab: CanvasTab.architecture,
                              disableInspectorOverlay: true,
                              disableEditingChrome: true,
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: NetworkPlaybackPanel(
                              renderMode: _view,
                              arrays: _activityArrays,
                              selectedLayer: _selectedLayer,
                              resolved: _activityRaster,
                              layerLabels: layerLabels,
                              isLoading: _isLoadingActivity,
                              error: sourceUnavailable ?? _activityError,
                              loadedEpoch: _loadedEpoch,
                              playbackEpoch: selectedEpoch?.epoch,
                              playbackSession: _epochPlaybackSession,
                              playbackController: playbackClock,
                              onPlaybackComplete: () =>
                                  _advanceEpochPlayback(maxIndex),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: WeightsViewTab(
                              jobId: jobId,
                              unavailableMessage: sourceUnavailable,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Aggregate hardware activity and source spike rates use
                    // the same architecture overlay, but the provenance chip
                    // above makes their origin explicit.
                    if (_view == StudioResultView.architecture &&
                        architectureRates.isNotEmpty)
                      Positioned(
                        top: 12,
                        right: 12,
                        child: ResultsSpikeRateLegend(rates: architectureRates),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Empty visualization state when no run has streamed any epochs yet.
  Widget _buildNoDataView(BuildContext context, ZetaColors colors) {
    final topInset = widget.applyOverlayInset
        ? StudioOverlayMetrics.maybeOf(context)?.stepperBottom ?? 0
        : 0.0;
    return Padding(
      padding: EdgeInsets.only(top: topInset),
      child: Column(
        children: [
          if (widget.showViewSwitch || widget.showDataSourceDisplay)
            Container(
              key: const Key('studio-result-source-header'),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: AppTheme.borderOf(context)),
                ),
              ),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    if (widget.showViewSwitch) ...[
                      ResultsViewSwitch(
                        view: _view,
                        onChanged: (view) => setState(() => _view = view),
                      ),
                      if (widget.showDataSourceDisplay)
                        const SizedBox(width: 8),
                    ],
                    if (widget.showDataSourceDisplay)
                      const NmtkInfoChip(
                        icon: ZetaIcons.analytics,
                        label: 'Data',
                        value: 'Source run unavailable',
                      ),
                  ],
                ),
              ),
            ),
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(ZetaIcons.info, size: 48, color: colors.mainSubtle),
                    const SizedBox(height: 16),
                    Text(
                      'No source-run result is available.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: colors.mainSubtle,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Complete a run in step 5 to use Architecture, Grid, '
                      'Raster, and Weights here.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: colors.mainSubtle,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _fetchActivityComparison() async {
    final snapshot = widget.visualizationContext.sourceSnapshot;
    if (snapshot == null) return;

    // Include the current neurosim canvas simulation if one exists.
    // simulationProvider.results?.jobId is the in-memory neurosim job ID.
    final simJobId = ref.read(canvas_sim.simulationProvider).results?.jobId;
    final allJobs = <Map<String, String>>[
      for (final entry in snapshot.platforms.entries)
        if (entry.value.completedJob case final job?)
          {'job_id': job.jobId, 'label': entry.key, 'service': job.service},
      if (simJobId != null &&
          !snapshot.platforms.values.any(
            (result) => result.completedJob?.jobId == simJobId,
          ))
        {'job_id': simJobId, 'label': 'Nengo', 'service': 'neurosim'},
    ];

    if (allJobs.length < 2) return;
    final client = ref.read(apiClientProvider);
    final data = await fetchActivityComparison(allJobs, client);
    if (mounted) setState(() => _activityComparison = data);
  }
}
