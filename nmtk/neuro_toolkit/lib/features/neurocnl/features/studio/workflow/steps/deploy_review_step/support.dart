library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:neuro_toolkit/features/neurocnl/providers/deploy_results_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/simulator_panel.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/deployment/deployment_feature.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/workflow/steps/results_step/studio_result_visualizer.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/workflow/steps/deploy_review_step/review_compare_mode_notifier.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/workflow/steps/deploy_review_step/review_compare_targets_notifier.dart';

/// Targets the Review step can ever show something for — every simulator plus
/// the hardware targets that produce a run result. Codegen/FPGA-only targets
/// (`brian2`, `sinabs`, `rockpool`, `pynn`, `nengo`, `sc_neurocore_fpga`) are
/// preview/verdict only and never have a Review result, so they're left out of
/// the target dropdown and the compare picker entirely.
const List<String> reviewableTargets = <String>[
  ...kSimulatorDeployBackends,
  'akida',
  'lava',
  'pynq',
];

/// Whether the Review step is currently showing more than one target's
/// results side by side. Plain in-memory UI state — like the results
/// themselves (see `deployResultsAvailableProvider`), it resets on restart.
/// Lives in a provider (not local widget state) because the target dropdown
/// and compare chip render in the top bar (`DeployReviewHeader`) while the
/// results body renders in the step content area — separate widgets in the
/// tree, not parent/child.
final reviewCompareModeProvider =
    NotifierProvider<ReviewCompareModeNotifier, bool>(
      ReviewCompareModeNotifier.new,
    );

/// The targets selected for side-by-side comparison. Only meaningful while
/// [reviewCompareModeProvider] is true.
final reviewCompareTargetsProvider =
    NotifierProvider<ReviewCompareTargetsNotifier, Set<String>>(
      ReviewCompareTargetsNotifier.new,
    );

/// The `deployReview` pipeline step: everything a deploy produced, for whichever
/// target is selected. The Deploy step keeps the configuration and the actions;
/// the charts, metrics and verdicts land here.
///
/// Deploy results are in-memory only, so this step re-locks after a restart —
/// see `deployResultsAvailableProvider`.

/// Dropdown to switch which target's results Review shows. Lists every
/// [reviewableTargets] entry; ones with no result yet are disabled and
/// labelled "(not run yet)", same grey tone `HardwareTargetsTable` uses for
/// its "Not run yet" cell.

/// Toggle + entry point for side-by-side comparison. Tapping it always opens
/// [CompareTargetsDialog] to (re)configure the selection; confirming with 2+
/// targets turns compare mode on, confirming with fewer turns it off.

/// Checkbox picker for [reviewableTargets], used by [DeployReviewCompareChip].
/// Targets with no result yet are shown but disabled, labelled "Not run yet" —
/// same convention as the target dropdown and `HardwareTargetsTable`.

/// Side-by-side layout for [DeployReviewCompareChip]'s selection — one pane
/// per target, laid out in the same bounded-height area the single-target
/// body uses.

/// The page-level provenance statement: did this run touch physical silicon?
///
/// Akida and PYNQ are the two targets that make a hardware claim, and each makes
/// it exactly once — the results view, the visualization panel and the benchmark
/// view all used to restate Akida's, which cost the top third of the page and
/// could contradict itself when the job flag and the result provenance
/// disagreed.

/// Per-target results dispatch, shared by the single-target [DeployReviewBody]
/// and each pane of [DeployReviewComparePane].
Widget deployReviewTargetBody(String target) {
  if (kSimulatorDeployBackends.contains(target)) {
    // The Activity/Report tabs need bounded height, not an intrinsic one.
    return SimulatorResultsPanel(
      key: ValueKey('deploy-review-simulator-$target'),
      backend: target,
    );
  }
  return switch (target) {
    'akida' => SingleChildScrollView(
      child: AkidaResultsView(
        sourceBuilder: (context, view) => StudioResultVisualizer(
          visualizationContext: context,
          controlledView: view,
          showViewSwitch: false,
          applyOverlayInset: false,
        ),
      ),
    ),
    'lava' => const SingleChildScrollView(child: LavaResultsView()),
    'pynq' => const SingleChildScrollView(child: PynqResultsView()),
    _ => const SizedBox.shrink(),
  };
}

/// The Review step's "Publish" action — opens [showPublishResultsDialog] with
/// a short results summary and the same three workspace-preview minimaps
/// used on Setup. Lives here (not Deploy) because publishing is about the
/// finished result, not the run configuration.
