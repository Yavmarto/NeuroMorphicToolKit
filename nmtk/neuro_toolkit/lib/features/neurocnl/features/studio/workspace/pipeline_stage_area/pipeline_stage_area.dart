import 'package:flutter/material.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

import 'package:neuro_toolkit/features/neurocnl/models/studio_pipeline_steps.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/workspace/pipeline_stage_area/single_stage_view.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/workspace/pipeline_stage_area/split_stage_view.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/workspace/pipeline_stage_area/step_card.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/workspace/pipeline_stage_area/support.dart';

class PipelineStageArea extends StatefulWidget {
  const PipelineStageArea({
    super.key,
    required this.activeStep,
    required this.splitStep,
    required this.stepCount,
    required this.stepBuilder,
    required this.frameBuilder,
    required this.onStepChanged,
    required this.onCollapse,
    this.canvasStepNames = const <String>{},
    this.unlockedStepNames = const <String>{},
    this.topInset = 0.0,
    this.contentTopPad = 0.0,
  });

  final String activeStep;
  final String? splitStep;
  final int stepCount;
  final Widget Function(int index) stepBuilder;
  final Widget Function({required Widget child}) frameBuilder;
  final ValueChanged<String> onStepChanged;
  final ValueChanged<String> onCollapse;
  final Set<String> canvasStepNames;
  final Set<String> unlockedStepNames;
  final double topInset;
  // ponytail: internal top padding for non-canvas steps so readable content
  // clears the floating stepper, while the card background fills full-screen.
  final double contentTopPad;

  @override
  State<PipelineStageArea> createState() => _PipelineStageAreaState();
}

class _PipelineStageAreaState extends State<PipelineStageArea>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  // Owned PageController for SingleStageView — recreated on each collapse so
  // it always starts at the correct page (no wrong-page flicker).
  PageController _singleCtrl = PageController();

  // Captured when a transition starts; stable for its duration.
  String _mainStep = '';
  String? _secondaryStep;
  bool _secondaryIsRight = true;

  // ponytail: 1.0 — stepper floats, peek effect not needed; canvas needs full bleed
  static const double _kDesktopViewportFraction = 1.0;
  static const double _cardHPad = 4.0;

  // Tracks whether the layout is in mobile mode
  // (width < NmtkShellTokens.compactBreakpoint).
  bool _isMobile = false;

  // Counts in-flight programmatic animateToPage calls so onPageChanged
  // callbacks fired during those animations don't feed back into Riverpod state
  // and redirect the scroll to an intermediate page.
  int _programmaticScrollCount = 0;

  // Direction of the most recent split-view pair navigation.
  SplitNavDir _splitNavDir = SplitNavDir.none;

  String _normalizeStepName(String? stepName, {String? fallback}) {
    return normalizeStudioPipelineStep(
      stepName,
      fallback: fallback ?? kDefaultStudioPipelineStep,
    );
  }

  int _stepIndex(String? stepName, {String? fallback}) {
    return indexOfStudioPipelineStep(
      stepName,
      fallback: fallback ?? kDefaultStudioPipelineStep,
    );
  }

  @override
  void initState() {
    super.initState();
    _mainStep = _normalizeStepName(widget.activeStep);
    final initialIdx = _stepIndex(widget.activeStep);
    _singleCtrl = PageController(
      initialPage: initialIdx,
      viewportFraction: 1.0,
    );
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
      value: widget.splitStep != null ? 1.0 : 0.0,
    );
    _anim = CurvedAnimation(
      parent: _ctrl,
      curve: Curves.easeInOutCubic,
      reverseCurve: Curves.easeInOutCubic,
    );
    if (widget.splitStep != null) {
      _secondaryStep = _normalizeStepName(
        widget.splitStep,
        fallback: _mainStep,
      );
      _secondaryIsRight = _isRightOf(_secondaryStep!, widget.activeStep);
    }
    _ctrl.addStatusListener((status) {
      if (status == AnimationStatus.dismissed) {
        _mainStep = _normalizeStepName(_mainStep);
        final targetIdx = _stepIndex(_mainStep);
        // Recreate the controller at the correct page BEFORE revealing
        // SingleStageView.  A fresh PageController has no saved scroll
        // offset, so it attaches at exactly targetIdx — no wrong-page frame.
        _singleCtrl.dispose();
        _singleCtrl = PageController(
          initialPage: targetIdx,
          viewportFraction: _isMobile ? 1.0 : _kDesktopViewportFraction,
        );
        setState(() => _secondaryStep = null);
      }
    });
  }

  @override
  void dispose() {
    _singleCtrl.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(PipelineStageArea old) {
    super.didUpdateWidget(old);

    if (widget.splitStep != null && old.splitStep == null) {
      // Single → split
      _mainStep = _normalizeStepName(widget.activeStep);
      _secondaryStep = _normalizeStepName(
        widget.splitStep,
        fallback: _mainStep,
      );
      _secondaryIsRight = _isRightOf(_secondaryStep!, _mainStep);
      _ctrl.forward(from: 0);
    } else if (widget.splitStep == null && old.splitStep != null) {
      // Split → single.  Infer _mainStep / _secondaryStep from old widget
      // values when not already pre-set (collapse always comes from top bar or
      // an external state reset such as a workspace reload).
      if (_secondaryStep == null) {
        final keepStep = _normalizeStepName(widget.activeStep);
        final removed = keepStep == _normalizeStepName(old.activeStep)
            ? _normalizeStepName(old.splitStep, fallback: keepStep)
            : _normalizeStepName(old.activeStep, fallback: keepStep);
        _mainStep = keepStep;
        _secondaryStep = removed;
        _secondaryIsRight = _isRightOf(removed, keepStep);
      }
      _ctrl.reverse();
    } else if (widget.activeStep != old.activeStep &&
        _ctrl.isDismissed &&
        _secondaryStep == null) {
      // External step change (top-bar stepper tap) while in settled single view.
      final newIdx = _stepIndex(widget.activeStep);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_singleCtrl.hasClients) {
          return;
        }
        // jumpToPage, NOT animateToPage. With viewportFraction 1.0 an animated
        // scroll drags every intermediate page through the viewport, so a
        // Setup→Deploy tap builds all seven steps — and KeepAliveWrapper then
        // pins each one alive for the rest of the session. That is several live
        // CanvasScreens (some carrying a 10000x10000 InteractiveViewer), which
        // is where the CPU spike and the resident memory came from. A jump
        // lays out only the destination.
        // Swipe navigation is unaffected — that scroll is user-driven.
        _programmaticScrollCount++;
        _singleCtrl.jumpToPage(newIdx);
        // Held one frame: onPageChanged can arrive during the jump's layout,
        // and it must not feed the change back into Riverpod.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _programmaticScrollCount--;
        });
      });
    }

    // Detect split-view pair navigation direction so AnimatedSwitcher can
    // slide in the correct direction.
    if (widget.splitStep != null &&
        old.splitStep != null &&
        (widget.activeStep != old.activeStep ||
            widget.splitStep != old.splitStep)) {
      final oldAIdx = _stepIndex(old.activeStep);
      final oldSIdx = _stepIndex(old.splitStep, fallback: old.activeStep);
      final newAIdx = _stepIndex(widget.activeStep);
      final newSIdx = _stepIndex(widget.splitStep, fallback: widget.activeStep);
      final oldLeft = oldAIdx <= oldSIdx ? oldAIdx : oldSIdx;
      final newLeft = newAIdx <= newSIdx ? newAIdx : newSIdx;
      if (newLeft != oldLeft) {
        _splitNavDir = newLeft > oldLeft ? SplitNavDir.next : SplitNavDir.prev;
      }
    }
  }

  bool _isRightOf(String step, String reference) =>
      _stepIndex(step, fallback: reference) > _stepIndex(reference);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final total = constraints.maxWidth;
        final isMobile = total < NmtkShellTokens.compactBreakpoint;

        // React to mobile ↔ desktop layout transitions.
        if (isMobile != _isMobile) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            // Collapse any active split when entering mobile layout.
            if (isMobile && widget.splitStep != null) {
              widget.onCollapse(widget.activeStep);
            }
            // Recreate controller with the correct viewport fraction.
            final targetIdx = _stepIndex(widget.activeStep);
            _singleCtrl.dispose();
            _singleCtrl = PageController(
              initialPage: targetIdx,
              viewportFraction: isMobile ? 1.0 : _kDesktopViewportFraction,
            );
            setState(() => _isMobile = isMobile);
          });
        }

        final halfWidth = (total - 8) / 2;

        final viewportFraction = _isMobile ? 1.0 : _kDesktopViewportFraction;
        final pageWidth = total * viewportFraction;

        return AnimatedBuilder(
          animation: _anim,
          builder: (context, _) {
            final t = _anim.value;

            Widget content;

            if (isMobile) {
              // ── Mobile: always full-width single view ────────────────
              content = SingleStageView(
                key: const ValueKey('single'),
                pageController: _singleCtrl,
                stepCount: widget.stepCount,
                stepBuilder: widget.stepBuilder,
                frameBuilder: widget.frameBuilder,
                canvasStepNames: widget.canvasStepNames,
                cardHPad: 0.0,
                contentTopPad: 0.0,
                isMobile: isMobile,
                onStepChanged: (name) {
                  if (_programmaticScrollCount == 0) widget.onStepChanged(name);
                },
              );
            } else if (_ctrl.isDismissed && _secondaryStep == null) {
              // ── Fully settled: single view ───────────────────────────
              content = SingleStageView(
                key: const ValueKey('single'),
                pageController: _singleCtrl,
                stepCount: widget.stepCount,
                stepBuilder: widget.stepBuilder,
                frameBuilder: widget.frameBuilder,
                canvasStepNames: widget.canvasStepNames,
                cardHPad: _cardHPad,
                contentTopPad: widget.contentTopPad,
                isMobile: isMobile,
                onStepChanged: (name) {
                  if (_programmaticScrollCount == 0) widget.onStepChanged(name);
                },
              );
            } else if (_ctrl.isCompleted && widget.splitStep != null) {
              // ── Fully settled: split view ────────────────────────────
              final splitNavDir = _splitNavDir;
              content = ClipRect(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 280),
                  transitionBuilder: (child, animation) {
                    final isIncoming =
                        child.key ==
                        ValueKey(
                          'split-${widget.activeStep}-${widget.splitStep}',
                        );
                    final Offset begin;
                    if (splitNavDir == SplitNavDir.next) {
                      begin = isIncoming
                          ? const Offset(1, 0)
                          : const Offset(-1, 0);
                    } else if (splitNavDir == SplitNavDir.prev) {
                      begin = isIncoming
                          ? const Offset(-1, 0)
                          : const Offset(1, 0);
                    } else {
                      begin = Offset.zero;
                    }
                    return SlideTransition(
                      position: Tween<Offset>(begin: begin, end: Offset.zero)
                          .animate(
                            CurvedAnimation(
                              parent: animation,
                              curve: Curves.easeOutCubic,
                            ),
                          ),
                      child: child,
                    );
                  },
                  child: SplitStageView(
                    key: ValueKey(
                      'split-${widget.activeStep}-${widget.splitStep}',
                    ),
                    activeStep: widget.activeStep,
                    splitStep: widget.splitStep!,
                    stepBuilder: widget.stepBuilder,
                    frameBuilder: widget.frameBuilder,
                    canvasStepNames: widget.canvasStepNames,
                    contentTopPad: widget.contentTopPad,
                  ),
                ),
              );
            } else if (_secondaryStep != null) {
              // ── Animating transition ─────────────────────────────────
              final secWidth = t * halfWidth;
              final gapWidth = t * 8.0;
              final mainWidth = total - secWidth - gapWidth;

              // Interpolate the 4-px horizontal padding that
              // SingleStageView.itemBuilder adds around each step card.
              // At t=0 (settled single) pad = _cardHPad so the last animation
              // frame is pixel-identical to the first SingleStageView frame —
              // no width snap or flicker.  At t=1 (fully split) pad = 0 to
              // match SplitStageView's Expanded children (no padding).
              // Screen-width-aware padding so the last animation frame is
              // pixel-identical to SingleStageView's Padding(horizontal: 4)
              // wrapper + the PageView's 0.91 viewport fraction margins.
              final mainPad = ((total - pageWidth) / 2 + _cardHPad) * (1.0 - t);

              final mainIdx = kStudioPipelineStepNames
                  .indexOf(_mainStep)
                  .clamp(0, kStudioPipelineStepNames.length - 1);
              final secIdx = kStudioPipelineStepNames
                  .indexOf(_secondaryStep!)
                  .clamp(0, kStudioPipelineStepNames.length - 1);

              final mainIsCanvas = widget.canvasStepNames.contains(_mainStep);
              final secIsCanvas = widget.canvasStepNames.contains(
                _secondaryStep,
              );
              final mainCard = Padding(
                padding: EdgeInsets.symmetric(horizontal: mainPad),
                child: StepCard(
                  stepName: _mainStep,
                  frameBuilder: widget.frameBuilder,
                  child: mainIsCanvas
                      ? widget.stepBuilder(mainIdx)
                      : Padding(
                          padding: EdgeInsets.only(top: widget.contentTopPad),
                          child: widget.stepBuilder(mainIdx),
                        ),
                ),
              );
              final secCard = StepCard(
                stepName: _secondaryStep!,
                frameBuilder: widget.frameBuilder,
                child: secIsCanvas
                    ? widget.stepBuilder(secIdx)
                    : Padding(
                        padding: EdgeInsets.only(top: widget.contentTopPad),
                        child: widget.stepBuilder(secIdx),
                      ),
              );

              // Secondary pane: fixed halfWidth content, clipped to secWidth.
              // Align anchors the edge that was already visible so the content
              // appears to slide in (or out) from that edge.
              final secPane = ClipRect(
                child: SizedBox(
                  width: secWidth,
                  height: double.infinity,
                  child: Align(
                    alignment: _secondaryIsRight
                        ? Alignment.centerRight
                        : Alignment.centerLeft,
                    child: SizedBox(width: halfWidth, child: secCard),
                  ),
                ),
              );

              content = Row(
                children: _secondaryIsRight
                    ? [
                        SizedBox(width: mainWidth, child: mainCard),
                        SizedBox(width: gapWidth),
                        secPane,
                      ]
                    : [
                        secPane,
                        SizedBox(width: gapWidth),
                        SizedBox(width: mainWidth, child: mainCard),
                      ],
              );
            } else {
              content = const SizedBox.shrink();
            }

            // ponytail: always Padding(top) — consistent parent keeps SingleStageView
            // element stable across topInset changes, preventing Multiple PageViews.
            return Padding(
              padding: EdgeInsets.only(top: widget.topInset),
              child: content,
            );
          },
        );
      },
    );
  }
}
