import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

import 'package:neuro_toolkit/features/neurobench/models/result.dart';
import 'package:neuro_toolkit/features/neurobench/models/workbench_tab.dart';
import 'package:neuro_toolkit/features/neurobench/models/workspace_route_state.dart';
import 'package:neuro_toolkit/features/neurobench/providers/benchmarks_provider.dart';
import 'package:neuro_toolkit/features/neurobench/providers/compare_selection_provider.dart';
import 'package:neuro_toolkit/features/neurobench/widgets/baseline_selector.dart';
import 'package:neuro_toolkit/features/neurobench/widgets/metric_diff_table.dart';

class ComparisonWorkspace extends ConsumerWidget {
  const ComparisonWorkspace({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeBenchmark = ref.watch(activeBenchmarkProvider);
    final activeBaseline = ref.watch(activeBaselineProvider);
    final currentResult = ref.watch(activeComparisonResultProvider);
    final compareSelection = ref.watch(compareSelectionProvider);
    final hasSelection = activeBaseline != null && currentResult != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (compareSelection.isNotEmpty)
          NmtkSection(
            title: 'From Results tab',
            subtitle:
                'Runs selected in Results & History. Apply them as baseline and current.',
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ...compareSelection.map(
                  (id) => Chip(
                    label: Text(
                      id.length > 12 ? '${id.substring(0, 12)}…' : id,
                    ),
                  ),
                ),
                ZetaButton.outline(
                  onPressed: compareSelection.length < 2
                      ? null
                      : () => _applyCompareSelection(
                            context,
                            ref,
                            compareSelection,
                          ),
                  leadingIcon: Icons
                      .compare_arrows_outlined, // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
                  label: 'Apply selection',
                ),
              ],
            ),
          ),
        if (compareSelection.isNotEmpty) const SizedBox(height: 16),
        NmtkSection(
          title: 'Platform Comparison',
          subtitle: activeBenchmark != null
              ? 'Diff ${activeBenchmark.name} runs — primary metric: ${activeBenchmark.scoring.primaryMetric}'
              : 'Select a benchmark from the catalog first.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: BaselineSelector(
                      tab: NeurobenchWorkbenchTab.compare,
                    ),
                  ),
                  SizedBox(width: 16),
                  Expanded(child: ComparisonResultSelector()),
                ],
              ),
              if (hasSelection) ...[
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: SelectionBadge(
                        label: 'Baseline',
                        value: activeBaseline.id,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Icon(
                      Icons.compare_arrows_outlined,
                      size: 20,
                    ), // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
                    const SizedBox(width: 12),
                    Expanded(
                      child: SelectionBadge(
                        label: 'Current run',
                        value: currentResult.id,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const ComparisonExportActions(),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (!hasSelection)
          NmtkSection(
            title: 'No comparison selected',
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Column(
                children: [
                  Icon(
                    Icons
                        .compare_arrows_outlined, // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
                    size: 40,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Select a baseline and current run, or pick two runs on the Results tab.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
          )
        else
          const MetricDiffTable(),
      ],
    );
  }

  void _applyCompareSelection(
    BuildContext context,
    WidgetRef ref,
    Set<String> selection,
  ) {
    final ids = selection.toList(growable: false);
    if (ids.length < 2) {
      return;
    }
    final benchmarkId = ref.read(activeBenchmarkIdProvider);
    final activeJobId = ref.read(activeJobIdProvider);
    final route = NeurobenchRouteState(
      tab: NeurobenchWorkbenchTab.compare,
      benchmarkId: benchmarkId,
      baselineId: ids[0],
      resultId: ids[1],
      jobId: activeJobId,
    );
    context.go(route.location);
  }
}

class ComparisonResultSelector extends ConsumerWidget {
  const ComparisonResultSelector({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeBenchmarkId = ref.watch(activeBenchmarkIdProvider);
    final selectedBaselineId = ref.watch(selectedBaselineIdProvider);
    final selectedResultId = ref.watch(selectedResultIdProvider);
    final activeJobId = ref.watch(activeJobIdProvider);
    final resultsAsync = ref.watch(activeBenchmarkResultsProvider);

    return resultsAsync.when(
      data: (results) {
        if (results.isEmpty) {
          return InputDecorator(
            decoration: const InputDecoration(
              labelText: 'Current Run',
              border: OutlineInputBorder(),
            ),
            child: Text(
              'No runs yet — run a benchmark from Configure & Run first.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          );
        }

        BenchmarkResult? selectedResult;
        for (final result in results) {
          if (result.id == selectedResultId) {
            selectedResult = result;
            break;
          }
        }

        return DropdownButtonFormField<BenchmarkResult>(
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Current Run',
            border: OutlineInputBorder(),
          ),
          hint: const Text('Select Current Run'),
          initialValue: selectedResult,
          onChanged: (value) {
            context.go(
              NeurobenchRouteState(
                tab: NeurobenchWorkbenchTab.compare,
                benchmarkId: activeBenchmarkId,
                baselineId: selectedBaselineId,
                resultId: value?.id,
                jobId: activeJobId,
              ).location,
            );
          },
          items: results.map((result) {
            final id =
                result.id.length > 8 ? result.id.substring(0, 8) : result.id;
            return DropdownMenuItem<BenchmarkResult>(
              value: result,
              child: Text('$id • ${result.timestamp}'),
            );
          }).toList(growable: false),
        );
      },
      loading: () => const LinearProgressIndicator(),
      error: (error, _) => Text('Unable to load results: $error'),
    );
  }
}

class ComparisonExportActions extends ConsumerWidget {
  const ComparisonExportActions({super.key});

  Future<void> _handleExport(
    BuildContext context,
    WidgetRef ref,
    String format,
  ) async {
    final baseline = ref.read(activeBaselineProvider);
    final currentResult = ref.read(activeComparisonResultProvider);

    if (baseline == null || currentResult == null) {
      return;
    }

    final apiClient = ref.read(apiClientProvider);

    try {
      final content = await apiClient.exportDiff(
        baseline.id,
        currentResult.id,
        format: format,
      );

      if (context.mounted) {
        NmtkSnackBars.success(
            context,
            'Export received (${content.length} bytes) — file saving is not yet wired on this platform.',
          );
      }
    } catch (error) {
      if (context.mounted) {
        NmtkSnackBars.error(context, 'Export failed: $error');
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      children: [
        ZetaButton.primary(
          onPressed: () => _handleExport(context, ref, 'csv'),
          leadingIcon: ZetaIcons.download,
          label: 'Export CSV',
        ),
        const SizedBox(width: 12),
        ZetaButton.outline(
          onPressed: () => _handleExport(context, ref, 'json'),
          leadingIcon:
              Icons.code_outlined, // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
          label: 'Export JSON',
        ),
      ],
    );
  }
}

class SelectionBadge extends StatelessWidget {
  const SelectionBadge({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(NmtkShellTokens.of(context).radiusSm),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
