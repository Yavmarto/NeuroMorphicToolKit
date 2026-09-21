import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

import 'package:neuro_toolkit/features/neurocnl/features/studio/deployment/deploy/neurosense_workspace/neurosense_setup_section.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/workspace_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/screens/neurosense_popup.dart';

/// Setup-stage chooser between file datasets and a live NeuroSense sensor feed.
class SetupInputSourceSection extends ConsumerWidget {
  const SetupInputSourceSection({super.key});

  static const String liveSensorKind = 'neurosense_live';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sourceKind = ref.watch(
      workspaceProvider.select((w) => w.workspaceSourceKind),
    );
    final usingLiveSensor = sourceKind == liveSensorKind;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Input source',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            NmtkOutlinedButton(
              key: const Key('setup-input-source-dataset'),
              label: 'Dataset file',
              icon: Icons.folder_outlined,
              onPressed: usingLiveSensor
                  ? () => ref
                        .read(workspaceProvider.notifier)
                        .setWorkspaceSourceKind(null)
                  : null,
            ),
            NmtkOutlinedButton(
              key: const Key('setup-input-source-live-sensor'),
              label: 'Live NeuroSense sensor',
              icon: Icons.sensors_outlined,
              onPressed: !usingLiveSensor
                  ? () => ref
                        .read(workspaceProvider.notifier)
                        .setWorkspaceSourceKind(liveSensorKind)
                  : null,
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          usingLiveSensor
              ? 'Using a live biosignal feed from NeuroSense. Configure the '
                    'sensor below (device, channel, sample rate).'
              : 'Using a dataset file from examples or disk.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        if (usingLiveSensor) ...[
          const SizedBox(height: 16),
          const NeurosenseSetupSection(),
          const SizedBox(height: 8),
          NmtkOutlinedButton(
            key: const Key('setup-open-neurosense-panel'),
            label: 'Open NeuroSense panel',
            icon: Icons.open_in_new,
            onPressed: () => showNeurosensePopup(
              context,
              initialTab: NeurosensePopupTab.devices,
            ),
          ),
        ],
      ],
    );
  }
}
