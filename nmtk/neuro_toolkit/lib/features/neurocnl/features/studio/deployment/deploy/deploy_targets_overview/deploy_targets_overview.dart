library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

import 'package:neuro_toolkit/features/neurocnl/providers/deploy_results_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/workspace_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/deployment/deploy/deploy_target_catalog/support.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/deployment/deploy/simulator_deploy_workspace/run_all_simulators_button.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/deployment/deploy/simulator_deploy_workspace/shared_simulator_settings_card.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/deployment/deploy/deploy_targets_overview/hardware_targets_table.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/deployment/deploy/deploy_targets_overview/simulator_targets_table.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/deployment/deploy/deploy_targets_overview/support.dart';

class DeployTargetsOverview extends ConsumerWidget {
  const DeployTargetsOverview({
    super.key,
    required this.selectedDeviceLabels,
    required this.selectedDeviceData,
    required this.onSelectTarget,
    this.onManageHardwareTarget,
  });

  // 'lava' (Lava / Loihi2) is deliberately not in this list even though it is
  // deploy-capable — it defaults to running the software simulator
  // (`StudioLavaDeployState.runConfig` starts at `'sim'`) and only switches to
  // real Loihi2 hardware when the user flips its own internal toggle, so it's
  // grouped with the simulators below instead.
  static final hardwareTargetIds = deployTargets
      .where((t) => t.deployCapable && t.id != 'lava')
      .map((t) => t.id)
      .toList(growable: false);

  /// Paired-device display label per hardware target id, if any.
  final Map<String, String> selectedDeviceLabels;

  /// Raw paired-device data (e.g. `AkidaPairedHost`) per hardware target id.
  final Map<String, Object> selectedDeviceData;

  /// Marks a target as the "active" one for validation/preflight scheduling —
  /// same provider the old dropdown drove, now updated when a target's
  /// dialog opens instead of when it's picked from a list.
  final ValueChanged<String> onSelectTarget;
  final ValueChanged<String>? onManageHardwareTarget;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textStyles = Zeta.of(context).textStyles;
    final selectedPlatforms = ref.watch(
      workspaceProvider.select((w) => w.selectedPlatforms),
    );
    // Setup owns platform selection — Deploy only shows what was ticked
    // there, same as the old dropdown did. A fresh workspace with nothing
    // ticked yet falls back to showing everything rather than two empty
    // sections, since the step gate normally prevents reaching Deploy that
    // way but a persisted/edge-case workspace still could.
    final anyKnownSelected = selectedPlatforms.any(
      (id) => deployTargets.any((t) => t.id == id),
    );
    final hardwareIds = anyKnownSelected
        ? DeployTargetsOverview.hardwareTargetIds
              .where(selectedPlatforms.contains)
              .toList(growable: false)
        : DeployTargetsOverview.hardwareTargetIds;
    final simulatorIds = anyKnownSelected
        ? kSimulatorDeployBackends
              .where(selectedPlatforms.contains)
              .toList(growable: false)
        : kSimulatorDeployBackends;
    final frameworkRuntimeIds = anyKnownSelected
        ? frameworkRuntimeBackendIds()
              .where(selectedPlatforms.contains)
              .toList(growable: false)
        : frameworkRuntimeBackendIds();
    final runtimeBackendIds = <String>[
      ...simulatorIds,
      ...frameworkRuntimeIds,
    ];
    final lavaSelected =
        !anyKnownSelected || selectedPlatforms.contains('lava');
    final exportOnlyIds = anyKnownSelected
        ? deployTargets
              .where(
                (t) =>
                    targetIsExportOnly(t.id) &&
                    selectedPlatforms.contains(t.id),
              )
              .map((t) => t.id)
              .toList(growable: false)
        : deployTargets
              .where((t) => targetIsExportOnly(t.id))
              .map((t) => t.id)
              .toList(growable: false);

    return Column(
      key: const Key('deploy-targets-overview'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (runtimeBackendIds.isNotEmpty || lavaSelected) ...[
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 8,
            children: [
              Text(
                'Runtime Targets',
                style: textStyles.titleMedium.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (simulatorIds.isNotEmpty)
                RunAllSimulatorsButton(backends: simulatorIds),
            ],
          ),
          if (runtimeBackendIds.isNotEmpty) ...[
            const SizedBox(height: 12),
            // Table on the left, shared-settings card fixed to a 340px-wide
            // panel on the right (2-column field grid) — a full-width
            // settings bar above the table
            // read as mostly empty space for just 4 fields; a fixed-width
            // side panel doesn't reflow as the table's rows change, either.
            // Below `NmtkShellTokens.normalBreakpoint` (the same threshold
            // `NmtkDeployLayout` uses for its inference/setup split) there
            // isn't room for both side by side, so it stacks instead.
            LayoutBuilder(
              builder: (context, constraints) {
                final table = SimulatorTargetsTable(
                  backends: runtimeBackendIds,
                  onFrameworkRun: frameworkRuntimeIds.isEmpty
                      ? null
                      : (dialogContext, targetId) {
                          onSelectTarget(targetId);
                          showCodegenTargetDialog(dialogContext, targetId);
                        },
                );
                final settings = SharedSimulatorSettingsCard(
                  backends: simulatorIds,
                );
                if (simulatorIds.isEmpty) {
                  return table;
                }
                if (constraints.maxWidth < NmtkShellTokens.normalBreakpoint) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [table, const SizedBox(height: 12), settings],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: table),
                    const SizedBox(width: 16),
                    SizedBox(width: 340, child: settings),
                  ],
                );
              },
            ),
          ],
          if (lavaSelected) ...[
            const SizedBox(height: 12),
            // Lava / Loihi2 lives here, not in the Hardware Targets table
            // below: it defaults to running the software simulator and only
            // becomes real hardware when its own dialog's toggle is
            // switched, so grouping it with the true fixed-hardware targets
            // was misleading. It keeps the same row shape as that table
            // (Target/Status/Results/Training/Configure) since nothing about
            // how it's opened or what it reports has changed — but it gets
            // its own sub-heading + "Hybrid" badge here so that dual nature
            // is visible on screen instead of living only in this comment.
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 4,
              children: [
                Text(
                  'Lava / Loihi2',
                  style: textStyles.bodyMedium.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Tooltip(
                  message:
                      'Runs as a software simulator by default, becomes '
                      'real Loihi2 hardware when toggled inside Configure.',
                  child: NmtkStatusBadge(
                    label: 'Hybrid',
                    tone: NmtkTone.info,
                    icon: ZetaIcons.swap,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            HardwareTargetsTable(
              tableKey: const Key('lava-hardware-table'),
              targetIds: const ['lava'],
              selectedDeviceLabels: selectedDeviceLabels,
              selectedDeviceData: selectedDeviceData,
              onOpenTarget: (String id) => _openHardwareTarget(context, id),
            ),
          ],
          const SizedBox(height: 24),
        ],
        if (hardwareIds.isNotEmpty) ...[
          Text(
            'Hardware Targets',
            style: textStyles.titleMedium.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          HardwareTargetsTable(
            targetIds: hardwareIds,
            selectedDeviceLabels: selectedDeviceLabels,
            selectedDeviceData: selectedDeviceData,
            onOpenTarget: (String id) => _openHardwareTarget(context, id),
          ),
        ],
        if (exportOnlyIds.isNotEmpty) ...[
          const SizedBox(height: 24),
          Text(
            'Export-only Targets',
            style: textStyles.titleMedium.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            'SpiNNaker handoff via PyNN — preview export code only, no in-app run.',
            style: textStyles.bodySmall.copyWith(
              color: Zeta.of(context).colors.mainSubtle,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final id in exportOnlyIds)
                ZetaButton.outline(
                  key: Key('export-only-target-preview-$id'),
                  size: ZetaWidgetSize.small,
                  label: '${targetLabel(id)} export',
                  onPressed: () {
                    onSelectTarget(id);
                    showCodegenTargetDialog(context, id);
                  },
                ),
            ],
          ),
        ],
      ],
    );
  }

  void _openHardwareTarget(BuildContext context, String targetId) {
    onSelectTarget(targetId);
    showHardwareTargetDialog(
      context,
      targetId,
      deviceLabel: selectedDeviceLabels[targetId],
      deviceData: selectedDeviceData[targetId],
      onManageHardwareTarget: onManageHardwareTarget,
    );
  }
}
