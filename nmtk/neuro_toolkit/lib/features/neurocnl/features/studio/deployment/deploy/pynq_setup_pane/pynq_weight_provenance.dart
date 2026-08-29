import 'package:flutter/material.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';

import 'package:neuro_toolkit/features/neurocnl/providers/studio_pynq_deploy_provider.dart';

class PynqWeightProvenance extends StatelessWidget {
  const PynqWeightProvenance({super.key, required this.provider});

  final StudioPynqDeployState provider;

  @override
  Widget build(BuildContext context) {
    final textStyles = Zeta.of(context).textStyles;
    final status = provider.exportResult?.trainedWeights;

    final (NmtkTone tone, String label, String detail) = switch (status) {
      null => (
        NmtkTone.warning,
        'Untrained weights',
        'No trained model was found in this workspace, so the board would '
            'receive an all-zero weight matrix and fire nothing. Add a NIR '
            'Exporter node to the Training canvas and run the pipeline.',
      ),
      final s when s.isAllZero => (
        NmtkTone.warning,
        'Trained model is empty',
        s.detail,
      ),
      final s when s.applied => (NmtkTone.success, 'Trained weights', s.detail),
      final s => (NmtkTone.warning, 'Untrained weights', s.detail),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        NmtkStatusBadge(
          label: label,
          tone: tone,
          icon: tone == NmtkTone.success
              ? ZetaIcons.check_circle_outline
              : ZetaIcons.warning,
        ),
        if (detail.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            detail,
            key: const Key('pynq-weight-provenance-detail'),
            style: textStyles.bodySmall,
          ),
        ],
      ],
    );
  }
}
