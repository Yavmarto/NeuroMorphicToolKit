import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';

import 'package:neuro_toolkit/features/neurobench/models/workbench_tab.dart';
import 'package:neuro_toolkit/features/neurobench/models/workspace_route_state.dart';
import 'package:neuro_toolkit/features/neurobench/providers/benchmarks_provider.dart';

class BenchmarkCatalog extends ConsumerWidget {
  const BenchmarkCatalog({
    super.key,
    this.preserveTab = NeurobenchWorkbenchTab.configure,
  });

  final NeurobenchWorkbenchTab preserveTab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final benchmarksAsync = ref.watch(benchmarksProvider);
    final activeId = ref.watch(activeBenchmarkIdProvider);
    final selectedBaselineId = ref.watch(selectedBaselineIdProvider);
    final selectedResultId = ref.watch(selectedResultIdProvider);
    final activeJobId = ref.watch(activeJobIdProvider);
    final theme = Theme.of(context);
    final tokens = NmtkShellTokens.of(context);

    return NmtkSurfaceCard(
      expandChild: true,
      child: Padding(
        padding: EdgeInsets.all(tokens.sectionGap),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Benchmark Catalog',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'NeuroBench standard tasks and custom benchmarks.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: benchmarksAsync.when(
                data: (benchmarks) => ListView.builder(
                  itemCount: benchmarks.length,
                  itemBuilder: (context, index) {
                    final benchmark = benchmarks[index];
                    final isSelected = benchmark.id == activeId;

                    return ZetaListItem(
                      rounded: true,
                      leading: Icon(
                        isSelected
                            ? ZetaIcons.check_circle
                            : Icons
                                .science_outlined, // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
                        color: isSelected
                            ? theme.colorScheme.secondary
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                      title: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            benchmark.name,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            benchmark.taskType,
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                      secondaryText: benchmark.description,
                      secondaryTextStyle: theme.textTheme.bodySmall,
                      showDivider: true,
                      onTap: () {
                        context.go(
                          NeurobenchRouteState(
                            tab: preserveTab,
                            benchmarkId: benchmark.id,
                            baselineId: selectedBaselineId,
                            resultId: selectedResultId,
                            jobId: activeJobId,
                          ).location,
                        );
                      },
                    );
                  },
                ),
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (err, stack) => Text('Error: $err'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
