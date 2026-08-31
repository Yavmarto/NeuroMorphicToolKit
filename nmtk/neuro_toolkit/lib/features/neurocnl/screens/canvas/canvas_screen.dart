import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

import 'package:neuro_toolkit/features/neurocnl/models/canvas/canvas.dart';
import 'package:neuro_toolkit/features/neurocnl/models/canvas/component.dart';
import 'package:neuro_toolkit/features/neurocnl/models/canvas/custom_pipeline_node.dart';
import 'package:neuro_toolkit/features/neurocnl/models/canvas/imported_cnl_spec.dart';
import 'package:neuro_toolkit/features/neurocnl/models/nir_node_type.dart';
import 'package:neuro_toolkit/features/neurocnl/theme/nir_node_styles.dart';
import 'package:neuro_toolkit/features/neurocnl/models/canvas/pipeline_dag.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/canvas/canvas_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/canvas/canvas_selectors.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/canvas/cnl_import_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/canvas/component_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/canvas/nir_types_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/canvas/simulation_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/canvas/sync_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/nir_import_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/spec_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/canvas/validation_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/services/import_cnl_payload.dart';
import 'package:neuro_toolkit/features/neurocnl/routing/canvas/neurosim_nav_section.dart';
import 'package:neuro_toolkit/features/neurocnl/utils/canvas_palette_search.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/canvas/canvas_palette_search_field.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/canvas/canvas_simulation_surface.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/canvas/mobile_canvas_chrome.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/canvas/network_canvas.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/canvas/pipeline_node_property_panel.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/canvas/pipeline_overview_canvas.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/canvas/pipeline_phase_canvas.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/canvas/pipeline_settings_dialog.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/workspace_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/canvas/property_panel.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/canvas/shell_panel.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/canvas/simulation_control_panel.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/cnl_editor.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/nir_importer_tab.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/studio_overlay_metrics.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/validation_overlay.dart';

class CanvasScreen extends ConsumerStatefulWidget {
  const CanvasScreen({
    super.key,
    this.initialUri,
    this.activeSection = NeuroSimNavSection.canvas,
    this.lockedTab,
    this.disableInspectorOverlay = false,
    this.disableEditingChrome = false,
    this.initiallyShowInspector = false,
    this.bottomRightUtilityPanel,
    this.bottomRightUtilityPanelHeight = 0,
    this.bottomRightUtilityPanelWidth = 240,
  });

  final Uri? initialUri;
  final NeuroSimNavSection activeSection;
  final CanvasTab? lockedTab;
  final bool disableInspectorOverlay;

  /// Allows an embedding surface to start with the Inspector open. Interactive
  /// canvases retain the usual closed-by-default behavior.
  final bool initiallyShowInspector;

  /// Suppresses the floating undo/redo/clear-canvas toolbar
  /// ([MobileCanvasChrome]). Set this when [CanvasScreen] is embedded as a
  /// read-only background (e.g. behind the Run or Results step) — editing
  /// controls there are both meaningless and visually redundant with that
  /// screen's own action bar.
  final bool disableEditingChrome;

  /// Optional Run-step utility panel rendered in the canvas's bottom-right
  /// dock. The Inspector stacks immediately above it when open.
  final Widget? bottomRightUtilityPanel;
  final double bottomRightUtilityPanelHeight;
  final double bottomRightUtilityPanelWidth;

  @override
  ConsumerState<CanvasScreen> createState() => _CanvasScreenState();
}

class _CanvasScreenState extends ConsumerState<CanvasScreen> {
  /// Confirms before an irreversible "Clear Canvas" action. Undo does not
  /// cover this: `clearArchitectureGraph()` also clears `canonicalDocProvider`
  /// (the CNL/NIR spec), which lives outside `canvasProvider`'s undo stack,
  /// so once confirmed this cannot be brought back with "Undo".
  Future<bool> _confirmClearCanvas(String whatLabel) async {
    if (!mounted) return false;
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: NmtkDesignTokens.dialogShape,
        ),
        title: Text('Clear $whatLabel?'),
        content: Text(
          'This removes all $whatLabel nodes and connections. This cannot be '
          'undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  static const double _minimumPanelWidth = 220;
  static const double _maximumPanelWidth = 520;
  // Design gap between the floating stepper and the editor overlay panels.
  static const double _kEditorTopGap = 12.0;

  bool _showProperties = false;
  bool _showCnl = false;
  bool _showNir = false;
  double _propertyWidth = 320;
  double _cnlWidth = 380;
  double _nirWidth = 380;
  String? _startupBannerMessage;
  bool _startupBannerIsError = false;
  bool _initialImportHandled = false;

  /// True while the mobile node-inspector bottom sheet is on screen. Mobile
  /// has no docked Inspector (`effectiveShowProperties` is forced false
  /// there) — this is what tapping a node opens instead. Guards against
  /// pushing a second sheet on top of an already-open one when the user taps
  /// a different node; the sheet's content (`PropertyPanel`/
  /// `PipelineNodePropertyPanel`) already watches the selected node
  /// reactively, so an already-open sheet updates itself.
  bool _mobileNodeSheetOpen = false;

  // Auto-layout orientation, tracked per tab -- a split pipeline-stepper
  // pane can put e.g. the train tab and eval tab at different local widths
  // at once, so these must not share one flag. Defaults match the axes each
  // tab was hardcoded to before this became width-aware.
  final Map<CanvasTab, CanvasLayoutAxis> _tabAxis = {
    CanvasTab.architecture: CanvasLayoutAxis.vertical,
    CanvasTab.pipelineTrain: CanvasLayoutAxis.horizontal,
    CanvasTab.pipelineEval: CanvasLayoutAxis.horizontal,
  };
  final Map<CanvasTab, Timer> _relayoutDebounce = {};

  @override
  void initState() {
    super.initState();
    _showProperties = widget.initiallyShowInspector;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _consumeInitialImport();
    });
    // A locked-tab instance (the Studio step wizard's Training DAG / Eval DAG
    // steps) never goes through PipelineOverviewCanvas._openPipelineTab, which
    // is otherwise the only place that seeds the default pipeline node chain
    // -- without this, those steps show a permanently empty canvas.
    if (widget.lockedTab?.isPipeline ?? false) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final ws = ref.read(workspaceProvider);
        ref
            .read(canvasProvider.notifier)
            .initDefaultPhases(
              frameworks: ws.selectedPlatforms,
              dataset: ws.selectedDataset,
            );
      });
    }
  }

  @override
  void dispose() {
    for (final timer in _relayoutDebounce.values) {
      timer.cancel();
    }
    super.dispose();
  }

  /// Records the tab's current local-width orientation and, on an actual
  /// flip (not every resize frame), debounces an automatic re-layout so a
  /// window drag doesn't fire dozens of destructive relayouts mid-drag.
  ///
  /// Auto-rerunning on crossing (rather than only affecting the next manual
  /// "Auto Layout" tap) is a deliberate choice: repeatedly resizing across
  /// the breakpoint will keep re-triggering layout and can clobber manual
  /// node placement each time -- accepted tradeoff for width automatically
  /// tracking the visual orientation.
  void _handleOrientationMeasured(CanvasTab tab, bool isVertical) {
    final axis = isVertical
        ? CanvasLayoutAxis.vertical
        : CanvasLayoutAxis.horizontal;
    if (_tabAxis[tab] == axis) return;
    _tabAxis[tab] = axis;
    _relayoutDebounce[tab]?.cancel();
    _relayoutDebounce[tab] = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _runAutoLayout(tab, axis);
      });
    });
  }

  void _runAutoLayout(CanvasTab tab, CanvasLayoutAxis axis) {
    final notifier = ref.read(canvasProvider.notifier);
    switch (tab) {
      case CanvasTab.architecture:
        notifier.autoLayoutGraph(axis: axis);
      case CanvasTab.pipelineTrain:
        notifier.autoLayoutPipelineDag(PipelinePhaseId.train, axis: axis);
      case CanvasTab.pipelineEval:
        notifier.autoLayoutPipelineDag(PipelinePhaseId.eval, axis: axis);
      case CanvasTab.pipelineOverview:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final activeTab = ref.watch(
      canvasProvider.select((state) => state.activeTab),
    );
    final canUndo = ref.watch(canvasProvider.select((state) => state.canUndo));
    final canRedo = ref.watch(canvasProvider.select((state) => state.canRedo));
    final tokens = NmtkShellTokens.of(context);
    final hasSelection = ref.watch(
      canvasProvider.select(
        (state) =>
            state.selectedNodeIds.isNotEmpty || state.selectedEdgeId != null,
      ),
    );
    final isMobile =
        MediaQuery.sizeOf(context).width < NmtkShellTokens.compactBreakpoint;
    final displayTab = widget.lockedTab ?? activeTab;
    final isArchitecture = displayTab == CanvasTab.architecture;
    final phaseId = displayTab.phaseId;
    final effectiveShowProperties = isMobile
        ? false
        : (_showProperties && (isArchitecture || hasSelection));

    // Mobile has no docked Inspector, so a tapped node's params would
    // otherwise be unreachable there — open them in a bottom sheet instead.
    // Fires on every selection change; the sheet is only actually pushed on
    // null -> non-null (a fresh tap), and popped on non-null -> null
    // (background tap deselects). Selecting a *different* node while the
    // sheet is already open just lets its reactive content swap underneath.
    //
    // CanvasScreen is instantiated once per wizard step (architecture,
    // pipelineTrain, pipelineEval) and kept alive by _KeepAliveWrapper once
    // visited, so 3 instances can be listening to this same global selection
    // signal at once. Without checking that the selected id actually belongs
    // to *this* instance's own node set, selecting a node on one tab pops a
    // sheet on all 3 — stacked barriers read as a black screen and need one
    // dismiss per instance.
    ref.listen(canvasSelectedNodeIdProvider, (previous, next) {
      if (!isMobile ||
          widget.disableInspectorOverlay ||
          (!isArchitecture && phaseId == null)) {
        return;
      }
      if (next != null && !_mobileNodeSheetOpen) {
        final belongsHere = isArchitecture
            ? ref.read(canvasProvider).graph.nodes.any((n) => n.id == next)
            : ref
                  .read(canvasProvider)
                  .pipelinePhases
                  .dagFor(phaseId!)
                  .nodes
                  .any((n) => n.id == next);
        if (belongsHere) {
          _showMobileNodeSheet(
            isArchitecture: isArchitecture,
            phaseId: phaseId,
          );
        }
      } else if (next == null && _mobileNodeSheetOpen) {
        Navigator.of(context).maybePop();
      }
    });
    final editorTop =
        (StudioOverlayMetrics.maybeOf(context)?.stepperBottom ?? 0) +
        _kEditorTopGap;
    final utilityPanelVisible =
        !isMobile && widget.bottomRightUtilityPanel != null;
    final utilityPanelHeight = utilityPanelVisible
        ? widget.bottomRightUtilityPanelHeight
        : 0.0;
    final inspectorAvailableHeight =
        MediaQuery.sizeOf(context).height -
        editorTop -
        utilityPanelHeight -
        (utilityPanelVisible ? 36 : 24);
    final inspectorDockHeight = math
        .min(420.0, math.max(160.0, inspectorAvailableHeight))
        .toDouble();

    if (widget.activeSection == NeuroSimNavSection.simulate) {
      return ColoredBox(
        color: tokens.shellBackground,
        child: Column(
          children: [
            if (_startupBannerMessage != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                child: _buildStartupBanner(tokens),
              ),
            const SimulationControlPanel(),
            const Expanded(child: CanvasSimulationSurface()),
          ],
        ),
      );
    }

    final canvasWidget = ColoredBox(
      color: tokens.shellBackground,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_startupBannerMessage != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _buildStartupBanner(tokens),
                  ),
                Expanded(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: tokens.canvasBackground,
                      borderRadius: (isMobile || widget.lockedTab != null)
                          ? BorderRadius.zero
                          : BorderRadius.circular(tokens.radiusLg),
                      border: (isMobile || widget.lockedTab != null)
                          ? null
                          : Border.all(color: tokens.chromeBorder),
                    ),
                    child: ClipRRect(
                      borderRadius: (isMobile || widget.lockedTab != null)
                          ? BorderRadius.zero
                          : BorderRadius.circular(tokens.radiusLg),
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: switch (displayTab) {
                              CanvasTab.pipelineOverview =>
                                const PipelineOverviewCanvas(),
                              CanvasTab.pipelineTrain => LayoutBuilder(
                                builder: (context, constraints) {
                                  final isVertical =
                                      constraints.maxWidth <
                                      NmtkShellTokens.compactBreakpoint;
                                  _handleOrientationMeasured(
                                    CanvasTab.pipelineTrain,
                                    isVertical,
                                  );
                                  final body = PipelinePhaseCanvas(
                                    phase: PipelinePhaseId.train,
                                    onNodeDoubleTap: _openInspector,
                                    isVertical: isVertical,
                                  );
                                  if (widget.disableEditingChrome) return body;
                                  return MobileCanvasChrome(
                                    body: body,
                                    extraRightActions: [
                                      CanvasChromeIconButton(
                                        icon: ZetaIcons.tune,
                                        tooltip: 'Pipeline Settings',
                                        enabled: true,
                                        onPressed: () =>
                                            showPipelineSettingsDialog(
                                              context,
                                              ref,
                                            ),
                                      ),
                                    ],
                                    barColor: const Color(0xFF0B1F3A),
                                    canvasTint: tokens.commandPalette.frameTint,
                                    onAutoLayout: () => _runAutoLayout(
                                      CanvasTab.pipelineTrain,
                                      _tabAxis[CanvasTab.pipelineTrain]!,
                                    ),
                                    onAddPrimitive: () =>
                                        _showPipelinePaletteSheet(
                                          context,
                                          ref,
                                          PipelinePhaseId.train,
                                        ),
                                    onClearCanvas: () async {
                                      if (!await _confirmClearCanvas(
                                        'Train pipeline',
                                      )) {
                                        return;
                                      }
                                      ref
                                          .read(canvasProvider.notifier)
                                          .clearPipelinePhase(
                                            PipelinePhaseId.train,
                                          );
                                    },
                                    onUndo: () => ref
                                        .read(canvasProvider.notifier)
                                        .undo(),
                                    onRedo: () => ref
                                        .read(canvasProvider.notifier)
                                        .redo(),
                                    canUndo: canUndo,
                                    canRedo: canRedo,
                                  );
                                },
                              ),
                              CanvasTab.pipelineEval => LayoutBuilder(
                                builder: (context, constraints) {
                                  final isVertical =
                                      constraints.maxWidth <
                                      NmtkShellTokens.compactBreakpoint;
                                  _handleOrientationMeasured(
                                    CanvasTab.pipelineEval,
                                    isVertical,
                                  );
                                  final body = PipelinePhaseCanvas(
                                    phase: PipelinePhaseId.eval,
                                    onNodeDoubleTap: _openInspector,
                                    isVertical: isVertical,
                                  );
                                  if (widget.disableEditingChrome) return body;
                                  return MobileCanvasChrome(
                                    body: body,
                                    barColor: const Color(0xFF0B2116),
                                    canvasTint: tokens.healthyColor.withValues(
                                      alpha: 0.08,
                                    ),
                                    onAutoLayout: () => _runAutoLayout(
                                      CanvasTab.pipelineEval,
                                      _tabAxis[CanvasTab.pipelineEval]!,
                                    ),
                                    onAddPrimitive: () =>
                                        _showPipelinePaletteSheet(
                                          context,
                                          ref,
                                          PipelinePhaseId.eval,
                                        ),
                                    onClearCanvas: () async {
                                      if (!await _confirmClearCanvas(
                                        'Eval pipeline',
                                      )) {
                                        return;
                                      }
                                      ref
                                          .read(canvasProvider.notifier)
                                          .clearPipelinePhase(
                                            PipelinePhaseId.eval,
                                          );
                                    },
                                    onUndo: () => ref
                                        .read(canvasProvider.notifier)
                                        .undo(),
                                    onRedo: () => ref
                                        .read(canvasProvider.notifier)
                                        .redo(),
                                    canUndo: canUndo,
                                    canRedo: canRedo,
                                  );
                                },
                              ),
                              CanvasTab.architecture => LayoutBuilder(
                                builder: (context, constraints) {
                                  final isVertical =
                                      constraints.maxWidth <
                                      NmtkShellTokens.compactBreakpoint;
                                  _handleOrientationMeasured(
                                    CanvasTab.architecture,
                                    isVertical,
                                  );
                                  final canvasBody = Stack(
                                    children: [
                                      Positioned.fill(
                                        child: NetworkCanvas(
                                          onNodeDoubleTap: _openInspector,
                                          isVertical: isVertical,
                                        ),
                                      ),
                                    ],
                                  );
                                  if (widget.disableEditingChrome) {
                                    return canvasBody;
                                  }
                                  return MobileCanvasChrome(
                                    body: canvasBody,
                                    extraLeftActions: [
                                      CanvasChromeIconButton(
                                        icon: ZetaIcons.document,
                                        tooltip: 'CNL Editor',
                                        enabled: true,
                                        tint: _showCnl
                                            ? const Color(0xFF7B61FF)
                                            : null,
                                        onPressed: () {
                                          setState(() {
                                            _showCnl = !_showCnl;
                                          });
                                        },
                                      ),
                                    ],
                                    extraRightActions: [
                                      CanvasChromeIconButton(
                                        icon: ZetaIcons.tune,
                                        tooltip: 'Inspector',
                                        enabled: true,
                                        tint: _showProperties
                                            ? const Color(0xFF7B61FF)
                                            : null,
                                        onPressed: _toggleInspector,
                                      ),
                                      CanvasChromeIconButton(
                                        icon: ZetaIcons.upload,
                                        tooltip: 'NIR Importer',
                                        enabled: true,
                                        tint: _showNir
                                            ? const Color(0xFF7B61FF)
                                            : null,
                                        onPressed: () {
                                          setState(() {
                                            _showNir = !_showNir;
                                            if (_showNir) {
                                              _showProperties = false;
                                            }
                                          });
                                        },
                                      ),
                                      const SizedBox(width: 8),
                                      const ValidationStatusIcon(),
                                    ],
                                    barColor:
                                        tokens.studioPalette.accentContainer,
                                    canvasTint: tokens.studioPalette.frameTint,
                                    onAutoLayout: () => _runAutoLayout(
                                      CanvasTab.architecture,
                                      _tabAxis[CanvasTab.architecture]!,
                                    ),
                                    onAddPrimitive: () =>
                                        _showPaletteSheet(context, ref),
                                    onClearCanvas: () async {
                                      if (!await _confirmClearCanvas(
                                        'model architecture',
                                      )) {
                                        return;
                                      }
                                      ref
                                          .read(canvasProvider.notifier)
                                          .clearArchitectureGraph();
                                      ref
                                          .read(nirImportProvider.notifier)
                                          .clearStateOnly();
                                      unawaited(
                                        ref
                                            .read(
                                              specTextControllerProvider
                                                  .notifier,
                                            )
                                            .set(''),
                                      );
                                    },
                                    onUndo: () => ref
                                        .read(canvasProvider.notifier)
                                        .undo(),
                                    onRedo: () => ref
                                        .read(canvasProvider.notifier)
                                        .redo(),
                                    canUndo: canUndo,
                                    canRedo: canRedo,
                                  );
                                },
                              ),
                            },
                          ),
                          if (effectiveShowProperties)
                            Positioned(
                              key: const ValueKey('canvas-inspector-dock'),
                              right: 12,
                              bottom:
                                  12 +
                                  utilityPanelHeight +
                                  (utilityPanelVisible ? 12 : 0),
                              child: _buildOverlayPanel(
                                width: _propertyWidth,
                                height: inspectorDockHeight,
                                title: 'Inspector',
                                subtitle: isArchitecture
                                    ? 'Edit node and connection parameters here.'
                                    : 'Edit the selected pipeline stage here.',
                                onHide: () =>
                                    setState(() => _showProperties = false),
                                onResize: (delta) => setState(() {
                                  _propertyWidth = (_propertyWidth - delta)
                                      .clamp(
                                        _minimumPanelWidth,
                                        _maximumPanelWidth,
                                      );
                                }),
                                resizeOnRight: false,
                                child: isArchitecture
                                    ? const PropertyPanel()
                                    : PipelineNodePropertyPanel(
                                        phase: phaseId!,
                                      ),
                              ),
                            ),
                          if (utilityPanelVisible)
                            Positioned(
                              key: const ValueKey(
                                'canvas-bottom-right-utility-dock',
                              ),
                              right: 12,
                              bottom: 12,
                              width: widget.bottomRightUtilityPanelWidth,
                              height: utilityPanelHeight,
                              child: Align(
                                alignment: Alignment.bottomRight,
                                child: widget.bottomRightUtilityPanel,
                              ),
                            ),
                          if (_showCnl && isArchitecture && !isMobile)
                            Positioned(
                              left: 0,
                              top: editorTop,
                              bottom: 0,
                              child: _buildOverlayPanel(
                                width: _cnlWidth,
                                title: 'CNL Editor',
                                subtitle: 'Edit canonical NeuroCNL directly.',
                                onHide: () => setState(() => _showCnl = false),
                                onResize: (delta) => setState(() {
                                  _cnlWidth = (_cnlWidth + delta).clamp(
                                    _minimumPanelWidth,
                                    _maximumPanelWidth,
                                  );
                                }),
                                resizeOnRight: true,
                                child: const CnlEditor(),
                              ),
                            ),
                          if (_showNir && isArchitecture && !isMobile)
                            Positioned(
                              right: 0,
                              top: editorTop,
                              bottom: 0,
                              child: _buildOverlayPanel(
                                width: _nirWidth,
                                title: 'NIR Importer',
                                subtitle: 'Sync with CNL editor and Canvas.',
                                onHide: () => setState(() => _showNir = false),
                                onResize: (delta) => setState(() {
                                  _nirWidth = (_nirWidth - delta).clamp(
                                    _minimumPanelWidth,
                                    _maximumPanelWidth,
                                  );
                                }),
                                resizeOnRight: false,
                                child: const NirImporterTab(),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    return canvasWidget;
  }

  Widget _buildOverlayPanel({
    required double width,
    double? height,
    required String title,
    required String subtitle,
    required VoidCallback onHide,
    required ValueChanged<double> onResize,
    required bool resizeOnRight,
    required Widget child,
  }) {
    final tokens = NmtkShellTokens.of(context);
    return SizedBox(
      width: width,
      height: height,
      child: Stack(
        children: [
          Positioned.fill(
            child: Material(
              elevation: 4,
              borderRadius: BorderRadius.circular(tokens.radiusLg),
              child: ShellPanel(
                title: title,
                subtitle: subtitle,
                onHide: onHide,
                borderRadius: BorderRadius.circular(tokens.radiusLg),
                child: child,
              ),
            ),
          ),
          // Resize drag handle on inner edge
          Positioned(
            top: 0,
            bottom: 0,
            left: resizeOnRight ? null : 0,
            right: resizeOnRight ? 0 : null,
            child: MouseRegion(
              cursor: SystemMouseCursors.resizeColumn,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onHorizontalDragUpdate: (d) => onResize(d.delta.dx),
                child: const SizedBox(width: 8),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _consumeInitialImport() async {
    if (_initialImportHandled) return;
    _initialImportHandled = true;

    final initialUri = widget.initialUri ?? Uri.base;
    final importContract = decodeImportedContract(initialUri);
    if (importContract != null) {
      ref
          .read(importedCnlSpecProvider.notifier)
          .setState(
            ImportedCnlSpec(
              content: importContract.cnlSpec,
              source: ImportedCnlSource.studioImport,
            ),
          );
      unawaited(ref.read(specTextProvider.notifier).set(importContract.cnlSpec));
      ref.read(canvasProvider.notifier).setGraph(importContract.graph);
      await ref
          .read(validationProvider.notifier)
          .validate(importContract.graph);
      if (!mounted) return;
      setState(() {
        _startupBannerIsError = false;
        _startupBannerMessage =
            'Imported a canonical CNL Studio contract and restored the canvas without local CNL interpretation.';
      });
      return;
    }

    final importedSpec = decodeImportedCnl(initialUri);
    if (importedSpec == null || importedSpec.trim().isEmpty) return;

    ref
        .read(importedCnlSpecProvider.notifier)
        .setState(
          ImportedCnlSpec(
            content: importedSpec,
            source: ImportedCnlSource.studioImport,
          ),
        );
    unawaited(ref.read(specTextProvider.notifier).set(importedSpec));

    try {
      final graph = await ref.read(apiClientProvider).repairCnl(importedSpec);
      ref.read(canvasProvider.notifier).setGraph(graph);
      await ref.read(validationProvider.notifier).validate(graph);
      if (!mounted) return;
      setState(() {
        _startupBannerIsError = false;
        _startupBannerMessage =
            'Imported a legacy raw CNL payload and repaired it into the canvas. Prefer canonical CNL Studio imports when available.';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _startupBannerIsError = true;
        _startupBannerMessage =
            'Could not repair the imported raw CNL payload into a canvas. Review the spec and use Repair + Sync after fixing it.';
      });
    }
  }

  Widget _buildStartupBanner(NmtkShellTokens tokens) {
    final theme = Theme.of(context);

    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: _startupBannerIsError
              ? theme.colorScheme.errorContainer
              : theme.colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(tokens.radiusMd),
          border: Border.all(
            color: _startupBannerIsError
                ? theme.colorScheme.error.withValues(alpha: 0.35)
                : theme.colorScheme.primary.withValues(alpha: 0.25),
          ),
        ),
        child: Row(
          children: [
            Expanded(child: Text(_startupBannerMessage!)),
            ZetaButton.text(
              onPressed: () {
                setState(() => _startupBannerMessage = null);
              },
              label: 'Dismiss',
            ),
          ],
        ),
      ),
    );
  }

  void _toggleInspector() {
    setState(() => _showProperties = !_showProperties);
  }

  void _openInspector() {
    if (widget.disableInspectorOverlay) return;
    if (!_showProperties) setState(() => _showProperties = true);
  }

  /// Mobile's replacement for the docked Inspector: a modal sheet showing
  /// the same [PropertyPanel]/[PipelineNodePropertyPanel] content the
  /// desktop dock shows, made scrollable for small screens.
  ///
  /// Both panels already render their own header (the node's real name +
  /// Delete + Close), so the sheet does not add a second one — an earlier
  /// version did, producing two title rows, two dividers, and two Delete
  /// buttons stacked on top of each other. The panel's own Close button
  /// already dismisses the sheet: it calls `selectNode(null)`, which the
  /// `ref.listen` above turns into `Navigator.maybePop()`.
  Future<void> _showMobileNodeSheet({
    required bool isArchitecture,
    required PipelinePhaseId? phaseId,
  }) async {
    setState(() => _mobileNodeSheetOpen = true);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        return DraggableScrollableSheet(
          initialChildSize: 0.55,
          minChildSize: 0.3,
          maxChildSize: 0.92,
          expand: false,
          builder: (context, scrollController) {
            return PrimaryScrollController(
              controller: scrollController,
              child: isArchitecture
                  ? const PropertyPanel()
                  : PipelineNodePropertyPanel(
                      phase: phaseId!,
                      showDockChrome: false,
                    ),
            );
          },
        );
      },
    );
    if (mounted) setState(() => _mobileNodeSheetOpen = false);
    // Deselecting whatever was still selected when the sheet closed (swipe
    // to dismiss, tap the scrim) keeps the canvas from showing a node as
    // selected with no way to see why — the sheet was the only mobile UI for
    // that state.
    if (mounted) ref.read(canvasProvider.notifier).clearSelection();
  }

  void _showPaletteSheet(BuildContext context, WidgetRef ref) {
    final types = ref.read(nirNodeTypesProvider);
    final isMobile =
        MediaQuery.sizeOf(context).width < NmtkShellTokens.compactBreakpoint;
    final TextEditingController searchController = TextEditingController();
    String query = '';

    void addType(NirNodeType type) {
      final CanvasState canvasState = ref.read(canvasProvider);
      final CanvasGraph graph = canvasState.graph;
      final int nodeCount = graph.nodes.length;
      final int nextIndex = nodeCount + 1;
      final String id = '${type.id}_${DateTime.now().millisecondsSinceEpoch}';

      final CanvasViewport viewport = canvasState.viewport;
      final double offset = (nodeCount % 10) * 30.0;
      final double posX = (200.0 - viewport.pan[0]) / viewport.zoom + offset;
      final double posY = (200.0 - viewport.pan[1]) / viewport.zoom + offset;

      ref
          .read(canvasProvider.notifier)
          .addNode(
            CanvasNode(
              id: id,
              componentId: type.legacyComponentId ?? type.id,
              nirType: type.isCustom ? type.baseNirType : type.id,
              label: type.displayName,
              parameters: <String, dynamic>{
                ...type.defaultParameters,
                'name': '${type.displayName} $nextIndex',
              },
              position: <double>[posX, posY],
              metadata: <String, dynamic>{'category': type.category},
            ),
            preferRight: !isMobile,
          );
    }

    Widget buildContent(BuildContext popupContext) {
      return StatefulBuilder(
        builder: (BuildContext ctx, void Function(void Function()) setSheet) {
          final List<NirNodeType> visible =
              filterCanvasPaletteItems<NirNodeType>(
                types,
                query,
                label: (NirNodeType t) => t.displayName,
                keywords: (NirNodeType t) => <String>[
                  t.id,
                  t.category,
                  for (final NirPortDef p in t.ports) p.label,
                ],
              );

          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Add NIR Primitive',
                  style: Theme.of(ctx).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                CanvasPaletteSearchField(
                  controller: searchController,
                  autofocus: !isMobile,
                  hintText: 'Search primitives…',
                  onChanged: (String value) => setSheet(() => query = value),
                  onSubmitted: () {
                    if (visible.isEmpty) return;
                    Navigator.of(popupContext).pop();
                    addType(visible.first);
                  },
                ),
                const SizedBox(height: 12),
                if (visible.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Text('No matching nodes'),
                  )
                else
                  GridView.count(
                    crossAxisCount: isMobile ? 4 : 5,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                    childAspectRatio: 0.85,
                    children: visible.map((NirNodeType type) {
                      return InkWell(
                        onTap: () {
                          Navigator.of(popupContext).pop();
                          addType(type);
                        },
                        borderRadius: BorderRadius.circular(NmtkShellTokens.of(context).radiusSm),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              type.icon,
                              size: 28,
                              color: nirCategoryColor(ctx, type.category),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              type.displayName,
                              textAlign: TextAlign.center,
                              style: Theme.of(ctx).textTheme.labelSmall
                                  ?.copyWith(
                                    color: Zeta.of(ctx).colors.mainDefault,
                                  ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
              ],
            ),
          );
        },
      );
    }

    final Future<void> shown = isMobile
        ? showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(NmtkShellTokens.of(context).radiusLg)),
            ),
            builder: (BuildContext sheetContext) {
              return SafeArea(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(sheetContext).size.height * 0.8,
                  ),
                  child: SingleChildScrollView(
                    child: buildContent(sheetContext),
                  ),
                ),
              );
            },
          )
        : showDialog<void>(
            context: context,
            builder: (BuildContext dialogContext) {
              return Dialog(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(NmtkShellTokens.of(context).radiusLg),
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: 500,
                    maxHeight: 600,
                  ),
                  child: SingleChildScrollView(
                    child: buildContent(dialogContext),
                  ),
                ),
              );
            },
          );

    shown.whenComplete(searchController.dispose);
  }

  Future<void> _showPipelinePaletteSheet(
    BuildContext context,
    WidgetRef ref,
    PipelinePhaseId phase,
  ) async {
    final platforms = ref.read(
      workspaceProvider.select((s) => s.selectedPlatforms),
    );

    // Saved custom components are a bonus, not a precondition: when the backend
    // is unreachable the fetch throws, and letting that propagate would mean the
    // Add-Node button silently does nothing. Fall back to the built-in types.
    List<ComponentBlock> components;
    try {
      components = await ref.read(componentsProvider.future);
    } catch (_) {
      components = const <ComponentBlock>[];
    }
    if (!context.mounted) return;
    final nodes = pipelinePaletteItems(
      phase: phase,
      platforms: platforms.toSet(),
      components: components,
    );

    final isMobile =
        MediaQuery.sizeOf(context).width < NmtkShellTokens.compactBreakpoint;
    final TextEditingController searchController = TextEditingController();
    String query = '';

    void addNodeType(PipelineNodePaletteItem item) {
      final nodeType = item.type;
      final id = '${item.id}_${DateTime.now().millisecondsSinceEpoch}';
      final dag = ref.read(canvasProvider).pipelinePhases.dagFor(phase);
      final int nodeCount = dag.nodes.length;
      final double offset = (nodeCount % 10) * 30.0;
      ref
          .read(canvasProvider.notifier)
          .addPipelineDagNode(
            phase,
            PipelineDagNode(
              id: id,
              type: nodeType,
              customComponentId: item.customComponentId,
              x: 200.0 + offset,
              y: 200.0 + offset,
              parameters: item.defaultParameters,
            ),
            preferRight: !isMobile,
          );
    }

    Widget buildContent(BuildContext popupContext) {
      return StatefulBuilder(
        builder: (BuildContext ctx, void Function(void Function()) setSheet) {
          final List<PipelineNodePaletteItem> visible =
              filterCanvasPaletteItems<PipelineNodePaletteItem>(
                nodes,
                query,
                label: (PipelineNodePaletteItem item) => item.label,
                keywords: (PipelineNodePaletteItem item) => <String>[
                  item.id,
                  item.type.name,
                  item.type.category.name,
                  for (final PortSpec p in item.type.inputPorts) p.id,
                  for (final PortSpec p in item.type.outputPorts) p.id,
                ],
              );

          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Add Node', style: Theme.of(ctx).textTheme.titleMedium),
                const SizedBox(height: 12),
                CanvasPaletteSearchField(
                  controller: searchController,
                  autofocus: !isMobile,
                  onChanged: (String value) => setSheet(() => query = value),
                  onSubmitted: () {
                    if (visible.isEmpty) return;
                    Navigator.of(popupContext).pop();
                    addNodeType(visible.first);
                  },
                ),
                const SizedBox(height: 12),
                if (visible.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Text('No matching nodes'),
                  )
                else
                  GridView.count(
                    crossAxisCount: isMobile ? 3 : 4,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                    childAspectRatio: 0.85,
                    children: visible.map((item) {
                      final nodeType = item.type;
                      final catColor = pipelineCategoryColor(nodeType.category);
                      return InkWell(
                        onTap: () {
                          Navigator.of(popupContext).pop();
                          addNodeType(item);
                        },
                        borderRadius: BorderRadius.circular(NmtkShellTokens.of(context).radiusSm),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              pipelineCategoryIcon(nodeType.category),
                              size: 28,
                              color: catColor,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              item.label,
                              textAlign: TextAlign.center,
                              style: Theme.of(ctx).textTheme.labelSmall
                                  ?.copyWith(
                                    color: Zeta.of(ctx).colors.mainDefault,
                                  ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
              ],
            ),
          );
        },
      );
    }

    final Future<void> shown = isMobile
        ? showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(NmtkShellTokens.of(context).radiusLg)),
            ),
            builder: (BuildContext sheetContext) {
              return SafeArea(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(sheetContext).size.height * 0.8,
                  ),
                  child: SingleChildScrollView(
                    child: buildContent(sheetContext),
                  ),
                ),
              );
            },
          )
        : showDialog<void>(
            context: context,
            builder: (BuildContext dialogContext) {
              return Dialog(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(NmtkShellTokens.of(context).radiusLg),
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: 500,
                    maxHeight: 600,
                  ),
                  child: SingleChildScrollView(
                    child: buildContent(dialogContext),
                  ),
                ),
              );
            },
          );

    unawaited(shown.whenComplete(searchController.dispose));
  }
}

// Pipeline category colour/icon tables live in theme/nir_node_styles.dart —
// they are shared with the node cards and the port-anchored connect palette.

class CanvasScreenHeaderActions extends ConsumerWidget {
  const CanvasScreenHeaderActions({
    super.key,
    required this.activeSection,
    required this.onOpenCanvas,
    required this.onOpenSimulation,
  });

  final NeuroSimNavSection activeSection;
  final VoidCallback onOpenCanvas;
  final VoidCallback onOpenSimulation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final simState = ref.watch(simulationProvider);
    final validationState = ref.watch(validationProvider);
    final previewStatus = _buildPreviewStatus(simState);
    final readinessStatus = _buildReadinessStatus(validationState, simState);

    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      runSpacing: 8,
      children: [
        ZetaButton.text(
          onPressed: onOpenCanvas,
          leadingIcon:
              Icons.hub_outlined, // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
          label: 'Canvas',
        ),
        ZetaButton.text(
          onPressed: onOpenSimulation,
          leadingIcon: Icons
              .insights_outlined, // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
          label: 'Simulation',
        ),
        NmtkShellStatusBadge(status: readinessStatus),
        NmtkShellStatusBadge(status: previewStatus),
      ],
    );
  }

  static NmtkShellStatusSpec _buildPreviewStatus(SimulationState simState) {
    return switch (simState.status) {
      SimulationStatus.connecting => const NmtkShellStatusSpec(
        label: 'Preview Streaming',
        tone: NmtkTone.info,
        icon: ZetaIcons.sync,
        detailText: 'Live preview data is streaming in.',
      ),
      SimulationStatus.running => const NmtkShellStatusSpec(
        label: 'Preview Playing',
        tone: NmtkTone.info,
        icon: ZetaIcons.play_circle,
        detailText: 'Playback is in progress.',
      ),
      SimulationStatus.paused => const NmtkShellStatusSpec(
        label: 'Preview Paused',
        tone: NmtkTone.neutral,
        icon: ZetaIcons.pause_circle,
        detailText: 'Preview data is loaded and paused.',
      ),
      SimulationStatus.completed => const NmtkShellStatusSpec(
        label: 'Preview Ready',
        tone: NmtkTone.success,
        icon: Icons.insights, // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
        detailText: 'Preview results are available.',
      ),
      SimulationStatus.error => NmtkShellStatusSpec(
        label: 'Preview Error',
        tone: NmtkTone.danger,
        icon: ZetaIcons.error_outline,
        detailText: simState.error ?? 'Preview failed to complete.',
      ),
      SimulationStatus.idle => const NmtkShellStatusSpec(
        label: 'Preview Idle',
        tone: NmtkTone.neutral,
        icon: ZetaIcons.pause_circle,
        detailText: 'Preview has not started.',
      ),
    };
  }

  static NmtkShellStatusSpec _buildReadinessStatus(
    AsyncValue<dynamic> validationState,
    SimulationState simState,
  ) {
    if (validationState is AsyncError) {
      return const NmtkShellStatusSpec(
        label: 'Shell Error',
        tone: NmtkTone.danger,
        icon: ZetaIcons.error_outline,
        detailText: 'Validation state failed to load.',
      );
    }
    if (validationState is AsyncLoading) {
      return const NmtkShellStatusSpec(
        label: 'Warming',
        tone: NmtkTone.warning,
        icon: Icons
            .hourglass_top_rounded, // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
        detailText: 'Module services are still warming up.',
      );
    }
    if (simState.status == SimulationStatus.error) {
      return const NmtkShellStatusSpec(
        label: 'Degraded',
        tone: NmtkTone.warning,
        icon: ZetaIcons.warning_outline,
        detailText: 'The shell is available, but preview is degraded.',
      );
    }
    return const NmtkShellStatusSpec(
      label: 'Ready',
      tone: NmtkTone.success,
      icon: ZetaIcons.check_circle_outline,
      detailText: 'Canvas editing is ready.',
    );
  }
}
