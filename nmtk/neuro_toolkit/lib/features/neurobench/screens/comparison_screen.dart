import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:neuro_toolkit/features/neurobench/widgets/metric_diff_table.dart';
import 'package:neuro_toolkit/features/neurobench/providers/benchmarks_provider.dart';

class ComparisonScreen extends ConsumerWidget {
  const ComparisonScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(activeBenchmarkProvider);

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
        title: const Text('Benchmark Comparison'),
      ),
      body: active == null
          ? const Center(
              child: Text('Select a benchmark on the main screen first'),
            )
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          'Comparing Results for: ${active.name}',
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                      ),
                      _ExportActions(activeId: active.id),
                    ],
                  ),
                  const SizedBox(height: 24),
                  const Expanded(
                    child: SingleChildScrollView(child: MetricDiffTable()),
                  ),
                ],
              ),
            ),
    );
  }
}

class _ExportActions extends ConsumerWidget {
  final String activeId;

  const _ExportActions({required this.activeId});

  Future<void> _handleExport(
    BuildContext context,
    WidgetRef ref,
    String format,
  ) async {
    final baseline = ref.read(activeBaselineProvider);
    final results = await ref.read(activeBenchmarkResultsProvider.future);

    if (baseline == null || results.isEmpty) return;

    final latestResult = results.last;
    final apiClient = ref.read(apiClientProvider);

    try {
      final String content = await apiClient.exportDiff(
        baseline.id,
        latestResult.id,
        format: format,
      );

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          NmtkSnackBars.success(
            context,
            'Export received (${content.length} bytes) — '
            'file saving is not yet wired on this platform.',
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(NmtkSnackBars.error(context, 'Export failed: $e'));
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
        const SizedBox(width: 8),
        ZetaButton.outline(
          onPressed: () => _handleExport(context, ref, 'json'),
          leadingIcon: Icons.code, // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
          label: 'Export JSON',
        ),
      ],
    );
  }
}
