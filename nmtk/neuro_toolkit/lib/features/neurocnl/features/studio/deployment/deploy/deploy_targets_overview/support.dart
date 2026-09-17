library;

import 'package:flutter/material.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

import 'package:neuro_toolkit/features/neurocnl/features/studio/deployment/deploy/akida_workspace/studio_akida_workspace.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/deployment/deploy/codegen_preview_panel/codegen_preview_panel.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/deployment/deploy/deploy_target_catalog/support.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/deployment/deploy/lava_workspace/studio_lava_workspace.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/deployment/deploy/neurosense_workspace/studio_neurosense_workspace.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/deployment/deploy/pynq_workspace/studio_pynq_workspace.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/deployment/deploy/sc_neurocore_fpga_workspace/studio_sc_neuro_core_fpga_workspace.dart';

/// Deploy step content: every deploy target listed as rows in real tables
/// (columns, not stacked cards) instead of one page per target reached
/// through a dropdown. Fixed hardware targets (Akida/PYNQ/SC-NeuroCore FPGA)
/// get one table whose "Configure" action opens that target's existing
/// full setup/execution page in a dialog; software simulators get a second
/// table with the shared-settings-cascade + per-row override model, with
/// Lava / Loihi2 as its own row right below that table (it defaults to
/// simulator mode, so it's grouped with the simulators, not the fixed
/// hardware targets above).

/// Real columnar table for the hardware/RTL deploy targets Setup selected.
/// Reused as-is for the standalone Lava / Loihi2 row under the simulators
/// section — [tableKey] must differ between the two so they don't collide
/// as sibling keys when both render at once.

/// Real columnar table for the software-simulator deploy targets Setup
/// selected. Timesteps/Seed/Firing Rate/dt are edited once in
/// [SharedSimulatorSettingsCard] above and cascade to every row not
/// individually overridden via that row's gear icon.

/// Opens a hardware target's existing full setup/execution page — unchanged
/// from before the table merge — inside a dialog, since these pages (device
/// pairing, overlay/synthesis setup, benchmark controls) are too involved to
/// flatten into a single table row.
void showHardwareTargetDialog(
  BuildContext context,
  String targetId, {
  required String? deviceLabel,
  required Object? deviceData,
  required ValueChanged<String>? onManageHardwareTarget,
}) {
  showDialog<void>(
    context: context,
    builder: (dialogContext) => Dialog(
      insetPadding: const EdgeInsets.all(24),
      shape: RoundedRectangleBorder(borderRadius: NmtkDesignTokens.dialogShape),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1100, maxHeight: 780),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 8, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      targetLabel(targetId),
                      style: Zeta.of(dialogContext).textStyles.titleMedium
                          .copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  Tooltip(
                    message: 'Close',
                    child: ZetaIconButton.text(
                      icon: ZetaIcons.close,
                      semanticLabel: 'Close',
                      onPressed: () => Navigator.of(dialogContext).pop(),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: switch (targetId) {
                  'akida' => StudioAkidaWorkspace(
                    selectedDeviceLabel: deviceLabel,
                    selectedDeviceData: deviceData,
                    isCompact: false,
                    onManageHardwareTarget: onManageHardwareTarget,
                  ),
                  'pynq' => StudioPynqWorkspace(
                    selectedDeviceLabel: deviceLabel,
                    selectedDeviceData: deviceData,
                    isCompact: false,
                    onManageHardwareTarget: onManageHardwareTarget,
                  ),
                  'lava' => const StudioLavaWorkspace(isCompact: false),
                  'sc_neurocore_fpga' => StudioScNeuroCoreFpgaWorkspace(
                    selectedDeviceLabel: deviceLabel,
                    selectedDeviceData: deviceData,
                  ),
                  _ => const SizedBox.shrink(),
                },
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Opens a live sensor source's own workspace — separate from
/// [showHardwareTargetDialog] because sensor sources aren't in [deployTargets]
/// and don't carry an SSH-paired device to display in the title bar.
void showLiveSourceDialog(BuildContext context, String targetId) {
  showDialog<void>(
    context: context,
    builder: (dialogContext) => Dialog(
      insetPadding: const EdgeInsets.all(24),
      shape: RoundedRectangleBorder(borderRadius: NmtkDesignTokens.dialogShape),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1100, maxHeight: 780),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 8, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      sensorSourceForId(targetId)?.label ?? targetId,
                      style: Zeta.of(dialogContext).textStyles.titleMedium
                          .copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  Tooltip(
                    message: 'Close',
                    child: ZetaIconButton.text(
                      icon: ZetaIcons.close,
                      semanticLabel: 'Close',
                      onPressed: () => Navigator.of(dialogContext).pop(),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: switch (targetId) {
                  'neurosense' => const StudioNeuroSenseWorkspace(),
                  _ => const SizedBox.shrink(),
                },
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Opens a codegen-only target's read-only compatibility/code preview —
/// unchanged from before the table merge — inside a dialog.
void showCodegenTargetDialog(BuildContext context, String targetId) {
  showDialog<void>(
    context: context,
    builder: (dialogContext) => Dialog(
      insetPadding: const EdgeInsets.all(24),
      shape: RoundedRectangleBorder(borderRadius: NmtkDesignTokens.dialogShape),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1100, maxHeight: 780),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 8, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${targetLabel(targetId)} code',
                      style: Zeta.of(dialogContext).textStyles.titleMedium
                          .copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  Tooltip(
                    message: 'Close',
                    child: ZetaIconButton.text(
                      icon: ZetaIcons.close,
                      semanticLabel: 'Close',
                      onPressed: () => Navigator.of(dialogContext).pop(),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: CodegenPreviewPanel(
                  key: ValueKey('codegen-$targetId'),
                  target: targetId,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
