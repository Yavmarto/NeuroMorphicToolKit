import 'package:flutter/material.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

import 'package:neuro_toolkit/features/neurocnl/features/studio/deployment/deploy/neurosense_workspace/neurosense_source_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/shared/studio_shared.dart';

class NeurosenseSetupPane extends StatelessWidget {
  const NeurosenseSetupPane({
    super.key,
    required this.config,
    required this.onConfigureSource,
    this.statusMessage,
  });

  final NeuroSenseSensorConfig? config;
  final VoidCallback onConfigureSource;
  final String? statusMessage;

  @override
  Widget build(BuildContext context) {
    final textStyles = Zeta.of(context).textStyles;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Sensor setup',
          style: textStyles.titleMedium.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        if (config == null) ...[
          const StudioPhaseBanner(
            label: 'No live sensor source is configured.',
            tone: NmtkTone.warning,
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            key: const Key('neurosense-configure-source'),
            onPressed: onConfigureSource,
            icon: const Icon(Icons.sensors_outlined, size: 18),
            label: const Text('Configure sensor source'),
          ),
        ] else ...[
          const StudioPhaseBanner(
            label: 'Live sensor source ready',
            tone: NmtkTone.success,
          ),
          const SizedBox(height: 8),
          NmtkKeyValueRow(label: 'Device', value: config!.device.name),
          NmtkKeyValueRow(label: 'Channel', value: '${config!.channel}'),
          NmtkKeyValueRow(
            label: 'Sample rate',
            value: '${config!.sampleRateHz} Hz',
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            key: const Key('neurosense-reconfigure-source'),
            onPressed: onConfigureSource,
            icon: const Icon(Icons.settings_outlined, size: 18),
            label: const Text('Reconfigure sensor source'),
          ),
        ],
        if (statusMessage != null && statusMessage!.trim().isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            statusMessage!,
            style: textStyles.bodySmall.copyWith(
              color: Zeta.of(context).colors.mainSubtle,
            ),
          ),
        ],
      ],
    );
  }
}
