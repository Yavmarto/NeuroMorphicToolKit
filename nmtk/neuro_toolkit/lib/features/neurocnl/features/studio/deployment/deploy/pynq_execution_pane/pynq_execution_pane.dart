import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

import 'package:neuro_toolkit/features/neurocnl/providers/studio_pynq_deploy_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/canvas/canvas_parameter_text_field.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/shared/studio_shared.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/deployment/deploy/deploy_workspace_panel/mobile_deploy_action.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/deployment/deploy/deploy_workspace_panel/mobile_deploy_action_reporter.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/deployment/deploy/pynq_workspace/support.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/deployment/deploy/pynq_execution_pane/pynq_run_complete.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/deployment/deploy/pynq_execution_pane/pynq_stimulus_picker.dart';

class PynqExecutionPane extends ConsumerStatefulWidget {
  const PynqExecutionPane({
    super.key,
    required this.provider,
    required this.isCompact,
  });

  final StudioPynqDeployState provider;
  final bool isCompact;

  @override
  ConsumerState<PynqExecutionPane> createState() => _PynqExecutionPaneState();
}

class _PynqExecutionPaneState extends ConsumerState<PynqExecutionPane> {
  String? _timestepsNote;

  void _commitTimesteps(String value) {
    final notifier = ref.read(studioPynqDeployProvider.notifier);
    final parsed = int.tryParse(value.trim());
    if (parsed == null) {
      setState(() => _timestepsNote = 'Enter a whole number.');
      return;
    }
    if (parsed < 1) {
      // The board rejects zero timesteps rather than doing nothing, so clamp
      // and say so instead of letting it fail downstream.
      setState(
        () => _timestepsNote = 'Using 1 — a run needs at least one step.',
      );
      notifier.setTimesteps(1);
      return;
    }
    if (_timestepsNote != null) setState(() => _timestepsNote = null);
    notifier.setTimesteps(parsed);
  }

  @override
  Widget build(BuildContext context) {
    final provider = widget.provider;
    final notifier = ref.read(studioPynqDeployProvider.notifier);
    final colors = Zeta.of(context).colors;
    final textStyles = Zeta.of(context).textStyles;
    final ack = provider.deployAck;
    final mobileAction = MobileDeployAction(
      id: ack == null ? 'pynq-deploy' : 'pynq-run',
      label: ack == null ? 'Deploy to board' : 'Run on board',
      icon: ack == null ? ZetaIcons.cloud_upload : ZetaIcons.play,
      onPressed: ack == null
          ? (provider.canDeploy ? notifier.deploy : null)
          : (provider.canRun ? notifier.run : null),
    );

    if (ack == null) {
      return DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surfaceHover,
          borderRadius: BorderRadius.circular(
            NmtkShellTokens.of(context).radiusLg,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(ZetaIcons.memory, size: 28, color: colors.mainSubtle),
              const SizedBox(height: 12),
              Text(
                provider.isExportable
                    ? 'Load this network onto the board to run it on the FPGA.'
                    : 'This network does not fit the PYNQ-Z2 overlay yet — see '
                          'Network fit for what to change.',
                textAlign: TextAlign.center,
                style: textStyles.bodyMedium.copyWith(color: colors.mainSubtle),
              ),
              const SizedBox(height: 16),
              if (!widget.isCompact)
                NmtkPrimaryButton(
                  key: const Key('pynq-deploy-network'),
                  onPressed: provider.canDeploy ? notifier.deploy : null,
                  icon: ZetaIcons.cloud_upload,
                  label: 'Deploy to board',
                ),
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
              if (widget.isCompact)
                MobileDeployActionReporter(action: mobileAction),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'PYNQ-Z2 inference',
                style: textStyles.titleMedium.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            pynqProvenanceBadge(ack),
          ],
        ),
        const SizedBox(height: 16),
        PynqStimulusPicker(provider: provider),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.end,
          children: [
            SizedBox(
              width: 160,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Timesteps',
                    style: textStyles.labelSmall.copyWith(
                      color: colors.mainSubtle,
                    ),
                  ),
                  const SizedBox(height: 4),
                  CanvasParameterTextField(
                    key: const Key('pynq-timesteps'),
                    label: 'Timesteps',
                    showLabel: false,
                    value: '${provider.timesteps}',
                    onCommit: _commitTimesteps,
                    onSubmitted: provider.canRun ? notifier.run : null,
                    keyboardType: TextInputType.number,
                    placeholder: '1',
                    errorText: _timestepsNote,
                    enabled: !provider.isBusy,
                  ),
                ],
              ),
            ),
            if (!widget.isCompact)
              NmtkPrimaryButton(
                key: const Key('pynq-run-network'),
                onPressed: provider.canRun ? notifier.run : null,
                icon: ZetaIcons.play,
                label: 'Run on board',
              ),
            NmtkOutlinedButton(
              key: const Key('pynq-verify-network'),
              onPressed: provider.isBusy ? null : notifier.verify,
              icon: ZetaIcons.check_circle_outline,
              label: 'Verify',
            ),
            NmtkOutlinedButton(
              key: const Key('pynq-redeploy-network'),
              onPressed: provider.canDeploy ? notifier.deploy : null,
              icon: ZetaIcons.cloud_upload,
              label: 'Redeploy',
            ),
          ],
        ),
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
        if (provider.runResult != null || provider.verifyResult != null) ...[
          const SizedBox(height: 16),
          const PynqRunComplete(),
        ],
        if (widget.isCompact) MobileDeployActionReporter(action: mobileAction),
      ],
    );
  }
}
