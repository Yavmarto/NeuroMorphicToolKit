import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

import 'package:neuro_toolkit/features/neurocnl/providers/studio_lava_deploy_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/shell_surface.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/shared/studio_shared.dart';

class LavaExecutionPane extends ConsumerWidget {
  const LavaExecutionPane({
    super.key,
    required this.provider,
    required this.supportState,
    required this.warnings,
    required this.rejections,
    required this.runResult,
  });

  final StudioLavaDeployState provider;
  final String? supportState;
  final List<String> warnings;
  final List<String> rejections;
  final Map<String, dynamic>? runResult;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (supportState != null) ...[
          StudioPhaseBanner(
            label: switch (supportState) {
              'exportable' => 'Simulator run supported.',
              'exportable_with_warnings' =>
                'Simulator run supported with warnings.',
              'unsupported' => 'Unsupported for Lava simulator execution.',
              _ => supportState!,
            },
            tone: supportState == 'unsupported'
                ? NmtkTone.danger
                : supportState == 'exportable_with_warnings'
                ? NmtkTone.warning
                : NmtkTone.success,
          ),
          const SizedBox(height: 16),
        ],
        if (warnings.isNotEmpty) ...[
          NeurocnlMessageList(
            messages: warnings,
            tone: NmtkTone.warning,
            icon: ZetaIcons.warning_outline,
          ),
          const SizedBox(height: 16),
        ],
        if (rejections.isNotEmpty) ...[
          NeurocnlMessageList(
            messages: rejections,
            tone: NmtkTone.danger,
            icon: ZetaIcons.cancel_outline,
          ),
          const SizedBox(height: 16),
        ],
        if (runResult != null) ...[
          const StudioPhaseBanner(
            label: 'Simulator run completed — see the Review step.',
            tone: NmtkTone.success,
          ),
          const SizedBox(height: 16),
        ],
        if (provider.activityMessage != null ||
            provider.errorMessage != null) ...[
          StudioStatusLine(
            message: provider.errorMessage ?? provider.activityMessage!,
            tone: provider.errorMessage != null
                ? NmtkTone.danger
                : provider.isBusy
                ? NmtkTone.neutral
                : provider.phase == StudioLavaDeployPhase.completed
                ? NmtkTone.success
                : NmtkTone.neutral,
            loading: provider.isBusy,
          ),
        ],
      ],
    );
  }
}
