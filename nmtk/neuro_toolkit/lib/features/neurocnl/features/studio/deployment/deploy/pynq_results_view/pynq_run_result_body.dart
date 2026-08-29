import 'package:flutter/material.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';

import 'package:neuro_toolkit/features/neurocnl/features/studio/shared/presentation/studio_status_line.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/deployment/deploy/pynq_results_view/support.dart';

class PynqRunResultBody extends StatelessWidget {
  const PynqRunResultBody({
    super.key,
    required this.result,
    required this.hasTrainedWeights,
    this.expectedLabel,
  });

  final PynqRunResult result;

  /// Changes what "no output spikes" means, which is why it is passed down: with
  /// zero weights it is the only possible outcome and says nothing about the
  /// network, so blaming the input or the threshold would send the user hunting
  /// for a problem that is not there.
  final bool hasTrainedWeights;

  /// The evaluation sample's true label, when the run used one. Without it the
  /// predicted class is still shown — it just cannot be called right or wrong.
  final int? expectedLabel;

  @override
  Widget build(BuildContext context) {
    final textStyles = Zeta.of(context).textStyles;
    final colors = Zeta.of(context).colors;
    final predicted = result.predictedClass;
    final counts = result.spikeCountsPerNeuron;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!result.kernelReportedDone) ...[
          const StudioStatusLine(
            message:
                'The engine never reported finishing this run, so these '
                'numbers were read from a kernel that may not have computed '
                'them. Run it again.',
            tone: NmtkTone.warning,
          ),
          const SizedBox(height: 8),
        ],
        if (predicted != null) ...[
          Align(
            alignment: Alignment.centerLeft,
            child: NmtkStatusBadge(
              key: const Key('pynq-predicted-class'),
              label: expectedLabel == null
                  ? 'Board answered $predicted'
                  : predicted == expectedLabel
                  ? 'Board answered $predicted — correct'
                  : 'Board answered $predicted — expected $expectedLabel',
              tone: expectedLabel == null
                  ? NmtkTone.info
                  : predicted == expectedLabel
                  ? NmtkTone.success
                  : NmtkTone.warning,
              icon: expectedLabel == null || predicted == expectedLabel
                  ? ZetaIcons.check_circle_outline
                  : ZetaIcons.warning,
            ),
          ),
          const SizedBox(height: 12),
        ],
        NmtkKeyValueRow(label: 'Status', value: result.status),
        NmtkKeyValueRow(label: 'Timesteps', value: '${result.timesteps}'),
        NmtkKeyValueRow(label: 'Output spikes', value: '${result.totalSpikes}'),
        NmtkKeyValueRow(
          label: 'Execution time',
          value: formatPynqMicroseconds(result.executionTimeUs),
        ),
        const SizedBox(height: 12),
        Text(
          'Spikes per output neuron',
          style: textStyles.labelSmall.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        Text(
          switch ((result.totalSpikes == 0, hasTrainedWeights)) {
            (false, _) => [
              for (var index = 0; index < counts.length; index++)
                '$index: ${counts[index]}',
            ].join('   '),
            (true, false) =>
              'No output neuron fired, which is the only possible result here: '
                  'this deploy carried an all-zero weight matrix because the '
                  'workspace has no trained model. Run the NIR Exporter node, '
                  'then redeploy.',
            (true, true) =>
              'No output neuron fired. A single spiking input rarely reaches '
                  'the threshold — run an evaluation sample, and give it enough '
                  'timesteps for the membrane to charge.',
          },
          key: const Key('pynq-output-spikes'),
          style: textStyles.bodySmall.copyWith(
            color: result.totalSpikes == 0 ? colors.mainSubtle : null,
          ),
        ),
      ],
    );
  }
}
