import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

import 'package:neuro_toolkit/features/neurocnl/config/platform_capabilities.dart';
import 'package:neuro_toolkit/features/neurocnl/l10n/app_localizations.dart';
import 'package:neuro_toolkit/features/neurocnl/models/studio_result_visualization.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/canvas/canvas_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/studio_result_session_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/training_mode_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/training_run_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/workspace_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/screens/canvas/canvas_screen.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/studio_overlay_metrics.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/deployment/deployment_feature.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/shared/studio_shared.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/workflow/workflow_feature.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/workflow/steps/run_step/metrics_sidebar.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/workflow/steps/run_step/run_action_bar.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/workflow/steps/run_step/support.dart';

class RunStep extends ConsumerStatefulWidget {
  const RunStep({super.key, required this.view, required this.onViewChanged});

  final StudioResultView view;
  final ValueChanged<StudioResultView> onViewChanged;

  @override
  ConsumerState<RunStep> createState() => _RunStepState();
}

class _RunStepState extends ConsumerState<RunStep> {
  String? _activePlatform;
  // Saved in initState so dispose() can clear without going through ref (unsafe after unmount).
  late TrainingMode _trainingModeNotifier;

  /// The not-applicable and success banners have no backing provider state
  /// for "the user already saw this" — unlike the error banner's
  /// `dismissedErrors` set (which must survive platform-tab switches), these
  /// two only need to disappear until the next run, so local state is enough.
  /// Reset in `_startTraining` so a fresh run re-shows them.
  bool _successDismissed = false;

  StudioResultSessionState get _session =>
      ref.read(studioResultSessionProvider);

  Map<String, TrainingStatus> get _status => <String, TrainingStatus>{
    for (final entry in _session.platforms.entries)
      entry.key: switch (entry.value.outcome) {
        StudioPlatformOutcome.idle ||
        StudioPlatformOutcome.cancelled => TrainingStatus.idle,
        StudioPlatformOutcome.running => TrainingStatus.running,
        StudioPlatformOutcome.complete => TrainingStatus.complete,
        StudioPlatformOutcome.error => TrainingStatus.error,
        StudioPlatformOutcome.notApplicable => TrainingStatus.notApplicable,
      },
  };

  Map<String, List<TrainingEpochEvent>> get _localEpochs =>
      <String, List<TrainingEpochEvent>>{
        for (final entry in _session.platforms.entries)
          entry.key: entry.value.history,
      };

  Map<String, String> get _errorSummaries {
    return <String, String>{
      for (final entry in _session.platforms.entries)
        if (entry.value.outcome == StudioPlatformOutcome.error &&
            !_session.dismissedErrors.contains(entry.key) &&
            entry.value.summary != null)
          entry.key: entry.value.summary!,
    };
  }

  Map<String, String> get _errorDetails {
    return <String, String>{
      for (final entry in _session.platforms.entries)
        if (entry.value.outcome == StudioPlatformOutcome.error &&
            !_session.dismissedErrors.contains(entry.key) &&
            entry.value.detail != null)
          entry.key: entry.value.detail!,
    };
  }

  bool get _isAnyRunning =>
      _status.values.any((s) => s == TrainingStatus.running);

  Map<String, TrainingRunOutcome> get _outcomeMap => {
    for (final entry in _status.entries) entry.key: _toOutcome(entry.value),
  };

  bool get _isAllSucceeded => RunStepLogic.allSucceeded(_outcomeMap);

  bool get _hasRunErrors => _session.hasErrors;

  static TrainingRunOutcome _toOutcome(TrainingStatus status) =>
      switch (status) {
        TrainingStatus.idle => TrainingRunOutcome.idle,
        TrainingStatus.running => TrainingRunOutcome.running,
        TrainingStatus.complete => TrainingRunOutcome.complete,
        TrainingStatus.error => TrainingRunOutcome.error,
        TrainingStatus.notApplicable => TrainingRunOutcome.notApplicable,
      };

  /// The single error banner's text: the one failure when only one platform
  /// failed, otherwise a count with every failing platform named.
  String? get _errorBannerSummary {
    if (_errorSummaries.isEmpty) return null;
    if (_errorSummaries.length == 1) {
      final entry = _errorSummaries.entries.first;
      return '${targetLabel(entry.key)}: ${entry.value}';
    }
    final names = _errorSummaries.keys.map(targetLabel).join(', ');
    return '${_errorSummaries.length} platforms failed: $names';
  }

  String? get _errorBannerDetail {
    if (_errorDetails.isEmpty) return null;
    return _errorDetails.entries
        .map((e) => '── ${targetLabel(e.key)} ──\n${e.value}')
        .join('\n\n');
  }

  /// Clears failure state without re-running anything. Until this existed the
  /// only way to clear an error was `_startTraining`, wired to both Play and
  /// Retry — so "I have read this" and "run everything again" were one action.
  void _dismissRunErrors() {
    ref.read(studioResultSessionProvider.notifier).dismissErrors();
  }

  @override
  void initState() {
    super.initState();
    _trainingModeNotifier = ref.read(trainingModeProvider.notifier);
    unawaited(
      ref
          .read(trainingRunControllerProvider.notifier)
          .checkForReattachableJobs(),
    );
  }

  @override
  void dispose() {
    // Use saved notifier — ref is unsafe after unmount.
    // ponytail: try-catch handles app-exit where ProviderContainer tears down
    // before widget disposal, making the notifier's internal ref invalid.
    try {
      _trainingModeNotifier.clearDeferred();
    } catch (_) {}
    super.dispose();
  }

  Future<void> _startTraining() async {
    setState(() {
      _successDismissed = false;
    });
    final platforms = await ref
        .read(trainingRunControllerProvider.notifier)
        .startTraining(
          confirmEditChoice: _confirmNotebookEditChoice,
          confirmStopManualSession: _confirmStopManualSession,
        );
    if (!mounted || platforms == null) return;
    setState(() {
      if (_activePlatform == null || !platforms.contains(_activePlatform)) {
        _activePlatform = platforms.first;
      }
    });
  }

  void _stopTraining() {
    ref.read(trainingRunControllerProvider.notifier).stopTraining();
  }

  Future<bool> _confirmStopManualSession() async {
    if (!mounted) return false;
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: NmtkDesignTokens.dialogShape,
        ),
        title: const Text('Notebook is open elsewhere'),
        content: const Text(
          'This notebook has a kernel already running from the embedded '
          'JupyterLab view. Running it here will stop that kernel first — '
          'any unsaved state in it will be lost.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Stop & Run'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<NotebookEditChoice> _confirmNotebookEditChoice() async {
    if (!mounted) return NotebookEditChoice.cancelled;
    final result = await showDialog<NotebookEditChoice>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: NmtkDesignTokens.dialogShape,
        ),
        title: const Text('Notebook has unsaved edits'),
        content: const Text(
          'This notebook was edited in JupyterLab since it was generated. '
          'Running now would normally regenerate it from the current '
          'pipeline config, discarding those edits.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(
              dialogContext,
            ).pop(NotebookEditChoice.discardAndRegenerate),
            child: const Text('Discard & Regenerate'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(NotebookEditChoice.keepEdits),
            child: const Text('Keep My Edits & Run'),
          ),
        ],
      ),
    );
    return result ?? NotebookEditChoice.cancelled;
  }

  void _openNotebook(BuildContext context) {
    openStudioNotebook(context);
  }

  void _showErrorDetails(BuildContext context) {
    final text = _errorBannerDetail;
    if (text == null) return;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(
              ZetaIcons.info,
              size: 18,
              color: Zeta.of(context).colors.mainNegative,
            ),
            const SizedBox(width: 8),
            const Text('Error Details'),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Text(
              text,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: text));
              ScaffoldMessenger.of(ctx).showSnackBar(
                const SnackBar(content: Text('Copied to clipboard')),
              );
            },
            child: const Text('Copy'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final workspace = ref.watch(workspaceProvider);
    final resultSession = ref.watch(studioResultSessionProvider);
    final overlayMetrics = StudioOverlayMetrics.maybeOf(context);
    // Same offset Setup's load row and Deploy's target picker use, so all
    // three per-step header rows sit the same distance below the stepper.
    final viewSwitchTop = overlayMetrics?.belowStepperHeaderTop ?? 0;
    const inlineViewSwitchHeight = 56.0;
    final nonCanvasContentTop = viewSwitchTop + inlineViewSwitchHeight;

    if (widget.view != StudioResultView.architecture) {
      return Stack(
        children: [
          Positioned.fill(
            child: Padding(
              padding: EdgeInsets.only(top: nonCanvasContentTop),
              child: KeyedSubtree(
                key: const Key('run-noncanvas-content'),
                child: StudioResultVisualizer(
                  visualizationContext: StudioVisualizationContext(
                    sourceSnapshot: resultSession.reviewableSnapshot,
                  ),
                  controlledView: widget.view,
                  showViewSwitch: false,
                  showDataSourceDisplay: false,
                  applyOverlayInset: false,
                ),
              ),
            ),
          ),
          Positioned(
            top: viewSwitchTop,
            left: 12,
            right: 12,
            child: Align(
              alignment: Alignment.centerLeft,
              child: ResultsViewSwitch(
                key: const Key('run-result-view-switch'),
                view: widget.view,
                onChanged: widget.onViewChanged,
              ),
            ),
          ),
        ],
      );
    }
    final platforms = workspace.selectedPlatforms.isEmpty
        ? const ['snntorch_sim']
        : workspace.selectedPlatforms;

    final active =
        _activePlatform != null && platforms.contains(_activePlatform)
        ? _activePlatform!
        : platforms.first;
    final epochs = _localEpochs[active] ?? [];
    final lastEpoch = epochs.isEmpty ? null : epochs.last;
    final status = _status[active] ?? TrainingStatus.idle;

    final colors = Zeta.of(context).colors;
    final l10n = AppLocalizations.of(context)!;

    return LayoutBuilder(
      builder: (context, constraints) {
        final bool isCompact =
            constraints.maxWidth < NmtkShellTokens.compactBreakpoint;
        final double bottomSafeInset =
            12 + MediaQuery.viewPaddingOf(context).bottom;

        final banners = Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_hasRunErrors)
              Material(
                elevation: 4,
                borderRadius: BorderRadius.circular(
                  NmtkShellTokens.of(context).radiusSm,
                ),
                clipBehavior: Clip.antiAlias,
                child: Container(
                  width: double.infinity,
                  color: colors.surfaceNegativeSubtle,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        ZetaIcons.error,
                        color: colors.mainNegative,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _errorBannerSummary ??
                              'Run failed — please check errors and retry.',
                          style: TextStyle(color: colors.mainNegative),
                        ),
                      ),
                      if (_errorBannerDetail != null)
                        IconButton(
                          constraints: const BoxConstraints.tightFor(
                            width: 40,
                            height: 40,
                          ),
                          icon: Icon(
                            ZetaIcons.info,
                            color: colors.mainNegative,
                            size: 20,
                          ),
                          tooltip: 'Error details',
                          onPressed: () => _showErrorDetails(context),
                        ),
                      // Acknowledging a failure must not mean re-running every
                      // platform, which is what Retry does.
                      TextButton(
                        key: const Key('run-error-dismiss'),
                        onPressed: _dismissRunErrors,
                        child: Text(
                          'Dismiss',
                          style: TextStyle(color: colors.mainNegative),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (_hasRunErrors) const SizedBox(height: 8),

            if (_isAllSucceeded && !_successDismissed)
              Material(
                elevation: 4,
                borderRadius: BorderRadius.circular(
                  NmtkShellTokens.of(context).radiusSm,
                ),
                clipBehavior: Clip.antiAlias,
                child: Container(
                  width: double.infinity,
                  color: colors.surfacePositiveSubtle,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        ZetaIcons.check_circle,
                        color: colors.mainPositive,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Training complete — preparing results.',
                          style: TextStyle(color: colors.mainPositive),
                        ),
                      ),
                      IconButton(
                        key: const Key('run-success-dismiss'),
                        constraints: const BoxConstraints.tightFor(
                          width: 40,
                          height: 40,
                        ),
                        icon: Icon(
                          ZetaIcons.close,
                          color: colors.mainPositive,
                          size: 18,
                        ),
                        tooltip: 'Dismiss',
                        onPressed: () =>
                            setState(() => _successDismissed = true),
                      ),
                    ],
                  ),
                ),
              ),
            if (_isAllSucceeded && !_successDismissed)
              const SizedBox(height: 8),
          ],
        );

        return Stack(
          children: [
            // ── Canvas Background ──────────────────────────────────────
            Positioned.fill(
              child: KeepAliveWrapper(
                child: CanvasScreen(
                  lockedTab: CanvasTab.architecture,
                  disableEditingChrome: true,
                  bottomRightUtilityPanel: isCompact
                      ? null
                      : Material(
                          elevation: 4,
                          borderRadius: BorderRadius.circular(
                            NmtkShellTokens.of(context).radiusSm,
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: MetricsSidebar(
                            status: status,
                            epochs: epochs,
                            lastEpoch: lastEpoch,
                            colors: colors,
                          ),
                        ),
                  bottomRightUtilityPanelHeight: kMetricsDockHeight,
                  bottomRightUtilityPanelWidth: kMetricsDockWidth,
                ),
              ),
            ),

            Positioned(
              top: viewSwitchTop,
              left: 32,
              right: 12,
              child: Align(
                alignment: Alignment.centerLeft,
                child: ResultsViewSwitch(
                  key: const Key('run-result-view-switch'),
                  view: widget.view,
                  onChanged: widget.onViewChanged,
                ),
              ),
            ),

            // ── Bottom overlays: banners, compact metrics strip, action bar.
            // Collapsed into one Column so there's a single source of truth
            // for their stacking order and spacing, instead of three
            // independently-positioned magic bottom offsets.
            Positioned(
              left: 12,
              right: isCompact ? 12 : kMetricsDockInset + 12,
              bottom: bottomSafeInset,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SizedBox(width: double.infinity, child: banners),
                  if (isCompact) ...[
                    SizedBox(
                      width: double.infinity,
                      child: Material(
                        elevation: 4,
                        borderRadius: BorderRadius.circular(
                          NmtkShellTokens.of(context).radiusSm,
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: MetricsSidebar(
                          status: status,
                          epochs: epochs,
                          lastEpoch: lastEpoch,
                          colors: colors,
                          isHorizontal: true,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  RunActionBar(
                    isRunning: _isAnyRunning,
                    hasErrors: _hasRunErrors,
                    isCompact: isCompact,
                    notebookAvailable: supportsEmbeddedWebView,
                    l10n: l10n,
                    onPlay: _startTraining,
                    onStop: _stopTraining,
                    onOpenNotebook: () => _openNotebook(context),
                    onRetry: _startTraining,
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
