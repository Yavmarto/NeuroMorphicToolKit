import 'package:flutter/material.dart' show Color;

import 'package:neuro_toolkit/features/neurocnl/models/studio_result_session.dart'
    show StudioResultView;
import 'package:neuro_toolkit/features/neurocnl/utils/npy_parser.dart'
    show NpyArray, NpyParser;

/// One activity export reduced to the shape the playback views consume.
typedef ResolvedActivityRaster = ({
  Map<String, List<double>> raster,
  NpyArray? rasterSource,
  double duration,
});

/// Resolves a 2D/3D activity-export array down to a spike raster + duration
/// for a single bucket, squeezing a 3D (batch, timesteps, neurons) export to
/// one batch sample. Returns `null` for `rasterSource` when [selectedArray]
/// is null (nothing selected yet) or has an unsupported shape (malformed
/// export) — callers distinguish the two via [selectedArray].
///
/// Allocates a fresh raster `Map` per call, so callers must not invoke it from
/// `build()`: `_StudioResultVisualizerState` memoises it on the source array's
/// identity and
/// passes the result down. Resolving per build handed the playback widget a new
/// Map every rebuild, and that widget compared the Map by identity to decide
/// whether to reload — so an unrelated rebuild rewound playback to zero.
ResolvedActivityRaster resolveActivityRaster(NpyArray? selectedArray) {
  if (selectedArray == null) {
    return (
      raster: const <String, List<double>>{},
      rasterSource: null,
      duration: 0.0,
    );
  }
  try {
    final rasterSource = selectedArray.shape.length == 2
        ? selectedArray
        : selectedArray.shape.length == 3
        ? NpyParser.selectBatchSample(selectedArray)
        : null;
    if (rasterSource == null) {
      return (
        raster: const <String, List<double>>{},
        rasterSource: null,
        duration: 0.0,
      );
    }
    return (
      raster: NpyParser.extractSpikeRaster(rasterSource),
      rasterSource: rasterSource,
      duration: rasterSource.shape[0].toDouble(),
    );
  } catch (_) {
    return (
      raster: const <String, List<double>>{},
      rasterSource: null,
      duration: 0.0,
    );
  }
}

/// Which view fills the shared result visualizer's main area.
///
/// These are three siblings, not a two-level hierarchy: [grid] and [raster]
/// are two renderings of the same per-neuron spike data and [architecture] is
/// the wiring diagram. An earlier version split them across an outer
/// Network/Architecture switch and an inner Grid/Raster switch, which read as
/// two unrelated rows of tabs because the nesting it implied wasn't real.
extension StudioResultViewUi on StudioResultView {
  /// Index into the main-area `IndexedStack`: both spike views are rendered by
  /// the same panel, which takes the mode as a parameter. Deliberately not
  /// `Enum.index` — that silently coupled stack order to declaration order.
  int get stackIndex => switch (this) {
    StudioResultView.architecture => 0,
    StudioResultView.weights => 2,
    StudioResultView.brainviz => 3,
    _ => 1,
  };

  /// True for spike-playback views that share the grid export and epoch clock.
  bool get usesActivityPlayback => switch (this) {
    StudioResultView.architecture || StudioResultView.weights => false,
    _ => true,
  };
}

// ── Platform tab chip ───────────────────────────────────────────────────

// ── Network playback panel ───────────────────────────────────────────────

/// Renders the run's real per-neuron spike data in whichever form the tab row
/// selected:
/// - Grid: the chip-die tile-grid renderer (`TileGridNeuronRenderer`, from
///   `nmtk_ui_core`) the old `/viz-demo` screen used, now fed real data
///   instead of that screen's canned Poisson noise.
/// - Raster: `AnimatedSnnPlayback`'s spike-raster + firing-rate chart.
///
/// Purely presentational: the export, the layer selection and the epoch
/// snapping all live in `_StudioResultVisualizerState` so Grid and Raster can
/// never show different layers or epochs.

/// Maps a real per-neuron spike raster onto a near-square grid of tiles (one
/// neuron per tile — the toolkit has no per-core neuron grouping outside a
/// specific deploy target, so a 1:1 mapping is the honest one) and replays it
/// through [TileGridNeuronRenderer], the same chip-die renderer the old
/// `/viz-demo` screen used for its canned data.

// ── Spike-rate legend overlay ────────────────────────────────────────────

/// Shared compact tab used by Results and Results comparison panels.

// ── Compare toggle chip ──────────────────────────────────────────────────

/// The Results step's one view switch: Architecture, Grid, Raster or Weights.
///
/// A single flat segmented control. These used to be split across an outer
/// Network/Architecture switch and an inner Grid/Raster row, which read as two
/// unrelated tab bars — Grid and Raster are just two renderings of the same
/// spike data, so they are siblings of Architecture, not children of it.
///
/// Kept as a named widget over three call sites, but it is now a thin wrapper:
/// the hand-rolled `GestureDetector` pill row it used to be was unreachable by
/// keyboard and silent to screen readers.

// ── Colour map (RdBu_r): blue → white → red, symmetric about 0 ─────────────

Color rdbuColor(double v, double vmax) {
  final t = (v / vmax).clamp(-1.0, 1.0);
  if (t >= 0) {
    // 0 → white,  +1 → red
    return Color.fromARGB(
      255,
      255,
      (255 * (1 - t)).round(),
      (255 * (1 - t)).round(),
    );
  } else {
    // 0 → white, -1 → blue
    final abs = -t;
    return Color.fromARGB(
      255,
      (255 * (1 - abs)).round(),
      (255 * (1 - abs)).round(),
      255,
    );
  }
}

// ── Single-neuron tile painter ────────────────────────────────────────────────

// ── Detail bottom sheet for a single neuron ──────────────────────────────────

// ── Main interactive weights view ─────────────────────────────────────────────
