import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

import 'package:neuro_toolkit/features/neurocnl/providers/spec_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/shared/studio_shared.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/deployment/deployment_feature.dart';

class AkidaSetupPane extends ConsumerWidget {
  const AkidaSetupPane({
    super.key,
    required this.provider,
    required this.selectedHost,
    required this.workspaceName,
    required this.onCreateDemo,
    required this.isCompact,
    this.onManageHardwareTarget,
    this.onChooseBundle,
  });

  final StudioAkidaDeployState provider;
  final AkidaPairedHost? selectedHost;
  final String workspaceName;
  final VoidCallback onCreateDemo;
  final bool isCompact;
  final ValueChanged<String>? onManageHardwareTarget;
  final VoidCallback? onChooseBundle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(studioAkidaDeployProvider.notifier);
    final textStyles = Zeta.of(context).textStyles;
    final colors = Zeta.of(context).colors;
    final host = selectedHost;
    final bundle = provider.bundleArtifact;
    final needsInstall =
        host != null &&
        (host.installedRuntimeVersion.isEmpty ||
            (host.availableRuntimeVersion.isNotEmpty &&
                host.availableRuntimeVersion != host.installedRuntimeVersion));
    final deployAction = MobileDeployAction(
      id: 'akida-deploy',
      label: host == null
          ? 'Deploy latest bundle'
          : 'Deploy to ${host.displayName}',
      icon: ZetaIcons.cloud_upload,
      onPressed: host == null || bundle == null || provider.isBusy
          ? null
          : () => notifier.submitBundle(bundle),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Deployment setup',
          style: textStyles.titleMedium.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        if (host == null) ...[
          const StudioPhaseBanner(
            label: 'No Akida host is paired.',
            tone: NmtkTone.warning,
          ),
          const SizedBox(height: 8),
          if (onManageHardwareTarget != null)
            FilledButton.icon(
              key: const Key('akida-pair-host'),
              onPressed: () => onManageHardwareTarget!('akida'),
              icon: const Icon(Icons.settings_ethernet_outlined, size: 18),
              label: const Text('Pair or select host'),
            ),
        ] else ...[
          StudioPhaseBanner(
            label: host.state == AkidaPairedHostState.ready
                ? 'Hardware runtime ready'
                : host.state.label,
            tone: host.state == AkidaPairedHostState.ready
                ? NmtkTone.success
                : NmtkTone.warning,
          ),
          const SizedBox(height: 8),
          NmtkKeyValueRow(label: 'Host', value: host.displayName),
          NmtkKeyValueRow(
            label: 'Runtime',
            value: host.installedRuntimeVersion.isEmpty
                ? 'Not installed'
                : host.installedRuntimeVersion,
          ),
          if (host.lastReadinessMessage.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                host.lastReadinessMessage.trim(),
                style: textStyles.bodySmall.copyWith(color: colors.mainSubtle),
              ),
            ),
          if (host.capabilitySnapshot != null) ...[
            const SizedBox(height: 12),
            Text(
              'Runtime components',
              style: textStyles.labelSmall.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                AkidaCapabilityChip(
                  label: 'TensorFlow',
                  available: host.capabilitySnapshot!.tensorflowAvailable,
                ),
                AkidaCapabilityChip(
                  label: 'cnn2snn',
                  available: host.capabilitySnapshot!.cnn2snnAvailable,
                ),
                AkidaCapabilityChip(
                  label: 'akida_models',
                  available: host.capabilitySnapshot!.akidaModelsAvailable,
                ),
              ],
            ),
            // A missing component used to be a dead end whose only real
            // remedy was a terminal on the host. The runtime installer already
            // knows how to put these back.
            if (!host.capabilitySnapshot!.tensorflowAvailable ||
                !host.capabilitySnapshot!.cnn2snnAvailable ||
                !host.capabilitySnapshot!.akidaModelsAvailable) ...[
              const SizedBox(height: 8),
              NmtkPrimaryButton(
                key: const Key('akida-install-missing-components'),
                onPressed: provider.isBusy
                    ? null
                    : notifier.installSelectedHost,
                icon: ZetaIcons.download,
                label: 'Install missing components',
              ),
            ],
          ],
          if (provider.sdkVerification != null &&
              !provider.sdkVerification!.isDeployable) ...[
            const SizedBox(height: 12),
            const StudioStatusLine(
              message: 'Runtime mapping did not pass.',
              tone: NmtkTone.danger,
            ),
            if ((provider.sdkVerification!.sdkIssueDetail ?? '')
                .trim()
                .isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  provider.sdkVerification!.sdkIssueDetail!.trim(),
                  style: textStyles.bodySmall,
                ),
              ),
            for (final issue in provider.sdkVerification!.sdkIssues)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('• $issue', style: textStyles.bodySmall),
              ),
          ],
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              NmtkOutlinedButton(
                onPressed: provider.isBusy
                    ? null
                    : () => notifier.checkReadiness(ref.read(specTextProvider)),
                icon: ZetaIcons.check_circle_outline,
                label: 'Recheck',
              ),
              if (onManageHardwareTarget != null)
                NmtkOutlinedButton(
                  onPressed: () => onManageHardwareTarget!('akida'),
                  label: 'Change host',
                ),
              if (needsInstall)
                NmtkPrimaryButton(
                  onPressed: provider.isBusy
                      ? null
                      : notifier.installSelectedHost,
                  icon: ZetaIcons.download,
                  label: 'Install runtime',
                ),
            ],
          ),
        ],
        const SizedBox(height: 20),
        Divider(color: colors.borderSubtle),
        const SizedBox(height: 16),
        Text(
          'Trained-model bundle',
          style: textStyles.labelLarge.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        if (bundle == null)
          Text(
            'No bundle was found in this workspace. Run the Akida exporter or '
            'create the MNIST companion notebook.',
            style: textStyles.bodySmall.copyWith(color: colors.mainSubtle),
          )
        else ...[
          Text(
            bundle.schemaVersion > 0
                ? '${bundle.filename} · schema v${bundle.schemaVersion}'
                : bundle.filename,
            style: textStyles.bodySmall,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 12),
          if (!isCompact)
            NmtkPrimaryButton(
              key: const Key('akida-deploy-latest-bundle'),
              onPressed: host == null || provider.isBusy
                  ? null
                  : () => notifier.submitBundle(bundle),
              icon: ZetaIcons.cloud_upload,
              label: 'Deploy latest bundle',
            ),
        ],
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, constraints) {
            final stackActions = constraints.maxWidth < 420;
            final actions = <Widget>[
              NmtkOutlinedButton(
                onPressed: host == null || provider.isBusy
                    ? null
                    : onChooseBundle,
                icon: ZetaIcons.upload,
                label: 'Choose another',
              ),
              if (bundle == null)
                NmtkOutlinedButton(
                  onPressed: provider.isBusy ? null : onCreateDemo,
                  icon: ZetaIcons.document,
                  label: 'Create MNIST demo',
                ),
              NmtkOutlinedButton(
                onPressed: provider.isBusy || host == null
                    ? null
                    : () => notifier.discoverLatestBundle(workspaceName),
                icon: ZetaIcons.refresh,
                label: 'Refresh bundle',
              ),
            ];
            if (stackActions) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var index = 0; index < actions.length; index++) ...[
                    SizedBox(width: double.infinity, child: actions[index]),
                    if (index != actions.length - 1) const SizedBox(height: 8),
                  ],
                ],
              );
            }
            return Wrap(spacing: 8, runSpacing: 8, children: actions);
          },
        ),
        // Deploy-side progress only. A sample or benchmark run reports itself
        // in the execution pane, under the button that started it — this
        // column is often below the fold when that button is pressed.
        if (!provider.isRunning) ...[
          if (provider.activityMessage != null ||
              provider.errorMessage != null) ...[
            const SizedBox(height: 16),
            StudioStatusLine(
              message: provider.errorMessage ?? provider.activityMessage!,
              tone: provider.errorMessage != null
                  ? NmtkTone.danger
                  : provider.isBusy
                  ? NmtkTone.neutral
                  : NmtkTone.success,
              loading: provider.isBusy,
            ),
          ],
        ],
        const SizedBox(height: 20),
        if (isCompact) MobileDeployActionReporter(action: deployAction),
        ZetaAccordion(
          children: [
            ZetaAccordionItem(
              title: 'Advanced topology check',
              isExpanded: false,
              child: AkidaAdvancedScaffoldPane(
                provider: provider,
                selectedHost: host,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
