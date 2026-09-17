import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:neuro_toolkit/features/neurobench/models/result.dart';
import 'package:neuro_toolkit/features/neurobench/models/workbench_tab.dart';
import 'package:neuro_toolkit/features/neurobench/models/workspace_route_state.dart';
import 'package:neuro_toolkit/features/neurobench/providers/benchmarks_provider.dart';

class BaselineSelector extends ConsumerWidget {
  const BaselineSelector({super.key, required this.tab});

  final NeurobenchWorkbenchTab tab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeBenchmarkId = ref.watch(activeBenchmarkIdProvider);
    final baselinesAsync = ref.watch(baselinesProvider);
    final selectedBaselineId = ref.watch(selectedBaselineIdProvider);
    final selectedResultId = ref.watch(selectedResultIdProvider);
    final activeJobId = ref.watch(activeJobIdProvider);

    return baselinesAsync.when(
      data: (baselines) {
        final filtered = activeBenchmarkId == null
            ? <BenchmarkResult>[]
            : baselines
                .where(
                  (baseline) => baseline.benchmarkId == activeBenchmarkId,
                )
                .toList(growable: false);
        if (filtered.isEmpty) {
          return const SizedBox.shrink();
        }

        BenchmarkResult? selectedBaseline;
        for (final baseline in filtered) {
          if (baseline.id == selectedBaselineId) {
            selectedBaseline = baseline;
            break;
          }
        }

        return DropdownButtonFormField<BenchmarkResult>(
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Baseline',
            border: OutlineInputBorder(),
          ),
          hint: const Text('Select Baseline'),
          initialValue: selectedBaseline,
          onChanged: (value) {
            context.go(
              NeurobenchRouteState(
                tab: tab,
                benchmarkId: activeBenchmarkId,
                baselineId: value?.id,
                resultId: selectedResultId,
                jobId: activeJobId,
              ).location,
            );
          },
          items: filtered.map<DropdownMenuItem<BenchmarkResult>>((baseline) {
            final id = baseline.id;
            final displayId = id.length > 8 ? id.substring(0, 8) : id;
            return DropdownMenuItem<BenchmarkResult>(
              value: baseline,
              child: Text(displayId),
            );
          }).toList(growable: false),
        );
      },
      loading: () => const CircularProgressIndicator(),
      error: (_, _) => const Text('Error loading baselines'),
    );
  }
}
