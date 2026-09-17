import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart' hide AppTheme;

import 'package:neuro_toolkit/features/neurocnl/theme/app_theme.dart';

/// Shared playback transport for spike-activity views.
///
/// Both spike views in the Results step — the chip-die tile grid and the spike
/// raster — replay the same per-neuron data over the same time axis, so they get
/// the same controls from here. They previously each carried a private
/// transport, which drifted into six different behaviours (one autoplayed and
/// looped, the other opened paused and stopped at the end; one paused on scrub,
/// the other resumed; only one had speed control; only one honoured reduce-motion
/// and only one guarded the single-frame case). Keeping the widget *and* the
/// wall-clock mapping in one place is what stops that recurring.

/// Wall-clock time in which to replay [durationMs] of simulation at [speed].
///
/// One millisecond of simulation maps to [_wallMsPerSimMs] of wall clock, with a
/// floor so a very short capture isn't a single flash.
///
/// The floor is applied to the *base* duration and speed divides the result.
/// Doing it the other way round — `max(floor, duration * k / speed)`, the
/// original — meant that for any run short enough to hit the floor, every speed
/// produced an identical playback: the ½×/1×/2×/5× buttons highlighted but
/// changed nothing. A 25-timestep capture (the common case) was entirely inside
/// that dead zone.
Duration spikePlaybackWallDuration(double durationMs, double speed) {
  const wallMsPerSimMs = 0.03; // 30 ms wall per 1 ms sim
  const minWallSeconds = 4.0;
  final base = math.max(minWallSeconds, durationMs * wallMsPerSimMs);
  final scaled = speed <= 0 ? base : base / speed;
  return Duration(milliseconds: (scaled * 1000).round());
}

/// The speed multipliers offered by [SpikePlaybackTransport].
const List<double> kSpikePlaybackSpeeds = [0.5, 1.0, 2.0, 5.0];

/// Shared state for a sequence of spike-playback clips.
///
/// Results owns a session while it walks its training epochs. Both Grid and
/// Raster subscribe to it, so speed and play/pause state survive an epoch
/// change without tying these visualizations to Riverpod.
class SpikePlaybackSession extends ChangeNotifier {
  bool _isPlaying = false;
  double _speed = 1.0;

  bool get isPlaying => _isPlaying;
  double get speed => _speed;

  void setPlaying(bool value) {
    if (_isPlaying == value) return;
    _isPlaying = value;
    notifyListeners();
  }

  void toggle() => setPlaying(!_isPlaying);

  void setSpeed(double value) {
    if (_speed == value) return;
    _speed = value;
    notifyListeners();
  }
}

/// Time constant of a spike's visible trail, in simulation milliseconds.
///
/// Chosen to reproduce the look of the frame-binned version it replaced, which
/// retained 0.78 of a tile's brightness per 1 ms frame: `exp(-1 / 4.02) ≈ 0.78`.
const double kSpikeTrailTauMs = 4.0;

/// Brightness of a spike's trail [sinceMs] simulation-milliseconds after the
/// spike, on the 0-1 scale the tile renderer expects.
///
/// Sampled continuously from the playback clock rather than binned into one
/// frame per timestep. Binning meant a 25-timestep capture produced 25 frames
/// spread over a 4-second floor — 6.25 updates per second, which is what read as
/// "flickering boxes" while the raster beside it repainted at 60 Hz.
///
/// A negative [sinceMs] (no spike yet at this point on the clock) is dark, and
/// so is a non-finite one (no spike at all).
double spikeTrailIntensity(double sinceMs, {double tauMs = kSpikeTrailTauMs}) {
  if (!sinceMs.isFinite || sinceMs < 0) return 0.0;
  if (tauMs <= 0) return sinceMs == 0 ? 1.0 : 0.0;
  return math.exp(-sinceMs / tauMs);
}

/// Play/pause + speed selector + elapsed-time readout, above a seek slider.
///
/// Stateless and driven entirely by scalars, so it works for a continuous clock
/// (the raster) and a frame-indexed one (the tile grid) without either having to
/// know how the other keeps time.
class SpikePlaybackTransport extends StatelessWidget {
  const SpikePlaybackTransport({
    super.key,
    required this.isPlaying,
    required this.speed,
    required this.currentTimeMs,
    required this.duration,
    required this.onTogglePlay,
    required this.onSpeedChanged,
    required this.onSeek,
  });

  final bool isPlaying;
  final double speed;
  final double currentTimeMs;

  /// Total simulation duration in ms.
  final double duration;

  final VoidCallback onTogglePlay;
  final ValueChanged<double> onSpeedChanged;

  /// Called with a time in ms when the user drags the slider.
  final ValueChanged<double> onSeek;

  /// Wall-clock length of a full playback at the current speed.
  double get _wallTotalSeconds =>
      spikePlaybackWallDuration(duration, speed).inMilliseconds / 1000.0;

  /// Wall-clock time elapsed so far, derived from the position on the sim axis
  /// (the clock is linear in both, so the ratio carries over).
  double get _wallElapsedSeconds => duration <= 0
      ? 0.0
      : _wallTotalSeconds * (currentTimeMs / duration).clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = Zeta.of(context).colors;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Tooltip(
              message: isPlaying ? 'Pause' : 'Play',
              child: ZetaIconButton.text(
                icon: isPlaying ? ZetaIcons.pause : ZetaIcons.play,
                size: ZetaWidgetSize.small,
                semanticLabel: isPlaying ? 'Pause' : 'Play',
                onPressed: onTogglePlay,
              ),
            ),
            const SizedBox(width: 6),
            for (final s in kSpikePlaybackSpeeds)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Tooltip(
                  message: 'Play at ${_speedLabel(s)} speed',
                  child: InkWell(
                    onTap: () => onSpeedChanged(s),
                    borderRadius: BorderRadius.circular(
                      NmtkShellTokens.of(context).radiusSm,
                    ),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 120),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: speed == s
                            ? AppTheme.textSecondaryOf(
                                context,
                              ).withValues(alpha: 0.15)
                            : // ZETA-MIGRATION-EXEMPT: transparent (no fill) — Zeta has no transparent token
                              Colors.transparent,
                        borderRadius: BorderRadius.circular(
                          NmtkShellTokens.of(context).radiusSm,
                        ),
                        border: Border.all(
                          color: speed == s
                              ? AppTheme.textSecondaryOf(context)
                              : AppTheme.borderOf(
                                  context,
                                ).withValues(alpha: 0.5),
                        ),
                      ),
                      child: Text(
                        _speedLabel(s),
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: 9,
                          color: AppTheme.textSecondaryOf(context),
                          fontWeight: speed == s
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            const Spacer(),
            Text(
              // Both clocks, because they differ by more than two orders of
              // magnitude and only one of them was ever shown: a 25 ms capture
              // takes 4 real seconds to play (see spikePlaybackWallDuration), so
              // "25 ms" on its own left the wait unexplained.
              '${currentTimeMs.toStringAsFixed(1)} / '
              '${duration.toStringAsFixed(0)} ms sim · '
              '${_wallElapsedSeconds.toStringAsFixed(1)} / '
              '${_wallTotalSeconds.toStringAsFixed(1)} s',
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: 9,
                color: AppTheme.textSecondaryOf(context),
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        // Colours stated explicitly: this app's Zeta-generated ColorScheme
        // leaves most slots unset, so an unthemed Slider paints its inactive
        // track in the surface colour and disappears on dark.
        SliderTheme(
          data: SliderThemeData(
            activeTrackColor: colors.mainPrimary,
            inactiveTrackColor: colors.surfaceHover,
            thumbColor: colors.mainPrimary,
            overlayColor: colors.mainPrimary.withValues(alpha: 0.1),
            trackHeight: 4,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
          ),
          child: Slider(
            value: currentTimeMs.clamp(0.0, math.max(duration, 0.0)),
            min: 0,
            max: math.max(duration, 0.0),
            onChanged: onSeek,
          ),
        ),
      ],
    );
  }

  static String _speedLabel(double s) => s == 0.5 ? '½×' : '${s.toInt()}×';
}
