import 'package:flutter/material.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

import 'package:neuro_toolkit/features/neurocnl/providers/studio_pynq_deploy_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/deployment/deploy/pynq_execution_pane/sample_preview.dart';

class PynqSamplePicker extends StatelessWidget {
  const PynqSamplePicker({
    super.key,
    required this.provider,
    required this.workspaceName,
    required this.notifier,
  });

  final StudioPynqDeployState provider;
  final String workspaceName;
  final StudioPynqDeployController notifier;

  @override
  Widget build(BuildContext context) {
    final textStyles = Zeta.of(context).textStyles;
    final colors = Zeta.of(context).colors;
    final sample = provider.datasetSample;

    if (sample == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            provider.datasetSampleIssue ??
                'No evaluation sample loaded for this workspace yet.',
            key: const Key('pynq-sample-issue'),
            style: textStyles.bodySmall.copyWith(color: colors.mainSubtle),
          ),
          const SizedBox(height: 8),
          NmtkOutlinedButton(
            key: const Key('pynq-sample-retry'),
            onPressed: provider.isBusy
                ? null
                : () => notifier.loadDatasetSample(workspaceName),
            icon: ZetaIcons.refresh,
            label: 'Look again',
          ),
        ],
      );
    }

    final canStep = !provider.isBusy && sample.sampleCount > 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            SamplePreview(sample: sample),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (sample.label != null)
                    NmtkStatusBadge(
                      key: const Key('pynq-sample-label'),
                      label: 'Labelled ${sample.label}',
                      tone: NmtkTone.info,
                      icon: ZetaIcons.check_circle_outline,
                    ),
                  const SizedBox(height: 6),
                  Text(
                    'Sample ${sample.sampleIndex} of ${sample.sampleCount} · '
                    '${sample.spikeCount} of ${sample.inputWidth} inputs '
                    'spiking',
                    key: const Key('pynq-sample-summary'),
                    style: textStyles.labelSmall.copyWith(
                      color: colors.mainSubtle,
                    ),
                  ),
                  Text(
                    sample.filename,
                    style: textStyles.labelSmall.copyWith(
                      color: colors.mainSubtle,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            NmtkOutlinedButton(
              key: const Key('pynq-sample-previous'),
              onPressed: canStep && sample.sampleIndex > 0
                  ? () => notifier.loadDatasetSample(
                      workspaceName,
                      index: sample.sampleIndex - 1,
                    )
                  : null,
              label: 'Previous',
            ),
            NmtkOutlinedButton(
              key: const Key('pynq-sample-next'),
              onPressed: canStep && sample.sampleIndex < sample.sampleCount - 1
                  ? () => notifier.loadDatasetSample(
                      workspaceName,
                      index: sample.sampleIndex + 1,
                    )
                  : null,
              label: 'Next',
            ),
          ],
        ),
        const SizedBox(height: 6),
        // Stated once, here, because the gap is real and would otherwise read
        // as a fault in the board: the overlay's input is one bit per neuron,
        // so the greyscale the model trained on cannot be presented to it.
        Text(
          'The board takes a black-and-white frame, so shading is lost — '
          'expect it to get a few more digits wrong than the simulation does.',
          key: const Key('pynq-sample-fidelity-note'),
          style: textStyles.labelSmall.copyWith(color: colors.mainSubtle),
        ),
      ],
    );
  }
}
