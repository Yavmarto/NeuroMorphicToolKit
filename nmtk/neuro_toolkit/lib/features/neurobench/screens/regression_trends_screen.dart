import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

import 'package:neuro_toolkit/features/neurobench/providers/benchmarks_provider.dart';
import 'package:neuro_toolkit/features/neurobench/models/result.dart';

class RegressionTrendsScreen extends ConsumerWidget {
  final String benchmarkId;

  const RegressionTrendsScreen({super.key, required this.benchmarkId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resultsAsync = ref.watch(benchmarkResultsProvider(benchmarkId));
    final baselinesAsync = ref.watch(baselinesProvider);

    return Scaffold(
      appBar: AppBar(
        // ZETA-MIGRATION-EXEMPT: no Zeta app bar exists; this is the same
        // rationale nmtk_ui_core's own mobile scaffold uses for its
        // hamburger/title bar (see studio_screen.dart).
        leadingWidth: 190,
        leading: ZetaButton.text(
          onPressed: () {
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
              return;
            }
            context.go('/');
          },
          label: 'Back to Workbench',
          leadingIcon: ZetaIcons.arrow_back,
        ),
        title: Text('Trends: $benchmarkId'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Performance Over Time',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 24),
            Expanded(
              child: resultsAsync.when(
                data: (results) {
                  if (results.isEmpty) {
                    // Show baselines as static reference while no run history exists
                    return baselinesAsync.when(
                      data: (baselines) {
                        final filtered = baselines
                            .where((b) => b.benchmarkId == benchmarkId)
                            .toList();
                        if (filtered.isEmpty) {
                          return const Center(
                            child: Text(
                              'No results yet. Run this benchmark to start tracking trends.',
                            ),
                          );
                        }
                        return _BaselineReferenceTable(
                          baselines: filtered,
                          benchmarkId: benchmarkId,
                        );
                      },
                      loading: () =>
                          const Center(child: CircularProgressIndicator()),
                      error: (err, _) => Text('Error: $err'),
                    );
                  }
                  return _TrendsTable(results: results);
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (err, _) => Text('Error loading trends: $err'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shows published baselines as a reference point when there are no run results.
class _BaselineReferenceTable extends StatelessWidget {
  final List<BenchmarkResult> baselines;
  final String benchmarkId;

  const _BaselineReferenceTable({
    required this.baselines,
    required this.benchmarkId,
  });

  @override
  Widget build(BuildContext context) {
    return NmtkSection(
      title: 'NeuroBench v1.0 Reference Results',
      subtitle: 'Run $benchmarkId to start tracking your own trends.',
      child: Column(
        children: [
          for (final b in baselines)
            ListTile(
              dense: true,
              leading: const Icon(
                Icons.science_outlined,
                size: 18,
              ), // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
              title: Text(b.targetId ?? b.id),
              subtitle: Text(b.params['framework']?.toString() ?? ''),
              trailing: b.metrics['accuracy'] != null
                  ? Text(
                      '${((b.metrics['accuracy']!) * 100).toStringAsFixed(1)}%',
                      style: Zeta.of(context).textStyles.bodyMedium.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    )
                  : null,
            ),
        ],
      ),
    );
  }
}

/// Shows a table of benchmark runs over time.
class _TrendsTable extends StatelessWidget {
  final List<BenchmarkResult> results;

  const _TrendsTable({required this.results});

  @override
  Widget build(BuildContext context) {
    final sorted = [...results]
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

    return NmtkSection(
      title: 'Run History',
      subtitle: '${sorted.length} run(s) recorded.',
      child: ListView.separated(
        itemCount: sorted.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final r = sorted[index];
          final acc = r.metrics['accuracy'];
          return ListTile(
            dense: true,
            leading: Text(
              '#${sorted.length - index}',
              style: Theme.of(context).textTheme.labelSmall,
            ),
            title: Text(r.targetId ?? r.id),
            subtitle: Text(r.timestamp.substring(0, 10)),
            trailing: acc != null
                ? Text(
                    '${(acc * 100).toStringAsFixed(1)}%',
                    style: Zeta.of(context).textStyles.bodyMedium.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  )
                : null,
          );
        },
      ),
    );
  }
}
