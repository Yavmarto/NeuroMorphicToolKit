import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

import 'package:neuro_toolkit/features/neurobench/models/result.dart';
import 'package:neuro_toolkit/features/neurobench/models/workbench_tab.dart';
import 'package:neuro_toolkit/features/neurobench/models/workspace_route_state.dart';
import 'package:neuro_toolkit/features/neurobench/providers/benchmarks_provider.dart';
import 'package:neuro_toolkit/features/neurobench/providers/compare_selection_provider.dart';

typedef OnNavigateTab = void Function(NeurobenchWorkbenchTab tab);

class BenchmarkResultsTable extends ConsumerWidget {
  const BenchmarkResultsTable({super.key, required this.onNavigateTab});

  final OnNavigateTab onNavigateTab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeBenchmark = ref.watch(activeBenchmarkProvider);
    final resultsAsync = ref.watch(activeBenchmarkResultsProvider);
    final primaryMetric = activeBenchmark?.scoring.primaryMetric ?? 'metric';

    return NmtkSection(
      title: 'Run History',
      subtitle:
          'All runs for this benchmark. Save as baseline, load for comparison, or export JSON.',
      child: resultsAsync.when(
        data: (results) {
          if (results.isEmpty) {
            return const Text('No past runs for this benchmark.');
          }

          final sorted = List<BenchmarkResult>.from(results)
            ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

          return NmtkAdaptiveLayout(
            breakpoint: NmtkShellTokens.compactBreakpoint,
            desktopBuilder: (_) =>
                _buildDataTable(context, ref, sorted, primaryMetric),
            mobileBuilder: (_) =>
                _buildCardList(context, ref, sorted, primaryMetric),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Text('Error: $err'),
      ),
    );
  }

  Widget _buildDataTable(
    BuildContext context,
    WidgetRef ref,
    List<BenchmarkResult> sorted,
    String primaryMetric,
  ) {
    final compareSelection = ref.watch(compareSelectionProvider);

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: [
          const DataColumn(label: Text('Compare')),
          const DataColumn(label: Text('Run ID')),
          const DataColumn(label: Text('Timestamp')),
          const DataColumn(label: Text('Target')),
          DataColumn(label: Text(primaryMetric)),
          const DataColumn(label: Text('Wall time')),
          const DataColumn(label: Text('Actions')),
        ],
        rows: sorted
            .map((result) {
              final selected = compareSelection.contains(result.id);
              final metricValue = result.metrics[primaryMetric];

              return DataRow(
                selected: selected,
                cells: [
                  DataCell(
                    ZetaCheckbox(
                      value: selected,
                      onChanged: (_) => ref
                          .read(compareSelectionProvider.notifier)
                          .toggle(result.id),
                    ),
                  ),
                  DataCell(Text(_shortId(result.id))),
                  DataCell(Text(result.timestamp)),
                  DataCell(Text(result.targetId ?? '—')),
                  DataCell(Text(metricValue?.toStringAsFixed(4) ?? '—')),
                  DataCell(
                    Text('${result.wallTimeSeconds.toStringAsFixed(2)} s'),
                  ),
                  DataCell(
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ZetaButton.text(
                          onPressed: () => _loadResult(context, ref, result),
                          label: 'Load',
                          size: ZetaWidgetSize.small,
                        ),
                        ZetaButton.text(
                          onPressed: () => _saveBaseline(context, ref, result),
                          label: 'Save',
                          size: ZetaWidgetSize.small,
                        ),
                        ZetaButton.text(
                          onPressed: () => _exportJson(context, result),
                          label: 'Export',
                          size: ZetaWidgetSize.small,
                        ),
                      ],
                    ),
                  ),
                ],
              );
            })
            .toList(growable: false),
      ),
    );
  }

  /// Card-per-row rendering for compact viewports (CEL-77): every run gets
  /// its own surface card instead of a wide multi-column row.
  Widget _buildCardList(
    BuildContext context,
    WidgetRef ref,
    List<BenchmarkResult> sorted,
    String primaryMetric,
  ) {
    final compareSelection = ref.watch(compareSelectionProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final result in sorted)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: NmtkSurfaceCard(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        ZetaCheckbox(
                          value: compareSelection.contains(result.id),
                          onChanged: (_) => ref
                              .read(compareSelectionProvider.notifier)
                              .toggle(result.id),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _shortId(result.id),
                            style: Zeta.of(context).textStyles.bodyMedium
                                .copyWith(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _kvRow(context, 'Timestamp', result.timestamp),
                    _kvRow(context, 'Target', result.targetId ?? '—'),
                    _kvRow(
                      context,
                      primaryMetric,
                      result.metrics[primaryMetric]?.toStringAsFixed(4) ?? '—',
                    ),
                    _kvRow(
                      context,
                      'Wall time',
                      '${result.wallTimeSeconds.toStringAsFixed(2)} s',
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ZetaButton.text(
                          onPressed: () => _loadResult(context, ref, result),
                          label: 'Load',
                          size: ZetaWidgetSize.small,
                        ),
                        ZetaButton.text(
                          onPressed: () => _saveBaseline(context, ref, result),
                          label: 'Save',
                          size: ZetaWidgetSize.small,
                        ),
                        ZetaButton.text(
                          onPressed: () => _exportJson(context, result),
                          label: 'Export',
                          size: ZetaWidgetSize.small,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _kvRow(BuildContext context, String label, String value) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: Zeta.of(context).textStyles.bodySmall.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
              style: Zeta.of(
                context,
              ).textStyles.bodySmall.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  String _shortId(String id) => id.length > 10 ? '${id.substring(0, 10)}…' : id;

  void _loadResult(
    BuildContext context,
    WidgetRef ref,
    BenchmarkResult result,
  ) {
    final benchmarkId = ref.read(activeBenchmarkIdProvider);
    final baselineId = ref.read(selectedBaselineIdProvider);
    final jobId = ref.read(activeJobIdProvider);

    ref.read(selectedResultIdProvider.notifier).set(result.id);

    context.go(
      NeurobenchRouteState(
        tab: NeurobenchWorkbenchTab.compare,
        benchmarkId: benchmarkId,
        baselineId: baselineId,
        resultId: result.id,
        jobId: jobId,
      ).location,
    );
    onNavigateTab(NeurobenchWorkbenchTab.compare);
  }

  Future<void> _saveBaseline(
    BuildContext context,
    WidgetRef ref,
    BenchmarkResult result,
  ) async {
    try {
      await ref.read(apiClientProvider).saveBaseline(result);
      ref.invalidate(baselinesProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          NmtkSnackBars.success(context, 'Saved ${result.id} as baseline.'),
        );
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(NmtkSnackBars.error(context, 'Save failed: $error'));
      }
    }
  }

  void _exportJson(BuildContext context, BenchmarkResult result) {
    final payload = const JsonEncoder.withIndent('  ').convert(result.toJson());
    Clipboard.setData(ClipboardData(text: payload));
    ScaffoldMessenger.of(context).showSnackBar(
      NmtkSnackBars.success(
        context,
        'Result JSON copied to clipboard (${payload.length} bytes).',
      ),
    );
  }
}
