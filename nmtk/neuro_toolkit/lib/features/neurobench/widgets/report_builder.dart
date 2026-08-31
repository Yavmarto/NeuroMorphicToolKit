import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

import 'package:neuro_toolkit/features/neurobench/models/workbench_tab.dart';
import 'package:neuro_toolkit/features/neurobench/models/workspace_route_state.dart';
import 'package:neuro_toolkit/features/neurobench/providers/benchmarks_provider.dart';
import 'package:neuro_toolkit/features/neurobench/providers/results_provider.dart';

/// Form widget for configuring and generating benchmark reports.
class ReportBuilder extends ConsumerStatefulWidget {
  const ReportBuilder({super.key, this.tab = NeurobenchWorkbenchTab.reports});

  final NeurobenchWorkbenchTab tab;

  @override
  ConsumerState<ReportBuilder> createState() => _ReportBuilderState();
}

class _ReportBuilderState extends ConsumerState<ReportBuilder> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  bool _includeComparison = true;
  bool _includeRobustness = true;
  bool _includeHistory = true;

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final benchmarksAsync = ref.watch(benchmarksProvider);
    final activeBenchmark = ref.watch(activeBenchmarkProvider);
    final activeBaseline = ref.watch(activeBaselineProvider);
    final selectedResult = ref.watch(activeComparisonResultProvider);
    final activeJobId = ref.watch(activeJobIdProvider);
    final latestResult = ref.watch(latestResultProvider);

    return NmtkSection(
      title: 'Report Workbench',
      subtitle:
          'Build report exports from the current benchmark, result, and baseline payloads without altering their schema.',
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _stateChip(
                    context,
                    icon: ZetaIcons.analytics,
                    label: latestResult == null
                        ? 'Preview mode'
                        : 'Result attached',
                  ),
                  _stateChip(
                    context,
                    icon: Icons
                        .compare_arrows_outlined, // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
                    label: activeBaseline == null
                        ? 'No baseline diff'
                        : 'Baseline diff ready',
                  ),
                ],
              ),
              const SizedBox(height: 16),
              NmtkTextInput(
                controller: _titleController,
                label: 'Report Title',
                // ZETA-MIGRATION-TODO: border has no ZetaTextInput equivalent
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter a title';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              benchmarksAsync.when(
                data: (benchmarks) => DropdownButtonFormField<String>(
                  key: ValueKey(activeBenchmark?.id),
                  initialValue: activeBenchmark?.id,
                  decoration: const InputDecoration(
                    labelText: 'Select Benchmark',
                    border: OutlineInputBorder(),
                  ),
                  items: benchmarks.map((b) {
                    return DropdownMenuItem(value: b.id, child: Text(b.name));
                  }).toList(),
                  onChanged: (value) {
                    context.go(
                      NeurobenchRouteState(
                        tab: widget.tab,
                        benchmarkId: value,
                        baselineId: activeBaseline?.id,
                        resultId: selectedResult?.id,
                        jobId: activeJobId,
                      ).location,
                    );
                  },
                  validator: (value) {
                    if (value == null) {
                      return 'Please select a benchmark';
                    }
                    return null;
                  },
                ),
                loading: () => const CircularProgressIndicator(),
                error: (err, stack) => Text('Error loading benchmarks: $err'),
              ),
              const SizedBox(height: 20),
              Text(
                'Included sections',
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              CheckboxListTile(
                value: _includeComparison,
                onChanged: (value) {
                  setState(() {
                    _includeComparison = value ?? false;
                  });
                },
                title: const Text('Comparison and regression diff'),
                subtitle: const Text(
                  'Include baseline comparison when available.',
                ),
                contentPadding: EdgeInsets.zero,
              ),
              CheckboxListTile(
                value: _includeRobustness,
                onChanged: (value) {
                  setState(() {
                    _includeRobustness = value ?? false;
                  });
                },
                title: const Text('Robustness and perturbation sweeps'),
                subtitle: const Text(
                  'Include current sweep views and placeholders.',
                ),
                contentPadding: EdgeInsets.zero,
              ),
              CheckboxListTile(
                value: _includeHistory,
                onChanged: (value) {
                  setState(() {
                    _includeHistory = value ?? false;
                  });
                },
                title: const Text('Run history'),
                subtitle: const Text('Attach recent benchmark executions.'),
                contentPadding: EdgeInsets.zero,
              ),
              const SizedBox(height: 16),
              ZetaButton.primary(
                onPressed: () {
                  if (_formKey.currentState!.validate()) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      NmtkSnackBars.success(
                        context,
                        latestResult == null
                            ? 'Report preview prepared. Run the benchmark to generate a fully populated export.'
                            : 'Generating report from the current result set...',
                      ),
                    );
                  }
                },
                leadingIcon: ZetaIcons.note,
                label: 'Generate Report',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _stateChip(
    BuildContext context, {
    required IconData icon,
    required String label,
  }) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(NmtkShellTokens.of(context).radiusChip),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Text(
            label,
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
