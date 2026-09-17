import 'package:flutter/material.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

import 'package:neuro_toolkit/features/neurocnl/features/studio/deployment/deploy/pynq_results_view/support.dart';

class PynqVerifyResultBody extends StatelessWidget {
  const PynqVerifyResultBody({super.key, required this.result});

  final PynqSitlVerifyResult result;

  @override
  Widget build(BuildContext context) {
    final textStyles = Zeta.of(context).textStyles;
    final tokens = NmtkShellTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: NmtkStatusBadge(
            label: result.passed
                ? 'Passed ${result.passedCases}/${result.totalCases}'
                : 'Failed ${result.totalCases - result.passedCases}/'
                      '${result.totalCases}',
            tone: result.passed ? NmtkTone.success : NmtkTone.danger,
            icon: result.passed
                ? ZetaIcons.check_circle_outline
                : ZetaIcons.warning,
          ),
        ),
        const SizedBox(height: 8),
        if (result.summary.trim().isNotEmpty)
          Text(result.summary.trim(), style: textStyles.bodySmall),
        const SizedBox(height: 8),
        NmtkKeyValueRow(
          label: 'Mean per case',
          value: formatPynqMicroseconds(result.meanExecUs),
        ),
        NmtkKeyValueRow(
          label: 'Slowest case',
          value: formatPynqMicroseconds(result.maxExecUs),
        ),
        if (result.steps.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            'Cases',
            style: textStyles.labelSmall.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          for (final step in result.steps)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    step.passed
                        ? ZetaIcons.check_circle_outline
                        : ZetaIcons.warning,
                    size: 14,
                    color: step.passed
                        ? tokens.healthyColor
                        : tokens.errorColor,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '${step.label} · ${step.outputSpikes.length} spike(s) '
                      'in ${formatPynqMicroseconds(step.executionTimeUs)}'
                      '${step.expectedOutputSpikes == null ? '' : ' · expected '
                                '${step.expectedOutputSpikes!.length}'}',
                      style: textStyles.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ],
    );
  }
}
