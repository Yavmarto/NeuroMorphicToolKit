import 'package:flutter/material.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

import 'package:neuro_toolkit/features/neurocnl/features/studio/deployment/deploy/simulator_deploy_workspace/simulator_target_settings_dialog_content.dart';

/// Runs every simulator target at once, reusing the same
/// [runSimulatorBackend] each row's own Run action calls — "run all" isn't a
/// separate code path, it's that call made three times.

/// Timesteps/Seed/Firing Rate/dt, edited once and pushed to every simulator
/// backend not present in [simulatorOverriddenBackendsProvider].

void showSimulatorTargetSettings(BuildContext context, String backend) {
  showDialog<void>(
    context: context,
    builder: (dialogContext) => Dialog(
      shape: RoundedRectangleBorder(borderRadius: NmtkDesignTokens.dialogShape),
      insetPadding: NmtkDialogSurface.insetPadding(dialogContext),
      child: SafeArea(
        child: ConstrainedBox(
          constraints: NmtkDialogSurface.constraints(
            dialogContext,
            maxWidth: 420,
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: SingleChildScrollView(
              child: SimulatorTargetSettingsDialogContent(backend: backend),
            ),
          ),
        ),
      ),
    ),
  );
}
