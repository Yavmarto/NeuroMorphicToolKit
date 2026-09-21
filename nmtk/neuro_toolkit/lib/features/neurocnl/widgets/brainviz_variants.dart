import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:neuro_toolkit/features/neurocnl/models/canvas/canvas.dart';
import 'package:neuro_toolkit/features/neurocnl/theme/app_theme.dart';
import 'package:neuro_toolkit/features/neurocnl/utils/canvas_projection_utils.dart'
    show spikeRateColor;
import 'package:neuro_toolkit/features/neurocnl/widgets/brainviz_force_3d_view.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart' hide AppTheme;

/// Distinct ways to read the same co-activation data in the brainviz.
///
/// Every variant answers the same question — "which neurons fire together?" —
/// but with a different visual, so they can be placed side by side and
/// compared.
enum BrainvizVariant {
  /// Dot size and colour show how hard each neuron fires right now.
  activity,

  /// Lines join neurons that fire together.
  wires,

  /// Neurons that fire together physically pull into a cluster.
  attraction,

  /// Every firing neuron emits a ring; co-active neurons ring in step.
  rings,

  /// A grid where each cell is how often two neurons fire together.
  matrix;

  String get label => switch (this) {
    BrainvizVariant.activity => 'Activity',
    BrainvizVariant.wires => 'Wires',
    BrainvizVariant.attraction => 'Pull together',
    BrainvizVariant.rings => 'Rings',
    BrainvizVariant.matrix => 'Co-firing grid',
  };

  /// One plain-English sentence shown under the panel title.
  String get caption => switch (this) {
    BrainvizVariant.activity =>
      'Dot size and colour show how hard each neuron fires now.',
    BrainvizVariant.wires =>
      'Lines join neurons that fire together; brighter is stronger.',
    BrainvizVariant.attraction =>
      'Neurons that fire together drift into one cluster. No lines.',
    BrainvizVariant.rings =>
      'Firing neurons send out rings. Co-active neurons ring in step.',
    BrainvizVariant.matrix =>
      'Each cell is how often two neurons fire together. Brighter is stronger.',
  };

  bool get isMatrix => this == BrainvizVariant.matrix;
}

/// Default comparison set: one panel per reading of the data.
const List<BrainvizVariant> kDefaultBrainvizVariants = BrainvizVariant.values;

/// Lays the requested brainviz variants out in a responsive, scrollable grid
/// so they can be compared at a glance.
class BrainvizVariantsView extends StatelessWidget {
  const BrainvizVariantsView({
    super.key,
    required this.graph,
    required this.activity,
    required this.matrix,
    this.clusterIndices,
    this.variants = kDefaultBrainvizVariants,
  });

  final CanvasGraph graph;
  final Map<String, double> activity;
  final Map<String, Map<String, double>> matrix;
  final Map<String, int>? clusterIndices;
  final List<BrainvizVariant> variants;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1100
            ? 3
            : constraints.maxWidth >= 700
            ? 2
            : 1;
        return GridView.builder(
          padding: const EdgeInsets.all(12),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            mainAxisExtent: 300,
          ),
          itemCount: variants.length,
          itemBuilder: (context, index) => _VariantCard(
            variant: variants[index],
            child: buildBrainvizVariant(
              variant: variants[index],
              graph: graph,
              activity: activity,
              matrix: matrix,
              clusterIndices: clusterIndices,
            ),
          ),
        );
      },
    );
  }
}

/// Renders one brainviz variant for the given data. Shared by the comparison
/// grid and the single-variant view.
Widget buildBrainvizVariant({
  Key? key,
  required BrainvizVariant variant,
  required CanvasGraph graph,
  required Map<String, double> activity,
  required Map<String, Map<String, double>> matrix,
  Map<String, int>? clusterIndices,
}) {
  switch (variant) {
    case BrainvizVariant.matrix:
      return BrainvizMatrixView(key: key, matrix: matrix, activity: activity);
    case BrainvizVariant.activity:
      return BrainvizForce3DView(
        key: key,
        graph: graph,
        activity: activity,
        correlationMatrix: matrix,
        nodeClusterIndices: clusterIndices,
        drawWires: false,
        useCorrelationDegree: false,
        maxLabels: 4,
      );
    case BrainvizVariant.wires:
      return BrainvizForce3DView(
        key: key,
        graph: graph,
        activity: activity,
        correlationMatrix: matrix,
        nodeClusterIndices: clusterIndices,
        maxLabels: 4,
      );
    case BrainvizVariant.attraction:
      return BrainvizForce3DView(
        key: key,
        graph: graph,
        activity: activity,
        correlationMatrix: matrix,
        nodeClusterIndices: clusterIndices,
        drawWires: false,
        correlationAttraction: 1.0,
        maxLabels: 4,
      );
    case BrainvizVariant.rings:
      return BrainvizForce3DView(
        key: key,
        graph: graph,
        activity: activity,
        correlationMatrix: matrix,
        drawWires: false,
        ringActivity: true,
        useCorrelationDegree: false,
        showLabels: false,
      );
  }
}

class _VariantCard extends StatelessWidget {
  const _VariantCard({required this.variant, required this.child});

  final BrainvizVariant variant;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tokens = NmtkShellTokens.of(context);
    final textTheme = Theme.of(context).textTheme;
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(tokens.radiusMd),
        border: Border.all(color: AppTheme.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  variant.label,
                  style: textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  variant.caption,
                  style: textTheme.labelSmall?.copyWith(
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}

/// Co-firing matrix: rows and columns are neurons, each cell is how strongly
/// the pair co-activates. The clearest single summary of "who fires with
/// whom"; the diagonal shows each neuron's own activity.
class BrainvizMatrixView extends StatelessWidget {
  const BrainvizMatrixView({
    super.key,
    required this.matrix,
    required this.activity,
    this.maxNodes = 18,
  });

  final Map<String, Map<String, double>> matrix;
  final Map<String, double> activity;
  final int maxNodes;

  List<String> _rankedIds() {
    final ids = <String>{...matrix.keys, ...activity.keys};
    if (ids.isEmpty) return const <String>[];
    final scores = <String, double>{};
    for (final id in ids) {
      var sum = 0.0;
      for (final value in matrix[id]?.values ?? const <double>[]) {
        sum += value;
      }
      scores[id] = sum + (activity[id] ?? 0.0);
    }
    final ranked = ids.toList()
      ..sort((a, b) => (scores[b] ?? 0).compareTo(scores[a] ?? 0));
    return ranked.take(maxNodes).toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final ids = _rankedIds();
    if (ids.length < 2) {
      return const Center(
        child: Text(
          'Not enough co-firing yet.',
          style: TextStyle(fontSize: 12),
        ),
      );
    }
    final zeta = Zeta.of(context);
    return CustomPaint(
      painter: _BrainvizMatrixPainter(
        ids: ids,
        matrix: matrix,
        activity: activity,
        colorOf: (value) => spikeRateColor(value, zeta.colors),
        labelStyle: zeta.textStyles.labelSmall.copyWith(
          fontSize: 9,
          color: AppTheme.textSecondary,
        ),
      ),
    );
  }
}

class _BrainvizMatrixPainter extends CustomPainter {
  _BrainvizMatrixPainter({
    required this.ids,
    required this.matrix,
    required this.activity,
    required this.colorOf,
    required this.labelStyle,
  });

  final List<String> ids;
  final Map<String, Map<String, double>> matrix;
  final Map<String, double> activity;
  final Color Function(double value) colorOf;
  final TextStyle labelStyle;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFF0A0E18),
    );

    final labelGutter = math.min(72.0, size.width * 0.3);
    final topGutter = 16.0;
    final gridSize = math.min(
      size.width - labelGutter - 8,
      size.height - topGutter - 8,
    );
    if (gridSize <= 0) return;
    final cell = gridSize / ids.length;

    for (var row = 0; row < ids.length; row++) {
      for (var col = 0; col < ids.length; col++) {
        final a = ids[row];
        final b = ids[col];
        final value = row == col
            ? (activity[a] ?? 0.0)
            : (matrix[a]?[b] ?? matrix[b]?[a] ?? 0.0);
        final rect = Rect.fromLTWH(
          labelGutter + col * cell,
          topGutter + row * cell,
          cell - 1,
          cell - 1,
        );
        final color = value <= 0.02
            ? AppTheme.surfaceVariant
            : colorOf(
                value,
              ).withValues(alpha: (0.25 + 0.75 * value).clamp(0, 1));
        canvas.drawRect(rect, Paint()..color = color);
      }
    }

    for (var i = 0; i < ids.length; i++) {
      final label = _short(ids[i]);
      final painter = TextPainter(
        text: TextSpan(text: label, style: labelStyle),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: labelGutter - 6);
      painter.paint(
        canvas,
        Offset(
          labelGutter - painter.width - 4,
          topGutter + i * cell + (cell - painter.height) / 2,
        ),
      );
    }
  }

  String _short(String id) {
    if (id.length <= 8) return id;
    return id.substring(id.length - 8);
  }

  @override
  bool shouldRepaint(covariant _BrainvizMatrixPainter old) =>
      old.ids != ids ||
      old.matrix != matrix ||
      old.activity != activity ||
      old.colorOf != colorOf;
}
