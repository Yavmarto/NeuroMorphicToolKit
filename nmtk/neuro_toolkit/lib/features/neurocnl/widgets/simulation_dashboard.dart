import 'package:flutter/material.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:neuro_toolkit/features/neurocnl/l10n/app_localizations.dart';
import 'package:neuro_toolkit/features/neurocnl/models/network_graph.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/pipeline_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/services/deploy_error_formatter.dart';

/// Preview panel for the generate-backed NIR-only Studio surface.
class SimulationDashboard extends ConsumerWidget {
  const SimulationDashboard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pipeline = ref.watch(pipelineProvider);
    final preview = pipeline.generateResult;
    final l10n = AppLocalizations.of(context)!;

    if (pipeline.errorMessage != null &&
        (pipeline.generateStatus == StepStatus.error ||
            pipeline.simulateStatus == StepStatus.error)) {
      final error = extractPipelineStepError(
        pipeline.errorMessage,
        stepLabel: 'Preview',
      );
      return _PreviewErrorState(
        title: error.title,
        message: error.message,
        hint: error.hint,
      );
    }

    if (preview == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons
                  .account_tree_outlined, // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
              size: 48,
              color: Zeta.of(context).colors.mainSubtle.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 16),
            Text(
              l10n.runToSeeResults,
              style: Zeta.of(context).textStyles.bodyMedium.copyWith(
                color: Zeta.of(context).colors.mainSubtle,
              ),
            ),
          ],
        ),
      );
    }

    final nodes = preview.network.nodes;
    final edges = preview.network.edges;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _PreviewSummaryCard(
          nodeCount: nodes.length,
          edgeCount: edges.length,
          nirLength: preview.nirCode.length,
        ),
        const SizedBox(height: 16),
        _TopologyCard(nodes: nodes, edges: edges),
        const SizedBox(height: 16),
        _NirPreviewCard(nirCode: preview.nirCode),
      ],
    );
  }
}

class _PreviewErrorState extends StatelessWidget {
  const _PreviewErrorState({
    required this.title,
    required this.message,
    this.hint,
  });

  final String title;
  final String message;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final errorColor = Zeta.of(context).colors.mainNegative;
    return Center(
      child: Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.all(16),
        constraints: const BoxConstraints(maxWidth: 560),
        decoration: BoxDecoration(
          color: errorColor.withValues(alpha: 0.08),
          border: Border.all(color: errorColor.withValues(alpha: 0.3)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(ZetaIcons.error_outline, color: errorColor, size: 20),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: Zeta.of(
                    context,
                  ).textStyles.bodyMedium.copyWith(color: errorColor),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: Zeta.of(context).textStyles.bodySmall.copyWith(
                color: Zeta.of(context).colors.mainDefault,
              ),
            ),
            if (hint != null) ...[
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons
                        .lightbulb_outline, // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
                    color: Zeta.of(
                      context,
                    ).colors.mainSubtle.withValues(alpha: 0.85),
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      hint!,
                      style: Zeta.of(context).textStyles.bodySmall.copyWith(
                        color: Zeta.of(context).colors.mainSubtle,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PreviewSummaryCard extends StatelessWidget {
  const _PreviewSummaryCard({
    required this.nodeCount,
    required this.edgeCount,
    required this.nirLength,
  });

  final int nodeCount;
  final int edgeCount;
  final int nirLength;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Zeta.of(context).colors.surfacePrimary,
        border: Border.all(color: Zeta.of(context).colors.borderDefault),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                ZetaIcons.analytics,
                size: 16,
                color: Zeta.of(context).colors.mainPrimary,
              ),
              const SizedBox(width: 8),
              Text(
                l10n.simulationSummary,
                style: Zeta.of(context).textStyles.bodyMedium.copyWith(
                  color: Zeta.of(context).colors.mainDefault,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              _StatChip(label: 'Nodes', value: '$nodeCount'),
              _StatChip(label: 'Edges', value: '$edgeCount'),
              _StatChip(label: 'NIR chars', value: '$nirLength'),
            ],
          ),
        ],
      ),
    );
  }
}

class _TopologyCard extends StatelessWidget {
  const _TopologyCard({required this.nodes, required this.edges});

  final List<NetworkNode> nodes;
  final List<NetworkEdge> edges;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Zeta.of(context).colors.surfacePrimary,
        border: Border.all(color: Zeta.of(context).colors.borderDefault),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Compiled Topology',
            style: Zeta.of(context).textStyles.bodyMedium.copyWith(
              color: Zeta.of(context).colors.mainDefault,
            ),
          ),
          const SizedBox(height: 8),
          for (final node in nodes) ...[
            _TopologyRow(
              leading: node.label,
              trailing: '${node.type}/${node.subtype}',
            ),
            const SizedBox(height: 8),
          ],
          if (nodes.isEmpty)
            Text(
              'No generated nodes.',
              style: Zeta.of(context).textStyles.bodySmall.copyWith(
                color: Zeta.of(context).colors.mainSubtle,
              ),
            ),
          if (edges.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Connections',
              style: Zeta.of(context).textStyles.bodySmall.copyWith(
                color: Zeta.of(context).colors.mainSubtle,
              ),
            ),
            const SizedBox(height: 8),
            for (final edge in edges) ...[
              _TopologyRow(
                leading: '${edge.source} -> ${edge.target}',
                trailing: edge.isInhibitory ? 'inhibitory' : 'excitatory',
              ),
              const SizedBox(height: 8),
            ],
          ],
        ],
      ),
    );
  }
}

class _NirPreviewCard extends StatelessWidget {
  const _NirPreviewCard({required this.nirCode});

  final String nirCode;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Zeta.of(context).colors.surfacePrimary,
        border: Border.all(color: Zeta.of(context).colors.borderDefault),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'NIR Graph Preview (JSON)',
            style: Zeta.of(context).textStyles.bodyMedium.copyWith(
              color: Zeta.of(context).colors.mainDefault,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Inspection view only — use Export → NIR to download the binary .nir file.',
            style: Zeta.of(context).textStyles.bodySmall.copyWith(
              color: Zeta.of(context).colors.mainSubtle,
            ),
          ),
          const SizedBox(height: 8),
          Text(nirCode, style: Zeta.of(context).textStyles.bodyMedium),
        ],
      ),
    );
  }
}

class _TopologyRow extends StatelessWidget {
  const _TopologyRow({required this.leading, required this.trailing});

  final String leading;
  final String trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            leading,
            style: Zeta.of(context).textStyles.bodySmall.copyWith(
              color: Zeta.of(context).colors.mainDefault,
            ),
          ),
        ),
        const SizedBox(width: 16),
        Text(
          trailing,
          style: Zeta.of(context).textStyles.bodySmall.copyWith(
            color: Zeta.of(context).colors.mainSubtle,
          ),
        ),
      ],
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Zeta.of(context).colors.surfaceHover,
        border: Border.all(color: Zeta.of(context).colors.borderDefault),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Zeta.of(context).textStyles.bodySmall.copyWith(
              color: Zeta.of(context).colors.mainSubtle,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: Zeta.of(context).textStyles.bodyMedium.copyWith(
              color: Zeta.of(context).colors.mainDefault,
            ),
          ),
        ],
      ),
    );
  }
}
