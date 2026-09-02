import 'dart:async';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart' hide AppTheme;
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:neuro_toolkit/features/neurocnl/theme/app_theme.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/canvas/spike_playback_transport.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/canvas/time_series_chart.dart'
    show traceColorPalette;

// ---------------------------------------------------------------------------
// Public widget
// ---------------------------------------------------------------------------

/// Animated time-playback view for a single SNN population.
///
/// Plays back a completed simulation by sweeping a time cursor from 0 ms to
/// [duration] ms, progressively revealing spikes and voltage traces.
///
/// Controls:
///   - Play / Pause button
///   - Speed selector: 0.5×, 1×, 2×, 5×
///   - Scrubber slider for manual seek
///   - Elapsed-time label
///   - Pinch/drag to zoom the time axis; double-tap to reset
///
/// Widget layout (top to bottom):
///   1. Toolbar (play/pause, speed, time label)
///   2. Scrubber slider
///   3. Firing-rate bar chart (windows revealed as cursor passes)
///   4. Animated spike raster (spikes appear as cursor sweeps past)
///   5. Animated voltage traces (only available from snnTorch backend)
class AnimatedSnnPlayback extends StatefulWidget {
  /// neuron_id → list of spike times (ms, 0-based within [duration])
  final Map<String, List<double>> spikes;

  /// neuron_id → list of voltage samples
  final Map<String, List<double>>? voltages;

  /// Total simulation duration in milliseconds
  final double duration;

  /// Population name shown in the header
  final String populationName;

  /// Whether to render the `"<populationName> — Activity"` header.
  ///
  /// Pass `false` where the surrounding chrome already names the population —
  /// the Results step selects it through a "Layer" dropdown, so the header
  /// there just repeated the dropdown's value.
  final bool showHeader;

  /// Optional shared state for a sequence of activity clips.
  ///
  /// When omitted, this widget retains its independent playback behavior.
  final SpikePlaybackSession? playbackSession;

  /// Shared clock owned by a parent (the Results step's context bar transport).
  ///
  /// When provided, this widget consumes that clock instead of owning one and
  /// defers completion, session sync and the transport to the parent — set
  /// [showTransport] false in that case so it does not draw its own.
  final AnimationController? playbackController;

  /// Whether to render the play/pause + progress transport.
  ///
  /// Set false when a parent shows a shared transport (see [playbackController]).
  final bool showTransport;

  /// Invoked after this clip completes while [playbackSession] is playing.
  final VoidCallback? onPlaybackComplete;

  /// Shown in place of the raster when [spikes] is empty.
  ///
  /// "No spikes recorded" states the fact and leaves the user to guess the
  /// cause, which is usually knowable — an untrained network's weights are all
  /// zero, so nothing *can* fire. Callers that know why pass it here.
  final String? emptyReason;

  const AnimatedSnnPlayback({
    super.key,
    required this.spikes,
    this.voltages,
    required this.duration,
    this.populationName = '',
    this.showHeader = true,
    this.playbackSession,
    this.playbackController,
    this.showTransport = true,
    this.onPlaybackComplete,
    this.emptyReason,
  });

  @override
  State<AnimatedSnnPlayback> createState() => _AnimatedSnnPlaybackState();
}

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------

class _AnimatedSnnPlaybackState extends State<AnimatedSnnPlayback>
    with TickerProviderStateMixin {
  late AnimationController _controller;
  late AnimationController _zoomHintController;
  double _speed = 1.0;

  // Zoom / pan state
  double _zoomFactor = 1.0;
  double _panMs = 0.0;
  double _canvasWidth = 0.0;
  bool _reduceMotion = false;
  Timer? _zoomHintTimer;

  // Pre-computed from widget.voltages (constant for lifetime of widget)
  List<List<double>> _voltageTraces = const [];
  List<double> _voltageTime = const [];

  // Shared with the Results step's tile grid so the two spike views can't drift
  // apart on timing. Also fixes speed: the previous local version applied its
  // minimum-duration floor *after* dividing by speed, so for any short capture
  // every speed produced identical playback.
  Duration get _wallDuration =>
      spikePlaybackWallDuration(widget.duration, _speed);

  double get _currentTimeMs => _controller.value * widget.duration;

  /// True when a parent owns the clock, so this view must not create, dispose,
  /// sync or reset it, and should defer completion + the transport to that
  /// parent.
  bool get _usesSharedClock => widget.playbackController != null;

  ({double start, double end}) get _visibleRange {
    final windowMs = widget.duration / _zoomFactor;
    final maxPan = math.max(0.0, widget.duration - windowMs);
    final clamped = _panMs.clamp(0.0, maxPan);
    return (start: clamped, end: clamped + windowMs);
  }

  @override
  void initState() {
    super.initState();
    _speed = widget.playbackSession?.speed ?? _speed;
    _controller =
        widget.playbackController ??
        AnimationController(vsync: this, duration: _wallDuration);
    if (!_usesSharedClock) {
      // Start at the end, so the raster arrives fully drawn instead of blank.
      // An empty plot next to a populated one reads as a broken chart rather
      // than an unplayed one, which is exactly how it looked side by side.
      // Play still restarts the reveal from zero — `_togglePlay` already treats
      // a finished clock as "replay from 0". Set before the status listener is
      // attached: landing on the upper bound completes the controller, and the
      // listener calls setState, which initState may not do.
      _controller.value = 1.0;
      _controller.addStatusListener((status) {
        if (status != AnimationStatus.completed) return;
        setState(() {});
        if (widget.playbackSession?.isPlaying == true) {
          widget.onPlaybackComplete?.call();
        }
      });
      widget.playbackSession?.addListener(_syncPlaybackSession);
    }
    _zoomHintController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    // Pre-compute voltage arrays once — avoids per-frame allocation.
    if (widget.voltages != null && widget.voltages!.isNotEmpty) {
      _voltageTraces = widget.voltages!.values.toList();
      final maxLen = _voltageTraces.map((t) => t.length).fold(0, math.max);
      _voltageTime = maxLen > 0
          ? List<double>.generate(maxLen, (i) => i / maxLen * widget.duration)
          : const [];
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (!_usesSharedClock) _syncPlaybackSession();
  }

  @override
  void didUpdateWidget(covariant AnimatedSnnPlayback oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.playbackController != oldWidget.playbackController) {
      if (widget.playbackController != null) {
        _controller = widget.playbackController!;
      } else {
        _controller = AnimationController(vsync: this, duration: _wallDuration);
        _controller.addStatusListener((status) {
          if (status != AnimationStatus.completed) return;
          setState(() {});
          if (widget.playbackSession?.isPlaying == true) {
            widget.onPlaybackComplete?.call();
          }
        });
      }
    }
    if (_usesSharedClock) return;
    if (oldWidget.playbackSession != widget.playbackSession) {
      oldWidget.playbackSession?.removeListener(_syncPlaybackSession);
      widget.playbackSession?.addListener(_syncPlaybackSession);
      if (widget.playbackSession == null) {
        _controller.stop();
        setState(() {});
        return;
      }
    }
    _syncPlaybackSession();
  }

  @override
  void dispose() {
    if (!_usesSharedClock) {
      widget.playbackSession?.removeListener(_syncPlaybackSession);
    }
    _zoomHintTimer?.cancel();
    if (!_usesSharedClock) _controller.dispose();
    _zoomHintController.dispose();
    super.dispose();
  }

  void _togglePlay() {
    final session = widget.playbackSession;
    if (session != null) {
      session.toggle();
      return;
    }
    if (_reduceMotion) return;
    if (_controller.isAnimating) {
      _controller.stop();
    } else if (_controller.value >= 1.0) {
      _controller
        ..duration = _wallDuration
        ..forward(from: 0);
    } else {
      _controller
        ..duration = _wallDuration
        ..forward();
    }
    setState(() {});
  }

  void _onSpeedChanged(double speed) {
    final session = widget.playbackSession;
    if (session != null) {
      session.setSpeed(speed);
      return;
    }
    final wasPlaying = _controller.isAnimating;
    final progress = _controller.value;
    setState(() => _speed = speed);
    _controller
      ..stop()
      ..duration = _wallDuration
      ..value = progress;
    if (wasPlaying && !_reduceMotion) _controller.forward();
  }

  void _onScrub(double ms) {
    final session = widget.playbackSession;
    if (session != null) session.setPlaying(false);
    final wasPlaying = _controller.isAnimating;
    _controller.stop();
    _controller
      ..duration = _wallDuration
      ..value = (ms / widget.duration).clamp(0.0, 1.0);
    if (wasPlaying && !_reduceMotion) _controller.forward();
    setState(() {});
  }

  void _syncPlaybackSession() {
    final session = widget.playbackSession;
    if (session == null) return;
    final progress = _controller.value;
    _speed = session.speed;
    _controller
      ..stop()
      ..duration = _wallDuration
      ..value = progress;
    if (session.isPlaying && !_reduceMotion) {
      _controller.forward(from: progress >= 1.0 ? 0.0 : null);
    }
    if (mounted) setState(() {});
  }

  // ---------------------------------------------------------------------------
  // Zoom / pan gesture handlers
  // ---------------------------------------------------------------------------

  void _onScaleUpdate(ScaleUpdateDetails details) {
    if (details.scale == 1.0 && details.focalPointDelta.dx.abs() < 1.0) return;
    setState(() {
      if (details.scale != 1.0) {
        // Pinch-to-zoom: keep focal point stable.
        final prevZoom = _zoomFactor;
        _zoomFactor = (_zoomFactor * details.scale).clamp(1.0, 20.0);
        if (_canvasWidth > 0 && prevZoom > 0) {
          final prevWindowMs = widget.duration / prevZoom;
          final focalNorm = (details.localFocalPoint.dx / _canvasWidth).clamp(
            0.0,
            1.0,
          );
          final focalMs = _panMs + focalNorm * prevWindowMs;
          final newWindowMs = widget.duration / _zoomFactor;
          _panMs = (focalMs - focalNorm * newWindowMs).clamp(
            0.0,
            math.max(0.0, widget.duration - newWindowMs),
          );
        }
      } else if (_zoomFactor > 1.0 && _canvasWidth > 0) {
        // Horizontal pan (single-finger drag while zoomed).
        final windowMs = widget.duration / _zoomFactor;
        final dragMs = -details.focalPointDelta.dx / _canvasWidth * windowMs;
        _panMs = (_panMs + dragMs).clamp(
          0.0,
          math.max(0.0, widget.duration - windowMs),
        );
      }
    });
    _showZoomHint();
  }

  void _onZoomReset() {
    setState(() {
      _zoomFactor = 1.0;
      _panMs = 0.0;
    });
    _showZoomHint();
  }

  void _showZoomHint() {
    _zoomHintController.forward(from: 0);
    _zoomHintTimer?.cancel();
    _zoomHintTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) _zoomHintController.reverse();
    });
  }

  // ---------------------------------------------------------------------------
  // Firing-rate data
  // ---------------------------------------------------------------------------

  static const _nWindows = 40;

  late final List<double> _firingRates = _computeFiringRates();

  List<double> _computeFiringRates() {
    final rates = List<double>.filled(_nWindows, 0.0);
    final windowSize = widget.duration / _nWindows;
    for (final neuronSpikes in widget.spikes.values) {
      for (final t in neuronSpikes) {
        final idx = (t / windowSize).floor().clamp(0, _nWindows - 1);
        rates[idx] += 1.0;
      }
    }
    final scale = 1000.0 / windowSize;
    for (int i = 0; i < _nWindows; i++) {
      rates[i] = rates[i] * scale;
    }
    return rates;
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  bool get _hasVoltages =>
      _voltageTraces.isNotEmpty &&
      _voltageTraces.any((v) => v.isNotEmpty) &&
      _voltageTime.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = traceColorPalette(context);

    final spikeList = widget.spikes.values.toList();

    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header label — suppressed by callers that already name the
          // population in their own chrome (the Results step names it in its
          // Layer picker, so repeating it there is pure duplication).
          if (widget.showHeader)
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 2),
              child: Text(
                widget.populationName.isNotEmpty
                    ? '${widget.populationName} \u2014 Activity'
                    : 'Population Activity',
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),

          // Transport (play/pause, speed, readout, seek) — shared with the
          // Results step's tile grid so both spike views offer identical
          // controls. AnimatedBuilder scopes the per-tick rebuild to here.
          // Hidden when a parent (the Results step) shows a shared transport
          // next to the epoch indicator instead.
          if (widget.showTransport)
            AnimatedBuilder(
              animation: _controller,
              builder: (context, _) => SpikePlaybackTransport(
                isPlaying: _controller.isAnimating,
                speed: _speed,
                currentTimeMs: _currentTimeMs,
                duration: widget.duration,
                onTogglePlay: _togglePlay,
                onSpeedChanged: _onSpeedChanged,
                onSeek: _onScrub,
              ),
            ),

          // Firing-rate bar chart — scoped rebuild.
          SizedBox(
            height: 44,
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) => _AnimatedFiringRateChart(
                rates: _firingRates,
                duration: widget.duration,
                currentTimeMs: _currentTimeMs,
              ),
            ),
          ),

          const SizedBox(height: 4),

          // Gesture-sensitive canvas area (zoom + pan).
          Expanded(
            child: GestureDetector(
              onScaleUpdate: _onScaleUpdate,
              onDoubleTap: _onZoomReset,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  // Capture width for focal-point math without setState.
                  _canvasWidth = constraints.maxWidth;

                  return Stack(
                    children: [
                      Column(
                        children: [
                          // ── Animated spike raster ──────────────────────
                          Padding(
                            padding: const EdgeInsets.only(left: 4, bottom: 2),
                            child: Text(
                              'Spike Raster',
                              style: theme.textTheme.labelSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          Expanded(
                            flex: _hasVoltages ? 6 : 10,
                            child: Container(
                              decoration: BoxDecoration(
                                color: AppTheme.surfaceOf(context),
                                borderRadius: BorderRadius.circular(
                                  NmtkShellTokens.of(context).radiusSm,
                                ),
                                border: Border.all(
                                  color: AppTheme.borderOf(context),
                                ),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(
                                  NmtkShellTokens.of(context).radiusSm,
                                ),
                                child: spikeList.isEmpty
                                    ? Center(
                                        child: Padding(
                                          padding: const EdgeInsets.all(16),
                                          child: Text(
                                            widget.emptyReason ??
                                                'No spikes recorded.',
                                            textAlign: TextAlign.center,
                                            style: theme.textTheme.bodySmall,
                                          ),
                                        ),
                                      )
                                    : RepaintBoundary(
                                        child: AnimatedBuilder(
                                          animation: _controller,
                                          builder: (context, _) => CustomPaint(
                                            size: Size(
                                              constraints.maxWidth,
                                              constraints.maxHeight,
                                            ),
                                            painter: AnimatedRasterPainter(
                                              spikes: spikeList,
                                              duration: widget.duration,
                                              currentTimeMs: _currentTimeMs,
                                              visibleRange: _visibleRange,
                                              reduceMotion: _reduceMotion,
                                              glowColor: NmtkShellTokens.of(
                                                context,
                                              ).studioPalette.accent,
                                              axisLabelStyle: Zeta.of(context)
                                                  .textStyles
                                                  .bodyXSmall
                                                  .copyWith(
                                                    color:
                                                        AppTheme.textSecondary,
                                                  ),
                                            ),
                                          ),
                                        ),
                                      ),
                              ),
                            ),
                          ),

                          // ── Voltage traces ───────────────────────────
                          if (_hasVoltages) ...[
                            const SizedBox(height: 4),
                            Padding(
                              padding: const EdgeInsets.only(
                                left: 4,
                                bottom: 2,
                              ),
                              child: Text(
                                'Membrane Potential',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            Expanded(
                              flex: 8,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: AppTheme.surfaceOf(context),
                                  borderRadius: BorderRadius.circular(
                                    NmtkShellTokens.of(context).radiusSm,
                                  ),
                                  border: Border.all(
                                    color: AppTheme.borderOf(context),
                                  ),
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(
                                    NmtkShellTokens.of(context).radiusSm,
                                  ),
                                  child: RepaintBoundary(
                                    child: AnimatedBuilder(
                                      animation: _controller,
                                      builder: (context, _) => CustomPaint(
                                        size: Size(
                                          constraints.maxWidth,
                                          constraints.maxHeight,
                                        ),
                                        painter: AnimatedChartPainter(
                                          traces: _voltageTraces,
                                          time: _voltageTime,
                                          colors: colors,
                                          currentTimeMs: _currentTimeMs,
                                          duration: widget.duration,
                                          visibleRange: _visibleRange,
                                          reduceMotion: _reduceMotion,
                                          axisLabelStyle: Zeta.of(context)
                                              .textStyles
                                              .bodyXSmall
                                              .copyWith(
                                                color: AppTheme.textSecondary,
                                              ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),

                      // ── Zoom indicator pill ────────────────────────────
                      if (_zoomFactor > 1.0)
                        Positioned(
                          bottom: 8,
                          left: 0,
                          right: 0,
                          child: IgnorePointer(
                            child: Center(
                              child: FadeTransition(
                                opacity: _zoomHintController,
                                child: _ZoomIndicator(zoomFactor: _zoomFactor),
                              ),
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Zoom indicator chip
// ---------------------------------------------------------------------------

class _ZoomIndicator extends StatelessWidget {
  final double zoomFactor;

  const _ZoomIndicator({required this.zoomFactor});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppTheme.surfaceOf(context).withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(
          NmtkShellTokens.of(context).radiusSm,
        ),
        border: Border.all(color: AppTheme.borderOf(context)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Text(
          '${zoomFactor.toStringAsFixed(1)}×',
          style: Zeta.of(context).textStyles.bodyXSmall.copyWith(
            color: AppTheme.textSecondaryOf(context),
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Animated firing-rate bar chart
// ---------------------------------------------------------------------------

class _AnimatedFiringRateChart extends StatelessWidget {
  final List<double> rates;
  final double duration;
  final double currentTimeMs;

  const _AnimatedFiringRateChart({
    required this.rates,
    required this.duration,
    required this.currentTimeMs,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (rates.isEmpty) return const SizedBox.shrink();

    final maxRate = rates.reduce((a, b) => a > b ? a : b);
    final scale = maxRate > 0 ? 1.0 / maxRate : 0.0;
    final windowSize = duration / rates.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 1),
          child: Text(
            'Population Firing Rate',
            style: theme.textTheme.labelSmall?.copyWith(fontSize: 9),
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final barWidth = constraints.maxWidth / rates.length;
              return Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (int i = 0; i < rates.length; i++)
                    _AnimatedBar(
                      width: barWidth - 0.5,
                      maxHeight: constraints.maxHeight,
                      fraction: rates[i] * scale,
                      // Reveal this bar once the cursor has passed its window.
                      revealed: currentTimeMs >= (i + 1) * windowSize,
                    ),
                ],
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 4, top: 1),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '0 ms',
                style: theme.textTheme.bodySmall?.copyWith(fontSize: 8),
              ),
              Text(
                '${duration.toStringAsFixed(0)} ms',
                style: theme.textTheme.bodySmall?.copyWith(fontSize: 8),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AnimatedBar extends StatelessWidget {
  final double width;
  final double maxHeight;
  final double fraction;
  final bool revealed;

  const _AnimatedBar({
    required this.width,
    required this.maxHeight,
    required this.fraction,
    required this.revealed,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 80),
      width: width,
      height: revealed ? fraction * maxHeight : 0,
      color: Color.lerp(AppTheme.primaryDim, AppTheme.primary, fraction),
    );
  }
}

// ---------------------------------------------------------------------------
// AnimatedRasterPainter
// ---------------------------------------------------------------------------

/// Spike raster that only renders spikes with t within [visibleRange] and
/// before [currentTimeMs]. Draws spike particle trails — each spike flashes
/// bright violet and decays to resting opacity over [_glowWindowMs].
class AnimatedRasterPainter extends CustomPainter {
  final List<List<double>> spikes;
  final double duration;
  final double currentTimeMs;
  final ({double start, double end}) visibleRange;
  final bool reduceMotion;
  final TextStyle axisLabelStyle;

  /// Studio-violet glow accent resolved from the active theme by the caller
  /// (paint() has no BuildContext) — sourced from NmtkShellTokens'
  /// studioPalette.accent, the same brand token the canvas chrome uses.
  final Color glowColor;

  static const _glowWindowMs = 80.0;

  const AnimatedRasterPainter({
    required this.spikes,
    required this.duration,
    required this.currentTimeMs,
    required this.visibleRange,
    required this.axisLabelStyle,
    required this.glowColor,
    this.reduceMotion = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (duration <= 0) return;
    final rangeMs = visibleRange.end - visibleRange.start;
    if (rangeMs <= 0) return;

    const leftMargin = 40.0;
    const bottomMargin = 24.0;
    const topMargin = 8.0;
    const rightMargin = 8.0;

    final plotW = size.width - leftMargin - rightMargin;
    final plotH = size.height - topMargin - bottomMargin;

    final nNeurons = spikes.length;
    if (nNeurons == 0 || plotW <= 0 || plotH <= 0) return;

    final rowHeight = plotH / nNeurons;

    final gridPaint = Paint()
      ..color = AppTheme.border.withValues(alpha: 0.3)
      ..strokeWidth = 0.5;

    // Horizontal grid lines + neuron labels
    final labelEvery = nNeurons > 20 ? ((nNeurons / 20).ceil()) : 1;
    for (int i = 0; i <= nNeurons; i++) {
      final y = topMargin + i * rowHeight;
      canvas.drawLine(
        Offset(leftMargin, y),
        Offset(size.width - rightMargin, y),
        gridPaint,
      );

      if (i < nNeurons && i % labelEvery == 0) {
        final labelY = topMargin + (i + 0.5) * rowHeight;
        final tp = TextPainter(
          text: TextSpan(
            text: '$i',
            style: axisLabelStyle.copyWith(fontSize: 9),
          ),
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: leftMargin - 4);
        tp.paint(
          canvas,
          Offset(leftMargin - tp.width - 4, labelY - tp.height / 2),
        );
      }
    }

    // Vertical time grid (5 ticks) — labels show visible range timestamps
    for (int i = 0; i <= 5; i++) {
      final x = leftMargin + plotW * i / 5;
      canvas.drawLine(
        Offset(x, topMargin),
        Offset(x, size.height - bottomMargin),
        gridPaint,
      );

      final tLabel = visibleRange.start + rangeMs * i / 5;
      final tp = TextPainter(
        text: TextSpan(
          text: tLabel.toStringAsFixed(rangeMs < 10 ? 2 : 1),
          style: axisLabelStyle.copyWith(fontSize: 9),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(
        canvas,
        Offset(x - tp.width / 2, size.height - bottomMargin + 4),
      );
    }

    // Axis label
    final xLabel = TextPainter(
      text: TextSpan(
        text: 'Time (ms)',
        style: axisLabelStyle.copyWith(fontSize: 10),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    xLabel.paint(
      canvas,
      Offset(leftMargin + plotW / 2 - xLabel.width / 2, size.height - 4),
    );

    // ── Spikes with particle trail glow ────────────────────────────────────
    final corePaint = Paint()..strokeCap = StrokeCap.round;
    final glowPaint = Paint()
      ..strokeCap = StrokeCap.round
      ..blendMode = BlendMode.screen;

    for (int i = 0; i < nNeurons; i++) {
      final y = topMargin + (i + 0.5) * rowHeight;
      for (final t in spikes[i]) {
        if (t > currentTimeMs) continue;
        if (t < visibleRange.start || t > visibleRange.end) continue;

        final x = leftMargin + (t - visibleRange.start) / rangeMs * plotW;
        if (x < leftMargin || x > size.width - rightMargin) continue;

        final age = currentTimeMs - t;

        if (reduceMotion) {
          // Reduced-motion: static dim circle, no glow.
          corePaint.color = AppTheme.synSubject.withValues(alpha: 0.6);
          canvas.drawCircle(Offset(x, y), 1.2, corePaint);
        } else if (age < _glowWindowMs) {
          final fade = 1.0 - (age / _glowWindowMs);
          // Outer glow — decays in radius and opacity.
          glowPaint.color = glowColor.withValues(
            alpha: (fade * 0.55).clamp(0.0, 1.0),
          );
          canvas.drawCircle(Offset(x, y), 1.2 + 2.8 * fade, glowPaint);
          // Core — full brightness.
          corePaint.color = AppTheme.primary;
          canvas.drawCircle(Offset(x, y), 1.2, corePaint);
        } else {
          // Faded history dot.
          corePaint.color = AppTheme.primary.withValues(alpha: 0.32);
          canvas.drawCircle(Offset(x, y), 1.2, corePaint);
        }
      }
    }

    // ── Time cursor with DAW-style trailing gradient ───────────────────────
    if (currentTimeMs >= visibleRange.start &&
        currentTimeMs <= visibleRange.end) {
      final cursorX =
          (leftMargin + (currentTimeMs - visibleRange.start) / rangeMs * plotW)
              .clamp(leftMargin, size.width - rightMargin);

      if (!reduceMotion) {
        // Trailing shadow (40 px to the left of cursor).
        const shadowW = 40.0;
        final shadowLeft = math.max(leftMargin, cursorX - shadowW);
        final shadowRect = Rect.fromLTRB(
          shadowLeft,
          topMargin,
          cursorX,
          size.height - bottomMargin,
        );
        final shadowPaint = Paint()
          ..shader = LinearGradient(
            colors: [
              glowColor.withValues(alpha: 0.0),
              glowColor.withValues(alpha: 0.12),
            ],
          ).createShader(shadowRect);
        canvas.drawRect(shadowRect, shadowPaint);
      }

      final cursorPaint = Paint()
        ..color = AppTheme.primary.withValues(alpha: 0.9)
        ..strokeWidth = 1.5
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.0);

      canvas.drawLine(
        Offset(cursorX, topMargin),
        Offset(cursorX, size.height - bottomMargin),
        cursorPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant AnimatedRasterPainter oldDelegate) {
    return oldDelegate.currentTimeMs != currentTimeMs ||
        oldDelegate.spikes != spikes ||
        oldDelegate.duration != duration ||
        oldDelegate.visibleRange != visibleRange ||
        oldDelegate.reduceMotion != reduceMotion;
  }
}

// ---------------------------------------------------------------------------
// AnimatedChartPainter
// ---------------------------------------------------------------------------

/// Voltage trace chart that draws traces only up to [currentTimeMs], with
/// zoom-aware x-mapping and adaptive sample density based on [visibleRange].
class AnimatedChartPainter extends CustomPainter {
  final TextStyle axisLabelStyle;
  final List<List<double>> traces;
  final List<double> time;
  final List<Color> colors;
  final double currentTimeMs;
  final double duration;
  final ({double start, double end}) visibleRange;
  final bool reduceMotion;

  const AnimatedChartPainter({
    required this.traces,
    required this.time,
    required this.colors,
    required this.currentTimeMs,
    required this.duration,
    required this.visibleRange,
    this.reduceMotion = false,
    required this.axisLabelStyle,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (time.isEmpty || traces.isEmpty || duration <= 0) return;
    final rangeMs = visibleRange.end - visibleRange.start;
    if (rangeMs <= 0) return;

    const leftMargin = 40.0;
    const bottomMargin = 24.0;
    const topMargin = 8.0;
    const rightMargin = 8.0;

    final plotW = size.width - leftMargin - rightMargin;
    final plotH = size.height - topMargin - bottomMargin;
    if (plotW <= 0 || plotH <= 0) return;

    // Map visible time range to sample indices.
    final totalMs = time.last - time.first;
    final startIdx = totalMs > 0
        ? ((visibleRange.start / totalMs) * (time.length - 1)).round().clamp(
            0,
            time.length - 1,
          )
        : 0;
    final endIdx = totalMs > 0
        ? ((visibleRange.end / totalMs) * (time.length - 1)).round().clamp(
            0,
            time.length - 1,
          )
        : time.length - 1;
    final cutoffIdx = totalMs > 0
        ? ((currentTimeMs / totalMs) * (time.length - 1)).round().clamp(
            0,
            time.length - 1,
          )
        : time.length - 1;

    // Adaptive step: more samples per pixel when zoomed in.
    final visibleSamples = endIdx - startIdx + 1;
    final step = math.max(1, visibleSamples ~/ 500);

    // Y-range computed over the visible+revealed slice.
    double minY = double.infinity;
    double maxY = double.negativeInfinity;
    for (final trace in traces) {
      for (
        int i = startIdx;
        i <= math.min(cutoffIdx, endIdx) && i < trace.length;
        i++
      ) {
        if (trace[i] < minY) minY = trace[i];
        if (trace[i] > maxY) maxY = trace[i];
      }
    }
    if (!minY.isFinite || !maxY.isFinite) {
      minY = 0;
      maxY = 1;
    }
    if (minY == maxY) {
      minY -= 1.0;
      maxY += 1.0;
    }
    final double paddingY = (maxY - minY) * 0.1;
    minY -= paddingY;
    maxY += paddingY;
    final double rangeY = maxY - minY;

    // Grid
    final gridPaint = Paint()
      ..color = AppTheme.border.withValues(alpha: 0.3)
      ..strokeWidth = 0.5;

    // Y-axis labels
    const yTicks = 5;
    for (int i = 0; i <= yTicks; i++) {
      final frac = i / yTicks;
      final yVal = maxY - frac * rangeY;
      final y = topMargin + frac * plotH;

      canvas.drawLine(
        Offset(leftMargin, y),
        Offset(size.width - rightMargin, y),
        gridPaint,
      );

      final yLabel = TextPainter(
        text: TextSpan(
          text: yVal.toStringAsFixed(1),
          style: axisLabelStyle.copyWith(fontSize: 9),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: leftMargin - 4);
      yLabel.paint(
        canvas,
        Offset(leftMargin - yLabel.width - 4, y - yLabel.height / 2),
      );
    }

    // X-axis time labels — show visible range timestamps
    for (int i = 0; i <= 5; i++) {
      final x = leftMargin + plotW * i / 5;
      canvas.drawLine(
        Offset(x, topMargin),
        Offset(x, size.height - bottomMargin),
        gridPaint,
      );

      final tLabel = visibleRange.start + rangeMs * i / 5;
      final tp = TextPainter(
        text: TextSpan(
          text: tLabel.toStringAsFixed(rangeMs < 10 ? 2 : 1),
          style: axisLabelStyle.copyWith(fontSize: 9),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(
        canvas,
        Offset(x - tp.width / 2, size.height - bottomMargin + 4),
      );
    }

    // Per-trace coloured lines up to cutoff, within visible range.
    for (int ti = 0; ti < traces.length; ti++) {
      final trace = traces[ti];
      final color = colors[ti % colors.length];
      final linePaint = Paint()
        ..color = color
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke;

      final path = Path();
      var first = true;
      final renderEnd = math.min(cutoffIdx, endIdx);
      for (int i = startIdx; i <= renderEnd && i < trace.length; i += step) {
        final tMs = time[i];
        final double x =
            leftMargin + (tMs - visibleRange.start) / rangeMs * plotW;
        final double y =
            topMargin + plotH - ((trace[i] - minY) / rangeY) * plotH;
        if (first) {
          path.moveTo(x, y);
          first = false;
        } else {
          path.lineTo(x, y);
        }
      }
      canvas.drawPath(path, linePaint);
    }

    // Time cursor (only if within visible range)
    if (currentTimeMs >= visibleRange.start &&
        currentTimeMs <= visibleRange.end) {
      final cursorX =
          (leftMargin + (currentTimeMs - visibleRange.start) / rangeMs * plotW)
              .clamp(leftMargin, leftMargin + plotW);

      final cursorPaint = Paint()
        ..color = AppTheme.primary.withValues(alpha: 0.9)
        ..strokeWidth = 1.5
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.0);

      canvas.drawLine(
        Offset(cursorX, topMargin),
        Offset(cursorX, size.height - bottomMargin),
        cursorPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant AnimatedChartPainter oldDelegate) {
    return oldDelegate.currentTimeMs != currentTimeMs ||
        oldDelegate.traces != traces ||
        oldDelegate.time != time ||
        oldDelegate.colors != colors ||
        oldDelegate.visibleRange != visibleRange ||
        oldDelegate.reduceMotion != reduceMotion;
  }
}
