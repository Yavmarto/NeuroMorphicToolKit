import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

import 'package:neuro_toolkit/features/neurocnl/providers/spec_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/studio_akida_deploy_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/canvas/canvas_parameter_text_field.dart';

class AkidaAdvancedScaffoldPane extends ConsumerWidget {
  // Local pane-width threshold, not a screen-level breakpoint — mirrors the
  // stacking threshold in AkidaSetupPane so the two panes behave the same
  // way as the embedded pane narrows.
  static const double _stackActionsWidth = 420;

  const AkidaAdvancedScaffoldPane({
    super.key,
    required this.provider,
    required this.selectedHost,
  });

  final StudioAkidaDeployState provider;
  final AkidaPairedHost? selectedHost;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(studioAkidaDeployProvider.notifier);
    final colors = Zeta.of(context).colors;
    final textStyles = Zeta.of(context).textStyles;
    final canMap =
        selectedHost != null &&
        provider.exportResult?.mappedNetwork != null &&
        !provider.isBusy;
    final canGenerate =
        selectedHost != null &&
        provider.exportResult?.mappedNetwork != null &&
        !provider.isBusy;
    final canRun =
        provider.sdkVerification?.isDeployable == true && !provider.isBusy;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'This path maps the canvas topology with placeholder weights. It '
          'checks hardware fit, but it cannot run the trained model.',
          style: textStyles.bodySmall.copyWith(color: colors.mainSubtle),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Akida version',
                  style: textStyles.labelSmall.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                SizedBox(
                  width: 200,
                  child: ZetaSegmentedControl<String>(
                    selected: provider.akidaVersion,
                    onChanged: provider.isBusy
                        ? (_) {}
                        : notifier.setAkidaVersion,
                    segments: const [
                      ZetaButtonSegment<String>(
                        value: 'akida1',
                        child: Text(
                          'Akida 1',
                          key: Key('akida-version-akida1'),
                        ),
                      ),
                      ZetaButtonSegment<String>(
                        value: 'akida2',
                        child: Text(
                          'Akida 2',
                          key: Key('akida-version-akida2'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Bit width',
                  style: textStyles.labelSmall.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                SizedBox(
                  width: 200,
                  child: ZetaSegmentedControl<int>(
                    selected: provider.bitWidth,
                    onChanged: provider.isBusy ? (_) {} : notifier.setBitWidth,
                    segments: const [
                      ZetaButtonSegment<int>(
                        value: 1,
                        child: Text('1-bit', key: Key('akida-bit-width-1')),
                      ),
                      ZetaButtonSegment<int>(
                        value: 2,
                        child: Text('2-bit', key: Key('akida-bit-width-2')),
                      ),
                      ZetaButtonSegment<int>(
                        value: 4,
                        child: Text('4-bit', key: Key('akida-bit-width-4')),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
        if (provider.sdkVerification?.isDeployable == true) ...[
          const SizedBox(height: 12),
          CanvasParameterTextField(
            key: const Key('akida-run-input-vector'),
            label: 'Run input vector',
            showLabel: true,
            value: provider.runInputVectorText,
            onCommit: notifier.setRunInputVectorText,
            enabled: !provider.isBusy,
            hintText: '1, 0, 0…',
          ),
        ],
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final actions = <Widget>[
              NmtkOutlinedButton(
                onPressed: provider.isBusy
                    ? null
                    : () =>
                          notifier.checkReadiness(ref.read(specTextProvider)),
                icon: Icons.fact_check_outlined,
                label: 'Check topology',
              ),
              NmtkOutlinedButton(
                onPressed: canGenerate
                    ? () => notifier.deploySelectedHost(
                        ref.read(specTextProvider),
                      )
                    : null,
                icon: ZetaIcons.document,
                label: 'Generate scaffold package',
              ),
              FilledButton.icon(
                onPressed: canMap
                    ? () =>
                          notifier.mapSelectedHost(ref.read(specTextProvider))
                    : null,
                icon: Icon(
                  ZetaIcons.memory,
                  size: 18,
                  color: Theme.of(context).colorScheme.onPrimary,
                ),
                label: const Text('Map runtime'),
              ),
              NmtkOutlinedButton(
                onPressed: canRun ? notifier.runSelectedHost : null,
                icon: ZetaIcons.play,
                label: 'Run placeholder inference',
              ),
            ];
            if (constraints.maxWidth < _stackActionsWidth) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var index = 0; index < actions.length; index++) ...[
                    actions[index],
                    if (index != actions.length - 1)
                      const SizedBox(height: 8),
                  ],
                ],
              );
            }
            return Wrap(spacing: 8, runSpacing: 8, children: actions);
          },
        ),
        if (provider.runResult != null) ...[
          const SizedBox(height: 12),
          NmtkKeyValueRow(
            label: 'Runtime target',
            value: provider.runResult!.runtimeTarget,
          ),
          NmtkKeyValueRow(
            label: 'Outputs',
            value: provider.runResult!.outputs.join(', '),
          ),
        ],
      ],
    );
  }
}
