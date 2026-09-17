import 'package:flutter/material.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart' hide AppTheme;

import 'package:neuro_toolkit/features/neurocnl/models/network_graph.dart';
import 'package:neuro_toolkit/features/neurocnl/theme/app_theme.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/deployment/presentation/compiled_artifacts/compiled_artifacts_metric_chip.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/deployment/presentation/compiled_artifacts/nengo_param_chip.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/deployment/presentation/compiled_artifacts/v_divider.dart';

/// Summary header for compiled Studio artifacts.

class CompiledArtifactsHeader extends StatelessWidget {
  const CompiledArtifactsHeader({
    super.key,
    required this.result,
    required this.ensembleNode,
  });

  final GenerateResult? result;
  final NetworkNode? ensembleNode;

  String _fmt(Object? v) {
    if (v is double) return v.toStringAsFixed(3);
    return v.toString();
  }

  @override
  Widget build(BuildContext context) {
    final hasResult = result != null;
    final cnlDocumentLines = hasResult
        ? '\n'.allMatches(result!.cnlDocument).length + 1
        : 0;
    final nirCodeLines = hasResult
        ? '\n'.allMatches(result!.nirCode).length + 1
        : 0;
    final tauRc = ensembleNode?.params['tau_rc'];
    final tauRef = ensembleNode?.params['tau_ref'];
    final nNeurons = ensembleNode?.params['n_neurons'];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(NmtkShellTokens.of(context).radiusSm),
        border: Border.all(color: AppTheme.border),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            Text(
              'Compiled Artifacts',
              style: Zeta.of(context).textStyles.labelMedium.copyWith(
                color: AppTheme.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 10),
            const VDivider(),
            const SizedBox(width: 10),
            CompiledArtifactsMetricChip(
              icon: Icons
                  .hub_outlined, // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
              label: hasResult ? '${result!.network.nodes.length} nodes' : '—',
            ),
            const SizedBox(width: 6),
            CompiledArtifactsMetricChip(
              icon: ZetaIcons.arrow_forward,
              label: hasResult ? '${result!.network.edges.length} edges' : '—',
            ),
            const SizedBox(width: 6),
            CompiledArtifactsMetricChip(
              icon: Icons
                  .code_outlined, // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
              label: hasResult ? '$cnlDocumentLines cnl' : '—',
            ),
            const SizedBox(width: 6),
            CompiledArtifactsMetricChip(
              icon: Icons
                  .account_tree_outlined, // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
              label: hasResult ? '$nirCodeLines nir' : '—',
            ),
            if (hasResult && ensembleNode != null) ...[
              const SizedBox(width: 10),
              const VDivider(),
              const SizedBox(width: 10),
              if (tauRc != null)
                NengoParamChip(label: 'τ_rc', value: _fmt(tauRc)),
              if (tauRef != null) ...[
                const SizedBox(width: 6),
                NengoParamChip(label: 'τ_ref', value: _fmt(tauRef)),
              ],
              if (nNeurons != null) ...[
                const SizedBox(width: 6),
                NengoParamChip(label: 'n', value: nNeurons.toString()),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
