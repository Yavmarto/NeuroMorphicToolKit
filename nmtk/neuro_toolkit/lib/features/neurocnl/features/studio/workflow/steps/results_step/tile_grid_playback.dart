import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

import 'package:neuro_toolkit/features/neurocnl/widgets/canvas/spike_playback_transport.dart';

class TileGridPlayback extends StatefulWidget {
  const TileGridPlayback({
    super.key,
    required this.rasterId,
    required this.raster,
    required this.duration,
    this.playbackSession,
    this.playbackController,
    this.showTransport = true,
    required this.onPlaybackComplete,
  });

  /// Identity of the data behind [raster], as `"layer@epoch"`.
  ///
  /// This — not [raster] — is the reload condition. `Map` compares by identity
  /// and the parent used to build a fresh one inside `build()`, so every
  /// unrelated rebuild of the Results step (a canvas pan, an SSE history tick)
  /// looked like new data, reloaded, and rewound playback to zero mid-play.
  final String rasterId;

  /// neuron id → spike times in ms, ascending (the order `extractSpikeRaster`
  /// emits, since it walks the timestep axis forward).
  final Map<String, List<double>> raster;

  /// Total simulation time in ms — the exported timestep count, at dt = 1 ms.
  final double duration;
  final SpikePlaybackSession? playbackSession;

  /// Shared clock lifted into [_StudioResultVisualizerState]. When provided the
  /// transport is rendered by that parent (next to the epoch indicator), so this
  /// view uses the shared clock and hides its own transport.
  final AnimationController? playbackController;
  final bool showTransport;
  final VoidCallback onPlaybackComplete;

  @override
  State<TileGridPlayback> createState() => _TileGridPlaybackState();
}

class _TileGridPlaybackState extends State<TileGridPlayback>
    with SingleTickerProviderStateMixin {
  // Zoom disabled: an InteractiveViewer reads a trackpad two-finger scroll as a
  // zoom, so the grid scaled whenever the pointer merely crossed it. Hover
  // inspection still works.
  final _renderer = TileGridNeuronRenderer(enableZoom: false);

  // ── Grid geometry and per-tile spike times, computed once per raster ──────
  int _rows = 0;
  int _cols = 0;
  int _neuronCount = 0;

  /// `rows * cols`, which is >= [_neuronCount]: a near-square grid is padded
  /// (1000 neurons -> 32x32 -> 24 spare tiles) and the renderer walks the
  /// geometry. Buffers are sized to this, never to the neuron count — reading
  /// past them is what threw `RangeError` on every paint.
  int _tileCount = 0;

  /// Per tile, its spike times ascending. Padding tiles get an empty list, which
  /// renders as permanently dark — the honest depiction of "no neuron".
  List<List<double>> _tileSpikes = const [];

  /// Per tile, the index of the first spike *after* the clock's last sampled
  /// position. Advanced monotonically while playing forward, so sampling costs
  /// O(tiles) per tick rather than a binary search per tile.
  Int32List _cursors = Int32List(0);

  /// Per tile, the time of the most recent spike at or before the clock, or NaN
  /// when the tile hasn't spiked yet at this point on the timeline.
  Float64List _lastSpikeMs = Float64List(0);

  /// Clock position of the last sample pushed, used to detect a backward seek
  /// (which invalidates the forward cursors). Negative means "nothing sampled".
  double _sampledMs = -1.0;

  double _speed = 1.0;
  bool _reduceMotion = false;

  // An AnimationController rather than a Timer, so this view keeps time exactly
  // the way the raster does — same wall-clock mapping, same speed multipliers,
  // same readout. The tile renderer is push-based, so a listener samples the
  // clock's position and pushes a frame.
  late AnimationController _controller;

  /// True when the parent owns the clock (a [playbackController] was supplied),
  /// so this view must not create, dispose, sync or reset it, or draw its own
  /// transport — the parent shows one next to the epoch indicator.
  bool get _usesSharedClock => widget.playbackController != null;

  double get _currentTimeMs => _controller.value * widget.duration;

  /// False for a capture too short to animate — a still image, no transport.
  bool get _hasTimeline => _tileCount > 0 && widget.duration > 1;

  @override
  void initState() {
    super.initState();
    _speed = widget.playbackSession?.speed ?? _speed;
    _controller =
        widget.playbackController ??
        AnimationController(
          vsync: this,
          duration: spikePlaybackWallDuration(widget.duration, _speed),
        );
    _controller.addListener(_sampleClock);
    if (!_usesSharedClock) {
      _controller.addStatusListener((status) {
        if (status == AnimationStatus.completed &&
            widget.playbackSession?.isPlaying == true) {
          widget.onPlaybackComplete();
        }
        if (mounted) setState(() {});
      });
      widget.playbackSession?.addListener(_syncPlaybackSession);
    }
    _loadRaster();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (!_usesSharedClock) _syncPlaybackSession();
  }

  @override
  void didUpdateWidget(covariant TileGridPlayback oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Deliberately keyed on `rasterId`, not on `raster`: see the field's doc.
    if (widget.rasterId != oldWidget.rasterId ||
        widget.duration != oldWidget.duration) {
      _loadRaster();
    }
    if (widget.playbackController != oldWidget.playbackController) {
      _controller.removeListener(_sampleClock);
      _controller =
          widget.playbackController ??
          AnimationController(
            vsync: this,
            duration: spikePlaybackWallDuration(widget.duration, _speed),
          );
      if (!_usesSharedClock) {
        _controller.addStatusListener((status) {
          if (status == AnimationStatus.completed &&
              widget.playbackSession?.isPlaying == true) {
            widget.onPlaybackComplete();
          }
          if (mounted) setState(() {});
        });
      }
      _controller.addListener(_sampleClock);
    }
    if (_usesSharedClock) return;
    if (widget.playbackSession != oldWidget.playbackSession) {
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
    widget.playbackSession?.removeListener(_syncPlaybackSession);
    // Must remove even when the clock is shared (parent-owned, not disposed
    // here): otherwise the parent's controller keeps ticking this listener
    // after _renderer is disposed below, and the next tick writes to a
    // disposed ValueNotifier.
    _controller.removeListener(_sampleClock);
    if (!_usesSharedClock) _controller.dispose();
    _renderer.dispose();
    super.dispose();
  }

  /// Bins neurons onto tiles and resets the clock. Runs once per raster, so it
  /// must not be reachable from `build()`.
  void _loadRaster() {
    final raster = widget.raster;
    final neuronIds = raster.keys.toList()
      ..sort((a, b) {
        final ai = int.tryParse(a);
        final bi = int.tryParse(b);
        if (ai != null && bi != null) return ai.compareTo(bi);
        return a.compareTo(b);
      });

    _neuronCount = neuronIds.length;
    if (_neuronCount == 0 || widget.duration <= 0) {
      _rows = _cols = _tileCount = 0;
      _tileSpikes = const [];
      _cursors = Int32List(0);
      _lastSpikeMs = Float64List(0);
      // Nothing left to sample — don't leave the previous raster's clock running.
      if (!_usesSharedClock) _controller.stop();
      return;
    }

    _cols = math.sqrt(_neuronCount).ceil().clamp(1, _neuronCount);
    _rows = (_neuronCount / _cols).ceil();
    _tileCount = _rows * _cols;
    _tileSpikes = List<List<double>>.generate(
      _tileCount,
      (i) => i < _neuronCount
          ? (raster[neuronIds[i]] ?? const <double>[])
          : const <double>[],
      growable: false,
    );
    _cursors = Int32List(_tileCount);
    _lastSpikeMs = Float64List(_tileCount);

    // Deliberately does NOT start playing. Autoplaying here meant playback
    // restarted every time the epoch or layer changed, which read as the view
    // starting at random; the raster has always opened paused. With a shared
    // clock the parent owns this reset (and any resume), so skip it here.
    if (!_usesSharedClock) {
      _controller
        ..stop()
        ..duration = spikePlaybackWallDuration(widget.duration, _speed)
        ..value = 0.0;
    }
    _rewindCursors();
    _pushSampleAt(0.0);
  }

  void _rewindCursors() {
    _cursors.fillRange(0, _cursors.length, 0);
    _lastSpikeMs.fillRange(0, _lastSpikeMs.length, double.nan);
    _sampledMs = -1.0;
  }

  /// Pushes the frame for the clock's current position, every tick.
  void _sampleClock() {
    if (_tileCount == 0) return;
    _pushSampleAt(_currentTimeMs);
    // Deliberately no setState: the transport is wrapped in an AnimatedBuilder
    // on this same controller, so the readout and slider track the clock
    // without rebuilding this subtree — which would re-run the LayoutBuilder
    // and re-attach the renderer on every frame.
  }

  /// Samples every tile's trail brightness at simulation time [t].
  ///
  /// Sampled from the clock rather than binned into one frame per timestep. The
  /// binned version produced `ceil(duration)` frames — 25 for a typical capture
  /// — spread across a 4-second wall-clock floor, i.e. 6.25 updates per second,
  /// which is what read as flickering boxes next to a raster repainting at 60 Hz.
  void _pushSampleAt(double t) {
    if (t < _sampledMs) _rewindCursors();
    _sampledMs = t;

    final activity = Float32List(_tileCount);
    final concentration = Float32List(_tileCount);
    for (var i = 0; i < _tileCount; i++) {
      final spikes = _tileSpikes[i];
      var cursor = _cursors[i];
      while (cursor < spikes.length && spikes[cursor] <= t) {
        _lastSpikeMs[i] = spikes[cursor];
        cursor++;
      }
      _cursors[i] = cursor;

      final last = _lastSpikeMs[i];
      if (last.isNaN) continue; // hasn't spiked yet — stays dark
      final since = t - last;
      activity[i] = spikeTrailIntensity(since);
      // Recency of the spike driving this tile. The binned version measured
      // "how late within the window the last spike landed", which stopped
      // meaning anything once windows did.
      concentration[i] = (1.0 - since / kSpikeTrailTauMs).clamp(0.0, 1.0);
    }

    // A fresh frame object per sample, not mutated buffers: both gates in the
    // renderer are identity-based (the ValueNotifier's `==` short-circuit and
    // `shouldRepaint`'s `!identical`), so reusing one frame would repaint
    // nothing at all.
    _renderer.pushFrame(
      TileActivityFrame(
        totalNeuronCount: _neuronCount,
        tileActivity: activity,
        tileConcentration: concentration,
        tileRows: _rows,
        tileCols: _cols,
        simulationTimeMs: t,
      ),
    );
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
    } else {
      _controller
        ..duration = spikePlaybackWallDuration(widget.duration, _speed)
        // Replaying from the end restarts rather than sitting finished.
        ..forward(from: _controller.value >= 1.0 ? 0.0 : null);
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
      ..duration = spikePlaybackWallDuration(widget.duration, speed)
      ..value = progress;
    if (wasPlaying && !_reduceMotion) _controller.forward();
  }

  void _onSeek(double ms) {
    widget.playbackSession?.setPlaying(false);
    _controller.stop();
    _controller.value = widget.duration <= 0
        ? 0.0
        : (ms / widget.duration).clamp(0.0, 1.0);
    setState(() {});
  }

  void _syncPlaybackSession() {
    final session = widget.playbackSession;
    if (session == null) return;
    final wasPlaying = _controller.isAnimating;
    final progress = _controller.value;
    _speed = session.speed;
    _controller
      ..stop()
      ..duration = spikePlaybackWallDuration(widget.duration, _speed)
      ..value = progress;
    if (session.isPlaying && !_reduceMotion && _hasTimeline) {
      _controller.forward(from: progress >= 1.0 ? 0.0 : null);
    }
    if (wasPlaying || mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (_tileCount == 0) {
      return const Center(
        child: Text('Playback unavailable for this training run.'),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_hasTimeline && widget.showTransport)
          AnimatedBuilder(
            animation: _controller,
            builder: (context, _) => SpikePlaybackTransport(
              isPlaying: _controller.isAnimating,
              speed: _speed,
              currentTimeMs: _currentTimeMs,
              duration: widget.duration,
              onTogglePlay: _togglePlay,
              onSpeedChanged: _onSpeedChanged,
              onSeek: _onSeek,
            ),
          ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              _renderer.attach(constraints.biggest);
              return _renderer.buildSurface(context);
            },
          ),
        ),
      ],
    );
  }
}
