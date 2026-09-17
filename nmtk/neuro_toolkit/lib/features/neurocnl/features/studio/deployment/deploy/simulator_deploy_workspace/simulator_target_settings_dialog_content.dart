import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zeta_flutter/zeta_flutter.dart';

import 'package:neuro_toolkit/features/neurocnl/providers/simulator_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/simulator_panel.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/deployment/deploy/deploy_target_catalog/support.dart';

class SimulatorTargetSettingsDialogContent extends ConsumerWidget {
  const SimulatorTargetSettingsDialogContent({
    super.key,
    required this.backend,
  });

  final String backend;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textStyles = Zeta.of(context).textStyles;
    final colors = Zeta.of(context).colors;
    final isOverridden = ref.watch(
      simulatorOverriddenBackendsProvider.select((s) => s.contains(backend)),
    );
    final label = targetLabel(backend);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '$label settings',
                style: textStyles.titleMedium.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Tooltip(
              message: 'Close',
              child: ZetaIconButton.text(
                icon: ZetaIcons.close,
                semanticLabel: 'Close',
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ],
        ),
        if (isOverridden)
          Align(
            alignment: Alignment.centerLeft,
            child: ZetaButton.text(
              size: ZetaWidgetSize.small,
              leadingIcon: ZetaIcons.refresh,
              label: 'Reset to shared settings',
              onPressed: () {
                ref
                    .read(simulatorOverriddenBackendsProvider.notifier)
                    .setOverridden(backend, false);
                ref
                    .read(simulatorSettingsProvider(backend).notifier)
                    .setAll(ref.read(simulatorSharedSettingsProvider));
              },
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 8),
            child: Text(
              'Currently matching the shared settings above. Editing any '
              'field below gives $label its own settings instead.',
              style: textStyles.bodySmall.copyWith(color: colors.mainSubtle),
            ),
          ),
        const SizedBox(height: 8),
        SimulatorParametersSection(
          backend: backend,
          runButtonLabel: 'Run $label',
          onAnyFieldChanged: () => ref
              .read(simulatorOverriddenBackendsProvider.notifier)
              .setOverridden(backend, true),
        ),
      ],
    );
  }
}
