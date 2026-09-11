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

  /// The success toast has no backing provider state for "the user already
  /// saw this" — unlike the error toast's `dismissedErrors` set (which must
  /// survive platform-tab switches), it only needs to disappear until the
  /// next run, so local state is enough. Reset in `_startTraining` so a
  /// fresh run re-shows it.
  bool _successDismissed = false;

  /// Guards against re-showing the error/success toast on every session
  /// update while the underlying condition is still true — `ref.listen`
  /// fires on every provider change, not just the edge where errors/success
  /// first appear.
  bool _errorSnackbarActive = false;
  bool _successSnackbarActive = false;

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

  void _handleSessionChange(
    StudioResultSessionState? previous,
    StudioResultSessionState next,
  ) {
    if (!mounted) return;
    if (_hasRunErrors) {
      if (!_errorSnackbarActive) {
        _errorSnackbarActive = true;
        _showErrorSnackbar();
      }
    } else {
      _errorSnackbarActive = false;
    }
    if (_isAllSucceeded && !_successDismissed) {
      if (!_successSnackbarActive) {
        _successSnackbarActive = true;
        _showSuccessSnackbar();
      }
    } else {
      _successSnackbarActive = false;
    }
  }

  void _showErrorSnackbar() {
    final detail = _errorBannerDetail;
    NmtkSnackBars.error(
      context,
      _errorBannerSummary ?? 'Run failed — please check errors and retry.',
      key: 'run-step-error',
      duration: null,
      action: detail == null
          ? null
          : NmtkNotificationAction(
              label: 'Details',
              onPressed: () => _showErrorDetails(context),
            ),
      onDismissed: _dismissRunErrors,
    );
  }

  void _showSuccessSnackbar() {
    NmtkSnackBars.success(
      context,
      'Training complete — preparing results.',
      key: 'run-step-success',
      onDismissed: () {
        if (mounted) setState(() => _successDismissed = true);
      },
    );
  }

  Future<void> _startTraining() async {
    setState(() {
      _successDismissed = false;
      _successSnackbarActive = false;
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
          ZetaButton.text(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            label: 'Cancel',
          ),
          ZetaButton.text(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            label: 'Stop & Run',
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
          ZetaButton.text(
            onPressed: () => Navigator.of(
              dialogContext,
            ).pop(NotebookEditChoice.discardAndRegenerate),
            label: 'Discard & Regenerate',
          ),
          ZetaButton.text(
            onPressed: () =>
                Navigator.of(dialogContext).pop(NotebookEditChoice.keepEdits),
            label: 'Keep My Edits & Run',
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
              // ZETA-MIGRATION-EXEMPT: error trace is monospace — Zeta (IBM Plex
              // Sans) has no monospace text style.
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ),
        ),
        actions: [
          ZetaButton.text(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: text));
              NmtkSnackBars.success(ctx, 'Copied to clipboard');
            },
            label: 'Copy',
          ),
          ZetaButton.text(
            onPressed: () => Navigator.of(ctx).pop(),
            label: 'Close',
          ),
        ],
      ),
    ).then((_) {
      // Details view auto-closes the toast (SnackBarAction always does);
      // bring it back if the error is still live.
      if (mounted && _hasRunErrors) _showErrorSnackbar();
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<StudioResultSessionState>(
      studioResultSessionProvider,
      _handleSessionChange,
    );
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
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ResultsViewSwitch(
                    key: const Key('run-result-view-switch'),
                    view: widget.view,
                    onChanged: widget.onViewChanged,
                  ),
                ],
              ),
            ),

            // ── Bottom overlays: compact metrics strip, action bar. Errors
            // and success are reported via toast (see _showErrorSnackbar /
            // _showSuccessSnackbar), not banners stacked here.
            Positioned(
              left: 12,
              right: isCompact ? 12 : kMetricsDockInset + 12,
              bottom: bottomSafeInset,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
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
