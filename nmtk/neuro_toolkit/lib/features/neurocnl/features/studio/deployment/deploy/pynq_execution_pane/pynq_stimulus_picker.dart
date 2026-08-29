import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';

import 'package:neuro_toolkit/features/neurocnl/providers/studio_pynq_deploy_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/workspace_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/deployment/presentation/pynq/stimulus_source_button.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/deployment/deploy/pynq_execution_pane/pynq_manual_stimulus.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/deployment/deploy/pynq_execution_pane/pynq_sample_picker.dart';

class PynqStimulusPicker extends ConsumerWidget {
  const PynqStimulusPicker({super.key, required this.provider});

  final StudioPynqDeployState provider;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(studioPynqDeployProvider.notifier);
    final workspaceName = ref.watch(workspaceProvider).workspaceName;
    final textStyles = Zeta.of(context).textStyles;
    final colors = Zeta.of(context).colors;
    final usingSample = provider.usingDatasetSample;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Input',
          style: textStyles.labelSmall.copyWith(color: colors.mainSubtle),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            StimulusSourceButton(
              key: const Key('pynq-input-source-sample'),
              label: 'Evaluation sample',
              selected: usingSample,
              onPressed: provider.isBusy
                  ? null
                  : () => notifier.setInputSource(
                      StudioPynqInputSource.datasetSample,
                    ),
            ),
            StimulusSourceButton(
              key: const Key('pynq-input-source-manual'),
              label: 'Type neurons',
              selected: !usingSample,
              onPressed: provider.isBusy
                  ? null
                  : () => notifier.setInputSource(
                      StudioPynqInputSource.manualIndices,
                    ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (usingSample)
          PynqSamplePicker(
            provider: provider,
            workspaceName: workspaceName,
            notifier: notifier,
          )
        else
          PynqManualStimulus(provider: provider, notifier: notifier),
      ],
    );
  }
}
