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
    final tokens = NmtkShellTokens.of(context);
    final theme = Theme.of(context);

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
          ? const SafeArea(
              child: Center(
                child: Text('Select a benchmark on the main screen first'),
              ),
            )
          : SafeArea(
              child: Padding(
                padding: EdgeInsets.all(tokens.sectionGap),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    // Phones stack the heading above the export actions; a
                    // side-by-side row squeezes the heading until both it and
                    // the buttons overflow (CEL-431).
                    final compact =
                        constraints.maxWidth <
                        NmtkShellTokens.compactBreakpoint;
                    final heading = Text(
                      'Comparing Results for: ${active.name}',
                      style: theme.textTheme.headlineSmall,
                    );
                    final actions = _ExportActions(activeId: active.id);

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (compact) ...[
                          heading,
                          SizedBox(height: tokens.sectionGap),
                          actions,
                        ] else
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(child: heading),
                              SizedBox(width: tokens.sectionGap),
                              actions,
                            ],
                          ),
                        SizedBox(height: tokens.sectionGap),
                        const Expanded(
                          child: SingleChildScrollView(
                            child: MetricDiffTable(),
                          ),
                        ),
                      ],
                    );
                  },
                ),
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
        NmtkSnackBars.success(
          context,
          'Export received (${content.length} bytes) — '
          'file saving is not yet wired on this platform.',
        );
      }
    } catch (e) {
      if (context.mounted) {
        NmtkSnackBars.error(context, 'Export failed: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = NmtkShellTokens.of(context);

    // Wrap so the two export buttons stack instead of clipping when the phone
    // viewport is at its 375 px minimum (CEL-431).
    return Wrap(
      spacing: tokens.compactGap,
      runSpacing: tokens.compactGap,
      children: [
        ZetaButton.primary(
          onPressed: () => _handleExport(context, ref, 'csv'),
          leadingIcon: ZetaIcons.download,
          label: 'Export CSV',
        ),
        ZetaButton.outline(
          onPressed: () => _handleExport(context, ref, 'json'),
          leadingIcon: Icons.code, // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
          label: 'Export JSON',
        ),
      ],
    );
  }
}
