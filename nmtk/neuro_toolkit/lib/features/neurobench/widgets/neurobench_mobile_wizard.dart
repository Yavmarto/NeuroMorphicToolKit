import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

import 'package:neuro_toolkit/features/neurobench/models/benchmark.dart';
import 'package:neuro_toolkit/features/neurobench/models/benchmark_job.dart';
import 'package:neuro_toolkit/features/neurobench/models/workbench_tab.dart';
import 'package:neuro_toolkit/features/neurobench/providers/execution_provider.dart';
import 'package:neuro_toolkit/features/neurobench/widgets/benchmark_catalog.dart';
import 'package:neuro_toolkit/features/neurobench/widgets/benchmark_workbench_tabs.dart';

/// Narrow-layout flow: pick a benchmark, then use the same five tabs as desktop.
class NeurobenchMobileWizard extends ConsumerStatefulWidget {
  const NeurobenchMobileWizard({
    super.key,
    required this.activeBenchmark,
    required this.initialTab,
    required this.onTabChanged,
  });

  final BenchmarkDefinition? activeBenchmark;
  final NeurobenchWorkbenchTab initialTab;
  final ValueChanged<NeurobenchWorkbenchTab> onTabChanged;

  @override
  ConsumerState<NeurobenchMobileWizard> createState() =>
      _NeurobenchMobileWizardState();
}

class _NeurobenchMobileWizardState
    extends ConsumerState<NeurobenchMobileWizard> {
  bool _showCatalog = true;

  @override
  void didUpdateWidget(covariant NeurobenchMobileWizard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.activeBenchmark == null && widget.activeBenchmark != null) {
      setState(() => _showCatalog = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = NmtkShellTokens.of(context);
    final executionState = ref.watch(benchmarkExecutionProvider);
    final benchmark = widget.activeBenchmark;

    if (benchmark == null || _showCatalog) {
      return Column(
        children: [
          Expanded(child: BenchmarkCatalog(preserveTab: widget.initialTab)),
          if (benchmark != null)
            Padding(
              padding: EdgeInsets.all(tokens.sectionGap),
              child: ZetaButton(
                onPressed: () => setState(() => _showCatalog = false),
                label: 'Open workbench',
                leadingIcon: ZetaIcons.arrow_forward,
              ),
            ),
        ],
      );
    }

    return Column(
      children: [
        Padding(
          padding: EdgeInsets.only(bottom: tokens.sectionGap),
          child: Align(
            alignment: Alignment.centerLeft,
            child: ZetaButton.text(
              onPressed: () => setState(() => _showCatalog = true),
              label: '← Change benchmark',
            ),
          ),
        ),
        Expanded(
          child: BenchmarkWorkbenchTabs(
            key: ValueKey(benchmark.id),
            benchmark: benchmark,
            initialTab:
                executionState.activeJob?.status == BenchmarkJobStatus.completed
                    ? NeurobenchWorkbenchTab.results
                    : widget.initialTab,
            onTabChanged: widget.onTabChanged,
          ),
        ),
      ],
    );
  }
}
