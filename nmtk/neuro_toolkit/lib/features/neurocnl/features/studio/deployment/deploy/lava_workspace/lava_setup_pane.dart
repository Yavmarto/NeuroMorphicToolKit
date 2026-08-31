import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

import 'package:neuro_toolkit/features/neurocnl/providers/spec_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/studio_lava_deploy_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/canvas/canvas_parameter_text_field.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/simulator_panel.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/shared/studio_shared.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/deployment/deploy/deploy_workspace_panel/mobile_deploy_action.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/deployment/deploy/deploy_workspace_panel/mobile_deploy_action_reporter.dart';

class LavaSetupPane extends ConsumerWidget {
  const LavaSetupPane({
    super.key,
    required this.provider,
    required this.notifier,
    required this.isCompact,
    required this.mobileAction,
  });

  final StudioLavaDeployState provider;
  final StudioLavaDeployController notifier;
  final bool isCompact;
  final MobileDeployAction mobileAction;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textStyles = Zeta.of(context).textStyles;
    final isSim = provider.runConfig == 'sim';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Deployment setup',
          style: textStyles.titleMedium.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        if (isSim) ...[
          Text(
            'The network is running in the isolated software simulator. '
            'To target Loihi 2 silicon via the hardware deployment service, '
            'prepare the hardware deployment pipeline below.',
            style: Zeta.of(context).textStyles.bodySmall,
          ),
          const SizedBox(height: 12),
          StudioHardwareActionWrap(
            actions: [
              StudioHardwareActionSpec(
                label: 'Prepare Loihi 2 hardware',
                icon: ZetaIcons.memory,
                variant: StudioHardwareActionVariant.outlined,
                onPressed: () => notifier.setRunConfig('hw'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SimulatorParametersSection(
            backend: 'lava_sim',
            runButtonLabel: 'Run Lava simulation',
            mobileActionBuilder: isCompact
                ? (onRun, isRunning) => MobileDeployActionReporter(
                    action: MobileDeployAction(
                      id: 'lava-sim-run',
                      label: isRunning ? 'Running…' : 'Run Lava simulation',
                      icon: ZetaIcons.play,
                      onPressed: onRun,
                    ),
                  )
                : null,
          ),
        ] else ...[
          Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              SizedBox(
                width: 200,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Weight bit-width',
                      style: TextStyle(
                        color: NmtkNeurocnlTokens.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(height: 4),
                    ZetaSegmentedControl<int>(
                      selected: provider.bitWidth,
                      onChanged: provider.isBusy
                          ? (_) {}
                          : (value) => notifier.setBitWidth(value),
                      segments: [
                        for (final bitWidth in const [8, 16])
                          ZetaButtonSegment<int>(
                            value: bitWidth,
                            child: KeyedSubtree(
                              key: Key('lava-bit-width-$bitWidth'),
                              child: Text('$bitWidth-bit'),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: 200,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Run config',
                      style: TextStyle(
                        color: NmtkNeurocnlTokens.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(height: 4),
                    ZetaSegmentedControl<String>(
                      selected: provider.runConfig,
                      onChanged: provider.isBusy
                          ? (_) {}
                          : (value) => notifier.setRunConfig(value),
                      segments: const [
                        ZetaButtonSegment<String>(
                          value: 'sim',
                          child: KeyedSubtree(
                            key: Key('lava-run-config-sim'),
                            child: Text('Simulator'),
                          ),
                        ),
                        ZetaButtonSegment<String>(
                          value: 'hw',
                          child: KeyedSubtree(
                            key: Key('lava-run-config-hw'),
                            child: Text('Hardware'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: 200,
                child: CanvasParameterTextField(
                  key: const Key('lava-run-steps'),
                  label: 'Run steps',
                  value: provider.runSteps.toString(),
                  onCommit: (v) => notifier.setRunSteps(
                    int.tryParse(v) ?? provider.runSteps,
                  ),
                  enabled: !provider.isBusy,
                  keyboardType: TextInputType.number,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          if (!isCompact)
            StudioHardwareActionWrap(
              actions: [
                StudioHardwareActionSpec(
                  label: 'Check Readiness',
                  icon: Icons
                      .fact_check_outlined, // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
                  variant: StudioHardwareActionVariant.outlined,
                  onPressed: provider.isBusy
                      ? null
                      : () => notifier.validate(ref.read(specTextProvider)),
                ),
                StudioHardwareActionSpec(
                  label: provider.runConfig == 'hw'
                      ? 'Check Hardware'
                      : 'Compile',
                  icon: ZetaIcons.memory,
                  onPressed: provider.isBusy
                      ? null
                      : () => notifier.compile(ref.read(specTextProvider)),
                ),
                StudioHardwareActionSpec(
                  label: 'Run',
                  icon: ZetaIcons.play,
                  onPressed: provider.runConfig == 'hw' || provider.isBusy
                      ? null
                      : () => notifier.run(ref.read(specTextProvider)),
                ),
              ],
            ),
          if (isCompact) MobileDeployActionReporter(action: mobileAction),
          const SizedBox(height: 16),
          StudioHardwareActionWrap(
            actions: [
              StudioHardwareActionSpec(
                label: 'Back to Lava simulator',
                icon: ZetaIcons.play,
                variant: StudioHardwareActionVariant.outlined,
                onPressed: provider.isBusy
                    ? null
                    : () => notifier.setRunConfig('sim'),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
