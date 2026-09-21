import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:neuro_toolkit/features/neurobench/models/benchmark.dart';
import 'package:neuro_toolkit/features/neurobench/models/workbench_tab.dart';
import 'package:neuro_toolkit/features/neurobench/widgets/benchmark_header_card.dart';
import 'package:neuro_toolkit/features/neurobench/widgets/benchmark_results_table.dart';
import 'package:neuro_toolkit/features/neurobench/widgets/benchmark_run_form.dart';
import 'package:neuro_toolkit/features/neurobench/widgets/comparison_workspace.dart';
import 'package:neuro_toolkit/features/neurobench/widgets/perturbation_curve_chart.dart';
import 'package:neuro_toolkit/features/neurobench/widgets/report_builder.dart';
import 'package:neuro_toolkit/features/neurobench/widgets/results_summary_card.dart';
import 'package:neuro_toolkit/features/neurobench/widgets/robustness_curve_chart.dart';
import 'package:neuro_toolkit/features/neurobench/widgets/target_comparison_grid.dart';

class BenchmarkWorkbenchTabs extends ConsumerStatefulWidget {
  const BenchmarkWorkbenchTabs({
    super.key,
    required this.benchmark,
    required this.initialTab,
    required this.onTabChanged,
  });

  final BenchmarkDefinition benchmark;
  final NeurobenchWorkbenchTab initialTab;
  final ValueChanged<NeurobenchWorkbenchTab> onTabChanged;

  @override
  ConsumerState<BenchmarkWorkbenchTabs> createState() =>
      _BenchmarkWorkbenchTabsState();
}

class _BenchmarkWorkbenchTabsState extends ConsumerState<BenchmarkWorkbenchTabs>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  static const _tabs = NeurobenchWorkbenchTab.values;

  @override
  void initState() {
    super.initState();
    final index = _tabs.indexOf(widget.initialTab).clamp(0, _tabs.length - 1);
    _tabController = TabController(
      length: _tabs.length,
      vsync: this,
      initialIndex: index,
    );
    _tabController.addListener(_onTabChanged);
  }

  @override
  void didUpdateWidget(covariant BenchmarkWorkbenchTabs oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialTab != widget.initialTab) {
      final index = _tabs.indexOf(widget.initialTab).clamp(0, _tabs.length - 1);
      if (_tabController.index != index) {
        _tabController.index = index;
      }
    }
  }

  void _onTabChanged() {
    if (_tabController.indexIsChanging) {
      return;
    }
    widget.onTabChanged(_tabs[_tabController.index]);
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  void navigateToTab(NeurobenchWorkbenchTab tab) {
    final index = _tabs.indexOf(tab);
    if (index >= 0 && _tabController.index != index) {
      _tabController.animateTo(index);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const BenchmarkHeaderCard(),
        const SizedBox(height: 12),
        TabBar(
          isScrollable: true,
          controller: _tabController,
          tabs: _tabs
              .map(
                (tab) => Tab(
                  icon: Icon(
                    tab.icon,
                    size: 18,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  text: tab.label,
                ),
              )
              .toList(growable: false),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              SingleChildScrollView(
                child: BenchmarkRunForm(benchmark: widget.benchmark),
              ),
              SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const ResultsSummaryCard(),
                    const SizedBox(height: 16),
                    BenchmarkResultsTable(onNavigateTab: navigateToTab),
                  ],
                ),
              ),
              const SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TargetComparisonGrid(),
                    SizedBox(height: 16),
                    ComparisonWorkspace(),
                  ],
                ),
              ),
              const SingleChildScrollView(
                child: ReportBuilder(tab: NeurobenchWorkbenchTab.reports),
              ),
              const SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    RobustnessCurveChart(),
                    SizedBox(height: 16),
                    PerturbationCurveChart(),
                    SizedBox(height: 16),
                    TargetComparisonGrid(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
