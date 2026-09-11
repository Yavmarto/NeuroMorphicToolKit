import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

import 'package:neuro_toolkit/features/neurocnl/models/simulator.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/simulator_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/simulator_panel.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/deployment/deploy/deploy_target_catalog/support.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/deployment/deploy/simulator_deploy_workspace/support.dart';

class SimulatorTargetsTable extends ConsumerWidget {
  const SimulatorTargetsTable({super.key, required this.backends});

  final List<String> backends;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final textStyles = Zeta.of(context).textStyles;

    Widget headerText(String label) => Text(
      label,
      style: textStyles.bodyMedium.copyWith(fontWeight: FontWeight.w600),
    );

    return SingleChildScrollView(
      key: const Key('simulator-targets-table'),
      scrollDirection: Axis.horizontal,
      // ZETA-MIGRATION-EXEMPT: zeta_flutter has no table/data-grid component
      // (confirmed against the installed package source) — DataTable is the
      // only option for tabular data here.
      child: DataTable(
        headingRowColor: WidgetStatePropertyAll(
          theme.colorScheme.surfaceContainerHighest,
        ),
        dataRowColor: WidgetStatePropertyAll(theme.colorScheme.surface),
        border: TableBorder.all(color: theme.colorScheme.outlineVariant),
        columnSpacing: 24,
        columns: [
          DataColumn(label: headerText('')),
          DataColumn(label: headerText('Target')),
          DataColumn(label: headerText('Results')),
          DataColumn(label: headerText('Settings')),
        ],
        rows: [
          for (final backend in backends)
            _simulatorTargetRow(context, ref, backend),
        ],
      ),
    );
  }

  DataRow _simulatorTargetRow(
    BuildContext context,
    WidgetRef ref,
    String backend,
  ) {
    final target = targetForId(backend);
    final settings = ref.watch(simulatorSettingsProvider(backend));
    final runState = ref.watch(simulatorRunProvider(backend));
    final isOverridden = ref.watch(
      simulatorOverriddenBackendsProvider.select((s) => s.contains(backend)),
    );
    // A completed run is only shown as done (checkmark) while `settings`
    // still matches what it actually ran with — changing the shared card or
    // this row's own override afterwards makes it stale, so it reverts to
    // "needs running" instead of silently claiming a result that no longer
    // reflects the current parameters.
    final lastRunSettings = ref.watch(
      simulatorLastRunSettingsProvider.select((s) => s[backend]),
    );
    final isStale =
        runState is SimulatorRunSuccess && lastRunSettings != settings;
    final textStyles = Zeta.of(context).textStyles;
    final colors = Zeta.of(context).colors;

    final emptyCell = Text(
      '—',
      style: textStyles.bodySmall.copyWith(color: colors.mainSubtle),
    );
    final resultsCell = switch (runState) {
      SimulatorRunSuccess(:final result) => _simulatorResultText(
        context,
        result,
      ),
      SimulatorRunError err => _simulatorErrorText(context, err),
      _ => emptyCell,
    };

    // DataRow.key only feeds Table's internal row-diffing — it never attaches
    // to a widget `find.byKey` can see, so the row also needs a KeyedSubtree
    // around one of its cells for that.
    return DataRow(
      key: ValueKey('simulator-target-row-$backend'),
      cells: [
        DataCell(
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Fixed-size boxes so the play/spinner/check/error swap never
              // changes this cell's width or the row's height.
              SizedBox(
                width: 20,
                height: 20,
                child: switch (runState) {
                  SimulatorRunLoading() => Center(
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: colors.mainDefault,
                      ),
                    ),
                  ),
                  SimulatorRunError err => Tooltip(
                    message: '${formatSimulatorRunError(err)}\n\nTap to retry.',
                    child: ZetaIconButton.negative(
                      key: Key('simulator-target-run-$backend'),
                      size: ZetaWidgetSize.small,
                      icon: ZetaIcons.cancel_outline,
                      semanticLabel:
                          'Run failed: ${formatSimulatorRunError(err)}. Tap to retry.',
                      onPressed: () => runSimulatorBackend(ref, backend),
                    ),
                  ),
                  SimulatorRunSuccess() when !isStale => Tooltip(
                    message: 'Done — tap to run again',
                    child: ZetaIconButton.positive(
                      key: Key('simulator-target-run-$backend'),
                      size: ZetaWidgetSize.small,
                      icon: ZetaIcons.check_circle_outline,
                      semanticLabel: 'Done — tap to run again',
                      onPressed: () => runSimulatorBackend(ref, backend),
                    ),
                  ),
                  _ => Tooltip(
                    message: isStale
                        ? 'Settings changed — tap to run'
                        : 'Run ${target.label}',
                    child: ZetaIconButton.text(
                      key: Key('simulator-target-run-$backend'),
                      size: ZetaWidgetSize.small,
                      icon: ZetaIcons.play,
                      semanticLabel: isStale
                          ? 'Settings changed — tap to run'
                          : 'Run ${target.label}',
                      onPressed: () => runSimulatorBackend(ref, backend),
                    ),
                  ),
                },
              ),
              const SizedBox(width: 4),
              SizedBox(
                width: 20,
                height: 20,
                child: Tooltip(
                  message: '${target.label} settings',
                  child: ZetaIconButton.text(
                    key: Key('simulator-target-settings-$backend'),
                    size: ZetaWidgetSize.small,
                    icon: ZetaIcons.settings,
                    semanticLabel: '${target.label} settings',
                    onPressed: () =>
                        showSimulatorTargetSettings(context, backend),
                  ),
                ),
              ),
            ],
          ),
        ),
        DataCell(
          KeyedSubtree(
            key: Key('simulator-target-row-$backend'),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(target.icon, size: 18, color: colors.mainDefault),
                const SizedBox(width: 8),
                Text(target.label, style: textStyles.bodyMedium),
                if (isOverridden) ...[
                  const SizedBox(width: 6),
                  Tooltip(
                    message:
                        'Has its own settings, separate from the shared card above',
                    child: Icon(
                      ZetaIcons.pin,
                      size: 14,
                      color: colors.mainSubtle,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        DataCell(resultsCell),
        DataCell(
          Text(
            'T${settings.timesteps} · S${settings.seed} · '
            'FR ${settings.firingRate.toStringAsFixed(2)} · '
            'dt ${settings.dtMs.toStringAsFixed(1)}ms',
            style: textStyles.bodySmall.copyWith(color: colors.mainSubtle),
          ),
        ),
      ],
    );
  }

  /// Duration + total-spikes recap for the Results column — the same
  /// numbers the Deploy step's per-target status card
  /// (`_DeployRunStatusPane._buildDone` in `simulator_panel.dart`) showed
  /// before this table replaced it, minus its "Ran at" timestamp: that's
  /// tracked as local widget state (`_completedAt` in
  /// `_SimulatorExecutionPaneState`) rather than anything carried on
  /// [SimulatorRunResult] itself, so it isn't reproducible here without
  /// duplicating that state-tracking.
  Widget _simulatorErrorText(BuildContext context, SimulatorRunError error) {
    final textStyles = Zeta.of(context).textStyles;
    final colors = Zeta.of(context).colors;
    final message = formatSimulatorRunError(error);
    return Tooltip(
      message: message,
      child: Text(
        message,
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
        style: textStyles.bodySmall.copyWith(color: colors.mainNegative),
      ),
    );
  }

  Widget _simulatorResultText(BuildContext context, SimulatorRunResult result) {
    final textStyles = Zeta.of(context).textStyles;
    final colors = Zeta.of(context).colors;
    final totalSpikes = result.spikes.values.fold<int>(
      0,
      (sum, population) =>
          sum + population.values.fold<int>(0, (s, ts) => s + ts.length),
    );
    return Text(
      '${result.durationSeconds.toStringAsFixed(3)}s · $totalSpikes spikes',
      style: textStyles.bodySmall.copyWith(color: colors.mainSubtle),
    );
  }
}
