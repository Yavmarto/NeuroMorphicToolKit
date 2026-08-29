import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';

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
    final compareSelection = ref.watch(compareSelectionProvider);
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
              rows: sorted.map((result) {
                final selected = compareSelection.contains(result.id);
                final metricValue = result.metrics[primaryMetric];

                return DataRow(
                  selected: selected,
                  cells: [
                    DataCell(
                      Checkbox(
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
                      Text(
                        '${result.wallTimeSeconds.toStringAsFixed(2)} s',
                      ),
                    ),
                    DataCell(
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TextButton(
                            onPressed: () => _loadResult(context, ref, result),
                            child: const Text('Load'),
                          ),
                          TextButton(
                            onPressed: () =>
                                _saveBaseline(context, ref, result),
                            child: const Text('Save'),
                          ),
                          TextButton(
                            onPressed: () => _exportJson(context, result),
                            child: const Text('Export'),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              }).toList(growable: false),
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Text('Error: $err'),
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
