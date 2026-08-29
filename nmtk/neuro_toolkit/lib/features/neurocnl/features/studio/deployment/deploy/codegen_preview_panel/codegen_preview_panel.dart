library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart' hide AppTheme;

import 'package:neuro_toolkit/features/neurocnl/providers/spec_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/theme/app_theme.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/simulator_panel.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/deployment/deploy/deploy_target_catalog/support.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/deployment/deploy/studio_standard_deploy_page/studio_standard_deploy_page.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/deployment/deploy/codegen_preview_panel/codegen_setup_pane.dart';

class CodegenPreviewPanel extends ConsumerWidget {
  const CodegenPreviewPanel({super.key, required this.target});

  final String target;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spec = ref.watch(specTextProvider);
    final label = targetLabel(target);

    if (spec.trim().isEmpty) {
      return NmtkSection(
        title: '$label — Generated Code',
        subtitle:
            'Run an interactive compatibility preview on the left, then inspect or export target code on the right.',
        child: const Text(
          'Define and validate a network on the Architecture tab first.',
          style: TextStyle(color: AppTheme.textPrimary, fontSize: 12),
        ),
      );
    }

    final Widget inference = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Interactive compatibility preview',
          style: Zeta.of(context).textStyles.titleSmall,
        ),
        const SizedBox(height: 4),
        Text(
          'Runs the current CNL network with the snnTorch simulator. '
          'The generated target export is displayed in the setup pane on the right.',
          style: Zeta.of(context).textStyles.bodySmall,
        ),
        const SizedBox(height: 8),
        const SizedBox(
          height: 520,
          child: SimulatorPanel(
            initialBackend: 'snntorch_sim',
            showResults: true,
          ),
        ),
      ],
    );

    final Widget setup = CodegenSetupPane(target: target, spec: spec);

    return StudioStandardDeployPage(
      title: '$label — Generated Code',
      inference: inference,
      setup: setup,
    );
  }
}
