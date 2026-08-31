import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

import 'package:neuro_toolkit/features/neurocnl/models/canvas/pipeline_dag.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/canvas/canvas_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/workspace_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/canvas/pipeline_cnl_panel.dart';

// ── Main widget ───────────────────────────────────────────────────────────────

class PipelineOverviewCanvas extends ConsumerWidget {
  const PipelineOverviewCanvas({super.key});

  // Mirrors CanvasScreen._switchTab: opening a pipeline tab must seed its
  // default node chain first, or the canvas opens empty (these cards call
  // setActiveTab directly, bypassing _switchTab entirely).
  void _openPipelineTab(WidgetRef ref, CanvasTab tab) {
    final ws = ref.read(workspaceProvider);
    ref
        .read(canvasProvider.notifier)
        .initDefaultPhases(
          frameworks: ws.selectedPlatforms,
          dataset: ws.selectedDataset,
        );
    ref.read(canvasProvider.notifier).setActiveTab(tab);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final phases = ref.watch(canvasProvider.select((s) => s.pipelinePhases));
    final graph = ref.watch(canvasProvider.select((s) => s.graph));
    final tokens = NmtkShellTokens.of(context);
    final textStyles = Zeta.of(context).textStyles;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Title
              Text('Pipeline Overview', style: textStyles.titleLarge),
              const SizedBox(height: 8),
              Text(
                'All phases of the ML pipeline. Click Open to edit a phase.',
                style: textStyles.bodySmall.copyWith(
                  color: tokens.metadataForeground,
                ),
              ),
              const SizedBox(height: 32),

              // Architecture card
              _PhaseCard(
                icon: Icons
                    .account_tree_outlined, // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
                title: 'Architecture',
                subtitle:
                    '${graph.nodes.length} nodes · ${graph.edges.length} edges',
                color: const Color(0xFF5C6BC0),
                emptyText: 'No architecture drawn yet',
                isEmpty: graph.nodes.isEmpty,
                onOpen: () => ref
                    .read(canvasProvider.notifier)
                    .setActiveTab(CanvasTab.architecture),
              ),

              const _Arrow(),

              // Train card
              _PhaseCard(
                icon: Icons
                    .model_training_outlined, // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
                title: 'Train',
                subtitle: _phaseSummary(phases.train),
                color: const Color(0xFF43A047),
                emptyText: 'Open Train canvas to build training pipeline',
                isEmpty: phases.train.nodes.isEmpty,
                onOpen: () => _openPipelineTab(ref, CanvasTab.pipelineTrain),
              ),

              const _Arrow(),

              // Eval card
              _PhaseCard(
                icon: ZetaIcons.chart_bar,
                title: 'Evaluate',
                subtitle: _phaseSummary(phases.eval),
                color: const Color(0xFF8E24AA),
                emptyText: 'Open Eval canvas to build evaluation pipeline',
                isEmpty: phases.eval.nodes.isEmpty,
                onOpen: () => _openPipelineTab(ref, CanvasTab.pipelineEval),
              ),

              const SizedBox(height: 32),
              const PipelineCnlPanel(),
            ],
          ),
        ),
      ),
    );
  }

  String _phaseSummary(PipelineDAG dag) {
    if (dag.nodes.isEmpty) return '';
    final labels = dag.nodes.take(4).map((n) => n.type.label).join(' → ');
    return dag.nodes.length > 4 ? '$labels …' : labels;
  }
}

// ── Phase card ────────────────────────────────────────────────────────────────

class _PhaseCard extends StatelessWidget {
  const _PhaseCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.emptyText,
    required this.isEmpty,
    required this.onOpen,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final String emptyText;
  final bool isEmpty;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(NmtkShellTokens.of(context).radiusSm),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            // Icon circle
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 16),
            // Content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Zeta.of(context).textStyles.labelMedium.copyWith(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  if (isEmpty)
                    Text(
                      emptyText,
                      style: Zeta.of(context).textStyles.bodyXSmall.copyWith(
                        fontSize: 11,
                        color: const Color(0xFF9E9E9E),
                      ),
                    )
                  else
                    Text(
                      subtitle,
                      style: Zeta.of(context).textStyles.bodyXSmall.copyWith(
                        fontSize: 11,
                        color: const Color(0xFF616161),
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            // Open button
            ZetaButton.text(
              onPressed: onOpen,
              label: '',
              semanticLabel: 'Open',
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(ZetaIcons.open_in_new_window, size: 14, color: color),
                  const SizedBox(width: 4),
                  Text(
                    'Open',
                    style: Zeta.of(context).textStyles.labelMedium.copyWith(color: color),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Arrow connector ───────────────────────────────────────────────────────────

class _Arrow extends StatelessWidget {
  const _Arrow();

  @override
  Widget build(BuildContext context) {
    return SizedBox(height: 32, child: CustomPaint(painter: _ArrowPainter()));
  }
}

class _ArrowPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFBDBDBD)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final cx = size.width / 2;
    // Dashed vertical line
    const dashH = 4.0;
    const gapH = 3.0;
    double y = 0;
    while (y < size.height - 10) {
      canvas.drawLine(
        Offset(cx, y),
        Offset(cx, (y + dashH).clamp(0, size.height - 10)),
        paint,
      );
      y += dashH + gapH;
    }
    // Arrowhead
    final arrowPaint = Paint()
      ..color = const Color(0xFFBDBDBD)
      ..style = PaintingStyle.fill;
    canvas.drawPath(
      Path()
        ..moveTo(cx, size.height)
        ..lineTo(cx - 6, size.height - 10)
        ..lineTo(cx + 6, size.height - 10)
        ..close(),
      arrowPaint,
    );
  }

  @override
  bool shouldRepaint(_ArrowPainter old) => false;
}
