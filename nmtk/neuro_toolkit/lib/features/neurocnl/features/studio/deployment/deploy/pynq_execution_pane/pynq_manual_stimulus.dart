import 'package:flutter/material.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';

import 'package:neuro_toolkit/features/neurocnl/providers/studio_pynq_deploy_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/canvas/canvas_parameter_text_field.dart';

class PynqManualStimulus extends StatelessWidget {
  const PynqManualStimulus({
    super.key,
    required this.provider,
    required this.notifier,
  });

  final StudioPynqDeployState provider;
  final StudioPynqDeployController notifier;

  @override
  Widget build(BuildContext context) {
    final textStyles = Zeta.of(context).textStyles;
    final colors = Zeta.of(context).colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CanvasParameterTextField(
          key: const Key('pynq-input-spikes'),
          label: 'Input neurons that spike',
          showLabel: false,
          value: provider.inputSpikesText,
          onCommit: notifier.setInputSpikesText,
          placeholder: '0, 3, 7',
          enabled: !provider.isBusy,
        ),
        const SizedBox(height: 4),
        // The board receives a whole frame per timestep, not this list — the
        // list is expanded in `buildInputFrames`. Saying so here is what stops
        // the numbers reading as "how many spikes to send in total".
        Text(
          provider.inputNeuronCount > 0
              ? 'Numbered 0 to ${provider.inputNeuronCount - 1}. Each one '
                    'spikes on every timestep.'
              : 'Each one spikes on every timestep.',
          key: const Key('pynq-input-spikes-helper'),
          style: textStyles.labelSmall.copyWith(color: colors.mainSubtle),
        ),
      ],
    );
  }
}
