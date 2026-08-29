import 'package:flutter/material.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';

import 'package:neuro_toolkit/features/neurocnl/models/canvas/pipeline_dag.dart';

// ── Shared category color table ─────────────────────────────────────────────
//
// One table for every node-accent color on every canvas — the Architecture
// canvas's NIR node categories and the Train/Eval canvases' pipeline DAG
// categories used to be two independent switch statements that happened to
// share a couple of hex values by coincidence and collided on others (e.g.
// 'transform' and 'timeControl' were both 0xFF8E24AA), so two conceptually
// different node kinds could render in the identical color. Concepts that
// are the same idea under a different name (io/data, neuron/network,
// utility/scheduler) intentionally share a color; everything else has its
// own distinct value.
const Map<String, Color> _canvasCategoryColors = {
  'io': Color(0xFF1E88E5),
  'data': Color(0xFF1E88E5),
  'neuron': Color(0xFF43A047),
  'network': Color(0xFF43A047),
  'transform': Color(0xFF8E24AA),
  'timeControl': Color(0xFFD81B60),
  'pooling': Color(0xFF00897B),
  'utility': Color(0xFF546E7A),
  'scheduler': Color(0xFF546E7A),
  'loss': Color(0xFFE53935),
  'backward': Color(0xFFFF6F00),
  'optimiser': Color(0xFFFFB300),
  'metrics': Color(0xFF3949AB),
  'export': Color(0xFF6D4C41),
  'lava': Color(0xFFD84315),
};

const Color _canvasCategoryFallbackColor = Color(0xFF546E7A);

/// Accent color for a node category, without needing a [BuildContext] — the
/// table is theme-independent, and the edge painters have no context.
Color canvasCategoryColor(String category) =>
    _canvasCategoryColors[category] ?? _canvasCategoryFallbackColor;

Color nirCategoryColor(BuildContext context, String category) =>
    canvasCategoryColor(category);

// ── Pipeline DAG categories ───────────────────────────────────────────────────
//
// Shared by every surface that draws a pipeline node: the node cards on the
// Train/Eval canvases, the bottom-bar "Add Node" palette, and the
// port-anchored connect palette. Previously duplicated between
// `canvas_screen.dart` and `pipeline_phase_canvas.dart`.

Color pipelineCategoryColor(PipelineDagCategory cat) =>
    _canvasCategoryColors[cat.name] ?? _canvasCategoryFallbackColor;

// ── Wire colors ─────────────────────────────────────────────────────────────

/// Color of a pipeline wire, from the data kind it carries.
///
/// Lives here beside the node accents so every color decision on a canvas is
/// in one file. The Architecture canvas has no equivalent notion — its
/// `PortType` describes tensor shape, not data kind — so its wires take the
/// source node's category accent via [nirCategoryColor] instead of a table
/// here.
Color canvasPortTypeColor(PortType type) => switch (type) {
  PortType.spikes => const Color(0xFFFFA000), // amber
  PortType.loss => const Color(0xFFE53935), // red
  PortType.gradients => const Color(0xFF1E88E5), // blue
  PortType.model => const Color(0xFF43A047), // green
  PortType.metrics => const Color(0xFF8E24AA), // purple
  PortType.membrane => const Color(0xFF00ACC1), // cyan
  _ => const Color(0xFF9E9E9E), // grey
};

IconData pipelineCategoryIcon(PipelineDagCategory cat) => switch (cat) {
  PipelineDagCategory.data =>
    Icons.dataset_outlined, // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
  PipelineDagCategory.timeControl => ZetaIcons.timer,
  PipelineDagCategory.network =>
    Icons.hub_outlined, // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
  PipelineDagCategory.loss =>
    Icons.functions, // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
  PipelineDagCategory.backward => ZetaIcons.undo,
  PipelineDagCategory.optimiser => ZetaIcons.tune,
  PipelineDagCategory.scheduler => ZetaIcons.schedule,
  PipelineDagCategory.metrics => ZetaIcons.chart_bar,
  PipelineDagCategory.export => ZetaIcons.download,
  PipelineDagCategory.lava => ZetaIcons.memory,
};
