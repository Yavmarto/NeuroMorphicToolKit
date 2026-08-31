library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

import 'package:neuro_toolkit/features/neurocnl/providers/spec_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/studio_lava_deploy_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/simulator_panel.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/deployment/deploy/deploy_workspace_panel/mobile_deploy_action.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/deployment/deploy/studio_standard_deploy_page/studio_standard_deploy_page.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/deployment/deploy/lava_workspace/lava_execution_pane.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/deployment/deploy/lava_workspace/lava_setup_pane.dart';

class StudioLavaWorkspace extends ConsumerWidget {
  const StudioLavaWorkspace({super.key, required this.isCompact});

  final bool isCompact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = ref.watch(studioLavaDeployProvider);
    final notifier = ref.read(studioLavaDeployProvider.notifier);

    final exportResult = provider.exportResult;
    final runResult = provider.runResult;
    final warnings =
        (exportResult?['warnings'] as List<dynamic>? ?? const <dynamic>[])
            .map((value) => value.toString())
            .toList(growable: false);
    final rejections =
        (exportResult?['rejections'] as List<dynamic>? ?? const <dynamic>[])
            .map((value) => value.toString())
            .toList(growable: false);
    final supportState = exportResult?['support_state'] as String?;
    final spec = ref.read(specTextProvider);
    final mobileAction = switch ((exportResult, provider.sessionId)) {
      (null, _) => MobileDeployAction(
        id: 'lava-readiness',
        label: 'Check readiness',
        icon: Icons.fact_check_outlined,
        onPressed: provider.isBusy ? null : () => notifier.validate(spec),
      ),
      (_, null) => MobileDeployAction(
        id: 'lava-compile',
        label: provider.runConfig == 'hw' ? 'Check hardware' : 'Compile',
        icon: ZetaIcons.memory,
        onPressed: provider.isBusy ? null : () => notifier.compile(spec),
      ),
      _ when provider.runConfig == 'sim' => MobileDeployAction(
        id: 'lava-run',
        label: 'Run Lava simulation',
        icon: ZetaIcons.play,
        onPressed: provider.isBusy ? null : () => notifier.run(spec),
      ),
      _ => MobileDeployAction(
        id: 'lava-hardware-check',
        label: 'Check hardware',
        icon: ZetaIcons.memory,
        onPressed: provider.isBusy ? null : () => notifier.compile(spec),
      ),
    };

    final isSim = provider.runConfig == 'sim';

    final Widget inference = isSim
        ? SizedBox(
            height: isCompact ? 520 : 600,
            child: const SimulatorExecutionPane(
              key: ValueKey('lava-simulator-panel'),
              backend: 'lava_sim',
              showResults: false,
            ),
          )
        : LavaExecutionPane(
            provider: provider,
            supportState: supportState,
            warnings: warnings,
            rejections: rejections,
            runResult: runResult,
          );

    final Widget setup = LavaSetupPane(
      provider: provider,
      notifier: notifier,
      isCompact: isCompact,
      mobileAction: mobileAction,
    );

    return StudioStandardDeployPage(
      title: isSim ? 'Lava Simulator' : 'Lava / Loihi 2 Hardware',
      isCompact: isCompact,
      inference: inference,
      setup: setup,
    );
  }
}
