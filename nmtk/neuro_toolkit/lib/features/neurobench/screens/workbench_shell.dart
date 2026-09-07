import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

import 'package:neuro_toolkit/features/neurobench/app.dart';
import 'package:neuro_toolkit/features/neurobench/models/benchmark.dart';
import 'package:neuro_toolkit/features/neurobench/models/benchmark_job.dart';
import 'package:neuro_toolkit/features/neurobench/models/result.dart';
import 'package:neuro_toolkit/features/neurobench/models/workbench_tab.dart';
import 'package:neuro_toolkit/features/neurobench/models/workspace_route_state.dart';
import 'package:neuro_toolkit/features/neurobench/providers/benchmarks_provider.dart';
import 'package:neuro_toolkit/features/neurobench/providers/dismissed_job_provider.dart';
import 'package:neuro_toolkit/features/neurobench/providers/execution_provider.dart';
import 'package:neuro_toolkit/features/neurobench/widgets/active_jobs_bar.dart';
import 'package:neuro_toolkit/features/neurobench/widgets/benchmark_catalog.dart';
import 'package:neuro_toolkit/features/neurobench/widgets/benchmark_workbench_tabs.dart';
import 'package:neuro_toolkit/features/neurobench/widgets/neurobench_mobile_wizard.dart';

class WorkbenchShellScreen extends ConsumerStatefulWidget {
  const WorkbenchShellScreen({super.key, required this.routeState});

  final NeurobenchRouteState routeState;

  @override
  ConsumerState<WorkbenchShellScreen> createState() =>
      _WorkbenchShellScreenState();
}

class _WorkbenchShellScreenState extends ConsumerState<WorkbenchShellScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _applyRouteState();
      }
    });
  }

  @override
  void didUpdateWidget(covariant WorkbenchShellScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.routeState.location != widget.routeState.location) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _applyRouteState();
        }
      });
    }
  }

  void _applyRouteState() {
    ref
        .read(activeBenchmarkIdProvider.notifier)
        .set(widget.routeState.benchmarkId);
    ref
        .read(selectedBaselineIdProvider.notifier)
        .set(widget.routeState.baselineId);
    ref.read(selectedResultIdProvider.notifier).set(widget.routeState.resultId);
    ref.read(activeJobIdProvider.notifier).set(widget.routeState.jobId);
  }

  NeurobenchRouteState _currentRouteState({
    required String? benchmarkId,
    required String? baselineId,
    required String? resultId,
    required String? jobId,
    NeurobenchWorkbenchTab? tab,
  }) {
    return NeurobenchRouteState(
      tab: tab ?? widget.routeState.tab,
      benchmarkId: benchmarkId,
      baselineId: baselineId,
      resultId: resultId,
      jobId: jobId,
    );
  }

  void _onTabChanged(NeurobenchWorkbenchTab tab) {
    final activeBenchmark = ref.read(activeBenchmarkProvider);
    final baseline = ref.read(activeBaselineProvider);
    final comparisonResult = ref.read(activeComparisonResultProvider);
    final executionState = ref.read(benchmarkExecutionProvider);

    final nextRoute = _currentRouteState(
      tab: tab,
      benchmarkId: activeBenchmark?.id,
      baselineId: baseline?.id,
      resultId: comparisonResult?.id,
      jobId: executionState.activeJob?.id,
    );
    _goToRouteIfNeeded(nextRoute);
  }

  void _goToRouteIfNeeded(NeurobenchRouteState nextRoute) {
    final router = GoRouter.maybeOf(context);
    if (router == null) {
      return;
    }
    final currentRoute = GoRouterState.of(context).uri.toString();
    if (nextRoute.location != currentRoute) {
      context.go(nextRoute.location);
    }
  }

  void _goToConfigureTab() {
    _onTabChanged(NeurobenchWorkbenchTab.configure);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<BenchmarkExecutionState>(benchmarkExecutionProvider, (
      previous,
      next,
    ) {
      final previousJob = previous?.activeJob;
      final nextJob = next.activeJob;
      final currentBenchmark = ref.read(activeBenchmarkProvider);
      final currentBaseline = ref.read(activeBaselineProvider);
      final currentComparisonResult = ref.read(activeComparisonResultProvider);

      if (previousJob?.id != nextJob?.id && nextJob != null) {
        ref.read(dismissedActiveJobBarIdProvider.notifier).set(null);
      }

      if (previousJob?.id != nextJob?.id ||
          previousJob?.resultId != nextJob?.resultId) {
        _goToRouteIfNeeded(
          _currentRouteState(
            benchmarkId: currentBenchmark?.id,
            baselineId: currentBaseline?.id,
            resultId: nextJob?.resultId ?? currentComparisonResult?.id,
            jobId: nextJob?.id,
          ),
        );
      }

      if (previousJob?.status != nextJob?.status &&
          nextJob?.status == BenchmarkJobStatus.completed) {
        ScaffoldMessenger.of(context).showSnackBar(
          NmtkSnackBars.success(
            context,
            'Benchmark job ${nextJob?.id} completed.',
          ),
        );
        _goToRouteIfNeeded(
          _currentRouteState(
            tab: NeurobenchWorkbenchTab.results,
            benchmarkId: currentBenchmark?.id,
            baselineId: currentBaseline?.id,
            resultId: nextJob?.resultId ?? currentComparisonResult?.id,
            jobId: nextJob?.id,
          ),
        );
      }

      if (previousJob?.status != nextJob?.status &&
          nextJob?.status == BenchmarkJobStatus.failed) {
        ScaffoldMessenger.of(context).showSnackBar(
          NmtkSnackBars.error(
            context,
            nextJob?.error ?? 'Benchmark job failed.',
          ),
        );
      }

      if (next.noticeMessage != null &&
          next.noticeMessage != previous?.noticeMessage) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(NmtkSnackBars.success(context, next.noticeMessage!));
        ref.read(benchmarkExecutionProvider.notifier).clearMessages();
      }

      if (next.errorMessage != null &&
          next.errorMessage != previous?.errorMessage) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(NmtkSnackBars.error(context, next.errorMessage!));
      }
    });

    final showShellChrome = ref.watch(showShellChromeProvider);
    final activeBenchmark = ref.watch(activeBenchmarkProvider);
    final executionState = ref.watch(benchmarkExecutionProvider);
    final resultsAsync = ref.watch(activeBenchmarkResultsProvider);
    ref.watch(activeBaselineProvider);
    ref.watch(activeComparisonResultProvider);
    final readiness = _resolveReadiness(
      activeBenchmark: activeBenchmark,
      resultsAsync: resultsAsync,
      executionState: executionState,
    );
    final theme = Theme.of(context);
    final tokens = NmtkShellTokens.of(context);
    final currentTab = widget.routeState.tab;

    final body = Padding(
      padding: EdgeInsets.all(tokens.sectionGap),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Phone viewports (below the compact breakpoint) use the stacked
          // catalog → workbench wizard; tablets and desktops get the
          // catalog-panel side-by-side layout.
          final useStackedLayout =
              constraints.maxWidth < NmtkShellTokens.compactBreakpoint;

          if (useStackedLayout) {
            return NeurobenchMobileWizard(
              activeBenchmark: activeBenchmark,
              initialTab: currentTab,
              onTabChanged: _onTabChanged,
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: tokens.utilityPanelWidth,
                child: BenchmarkCatalog(preserveTab: currentTab),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: activeBenchmark == null
                    ? const NmtkEmptyState(
                        title: 'Select a benchmark',
                        message:
                            'Choose a benchmark from the catalog to configure runs, review history, compare targets, and build reports.',
                        icon: Icons
                            .science_outlined, // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
                      )
                    : BenchmarkWorkbenchTabs(
                        key: ValueKey(activeBenchmark.id),
                        benchmark: activeBenchmark,
                        initialTab: currentTab,
                        onTabChanged: _onTabChanged,
                      ),
              ),
            ],
          );
        },
      ),
    );

    return Scaffold(
      backgroundColor: theme.colorScheme.surfaceContainerLowest,
      appBar: showShellChrome
          ? NmtkTopAppBar(
              mode: NmtkShellMode.command,
              title: const Text('NeuroBench'),
              destinations: const [
                NavigationDestinationData(
                  label: 'NeuroBench',
                  icon: Icons
                      .science_outlined, // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
                ),
              ],
              selectedIndex: 0,
              onDestinationSelected: (_) {},
              statusBadges: [
                NmtkShellStatusBadge(
                  status: NmtkShellStatusSpec.fromReadinessState(
                    readiness,
                    detailText: _readinessDetail(
                      activeBenchmark: activeBenchmark,
                      resultsAsync: resultsAsync,
                    ),
                  ),
                ),
              ],
              actions: [
                if (activeBenchmark != null)
                  NmtkTopAppBarAction(
                    icon: executionState.hasActiveBackgroundJob
                        ? ZetaIcons.sync
                        : ZetaIcons.play,
                    tooltip: executionState.hasActiveBackgroundJob
                        ? 'A benchmark job is running'
                        : 'Open Configure & Run',
                    onPressed: _goToConfigureTab,
                    selected: executionState.hasActiveBackgroundJob,
                  ),
              ],
            )
          : null,
      body: showShellChrome
          ? SafeArea(bottom: false, child: body)
          : SafeArea(bottom: false, child: body),
      bottomNavigationBar: const ActiveJobsBar(),
    );
  }

  NmtkShellReadinessState _resolveReadiness({
    required BenchmarkDefinition? activeBenchmark,
    required AsyncValue<List<BenchmarkResult>> resultsAsync,
    required BenchmarkExecutionState executionState,
  }) {
    if (activeBenchmark == null) {
      return NmtkShellReadinessState.opening;
    }

    final activeJob = executionState.activeJob;
    if (activeJob != null && !activeJob.status.isTerminal) {
      return NmtkShellReadinessState.warmingUp;
    }
    if (activeJob?.status == BenchmarkJobStatus.failed) {
      return NmtkShellReadinessState.error;
    }

    return resultsAsync.when(
      data: (results) => results.isEmpty
          ? NmtkShellReadinessState.degraded
          : NmtkShellReadinessState.ready,
      loading: () => NmtkShellReadinessState.warmingUp,
      error: (_, _) => NmtkShellReadinessState.error,
    );
  }

  String _readinessDetail({
    required BenchmarkDefinition? activeBenchmark,
    required AsyncValue<List<BenchmarkResult>> resultsAsync,
  }) {
    if (activeBenchmark == null) {
      return 'Waiting for benchmark selection';
    }

    return resultsAsync.when(
      data: (results) => results.isEmpty
          ? 'Benchmark loaded, but there are no recorded runs yet'
          : 'Latest run and comparison data available',
      loading: () => 'Loading benchmark runs and summary metrics',
      error: (error, _) => 'Unable to load benchmark results: $error',
    );
  }
}
