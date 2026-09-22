import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:neuro_toolkit/features/neurocnl/models/canonical_editor_document.dart'
    as canonical_doc;
import 'package:neuro_toolkit/features/neurocnl/models/canvas/canvas.dart';
import 'package:neuro_toolkit/features/neurocnl/models/canvas/canvas_clipboard.dart';
import 'package:neuro_toolkit/features/neurocnl/models/canvas/grid.dart';
import 'package:neuro_toolkit/features/neurocnl/models/canvas/node_geometry.dart';
import 'package:neuro_toolkit/features/neurocnl/models/canvas/pipeline_config.dart';
import 'package:neuro_toolkit/features/neurocnl/models/canvas/pipeline_dag.dart';
import 'package:neuro_toolkit/features/neurocnl/utils/canvas_projection_utils.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/canonical_doc_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/canvas/validation_provider.dart';

part 'canvas_provider.g.dart';

/// A node's UI-local layout — not part of the canonical document. See
/// [CanvasController._layoutOverrides].
typedef _NodeLayout = ({
  double x,
  double y,
  double width,
  double height,
  bool isVisible,
});

/// Which top-level tab is active on the Canvas screen.
enum CanvasTab { architecture, pipelineTrain, pipelineEval, pipelineOverview }

extension CanvasTabX on CanvasTab {
  bool get isPipeline => this != CanvasTab.architecture;

  bool get isPhaseCanvas =>
      this == CanvasTab.pipelineTrain || this == CanvasTab.pipelineEval;

  PipelinePhaseId? get phaseId => switch (this) {
    CanvasTab.pipelineTrain => PipelinePhaseId.train,
    CanvasTab.pipelineEval => PipelinePhaseId.eval,
    _ => null,
  };

  String get label => switch (this) {
    CanvasTab.architecture => 'Model',
    CanvasTab.pipelineOverview => 'Overview',
    CanvasTab.pipelineTrain => 'Train',
    CanvasTab.pipelineEval => 'Eval',
  };
}

class CanvasState {
  /// Architecture graph — serialises to CNL.
  final CanvasGraph graph;

  /// Pipeline tab configuration — serialises to training_config.json.
  final PipelineConfig pipeline;

  /// Which canvas tab is currently active.
  final CanvasTab activeTab;

  /// Pipeline DAG phases — node/edge data for each pipeline phase canvas.
  final PipelinePhases pipelinePhases;

  final Set<String> selectedNodeIds;
  final String? selectedEdgeId;
  final String? connectingFromNodeId;
  final String? connectingFromPortId;
  final bool canUndo;
  final bool canRedo;

  /// Id of a node that was just added and whose canvas should animate its
  /// viewport to center on it. Set by [CanvasController.addNode] /
  /// [CanvasController.addPipelineDagNode]; the owning canvas widget clears it
  /// via [CanvasController.clearPendingViewportFocusNodeId] once it has
  /// consumed the pan. A transient UI signal, not a durable selection.
  final String? pendingViewportFocusNodeId;

  /// Pan/zoom of the architecture canvas. Deliberately a field on the *state*
  /// rather than inside `graph.metadata`: moving the camera is not an edit to
  /// the document. Keeping it in the graph meant every pan frame minted a new
  /// CanvasGraph, and since CanvasGraph compares by identity that invalidated
  /// every `select((s) => s.graph)` in the app — rebuilding the whole canvas
  /// per frame and tripping the workspace autosave listener.
  /// ponytail: view state, never persisted — a fresh session opens at the
  /// default camera, which is what it already did (nothing wrote zoom/pan to
  /// disk even when it lived in the graph).
  final CanvasViewport viewport;

  /// Monotonically increasing, session-only signal emitted once a workspace
  /// payload is fully restored. Each canvas consumes it after layout to place
  /// its first node inside the usable viewport.
  final int workspaceRestoreFocusRevision;

  String? get primarySelectedNodeId => selectedNodeIds.length == 1
      ? selectedNodeIds.first
      : selectedNodeIds.isEmpty
      ? null
      : selectedNodeIds.first;

  /// Backward-compatible single-selection accessor.
  String? get selectedNodeId => primarySelectedNodeId;

  /// [graph] with the live [viewport] folded back into its metadata — the shape
  /// a saved project stores. Use this at serialization boundaries only (project
  /// save); everywhere else read [graph], whose identity must stay stable
  /// across pans.
  CanvasGraph get graphForPersistence =>
      graph.copyWith(metadata: viewport.applyToMetadata(graph.metadata));

  CanvasState({
    required this.graph,
    this.pipeline = const PipelineConfig(),
    this.activeTab = CanvasTab.architecture,
    this.pipelinePhases = const PipelinePhases(),
    Set<String>? selectedNodeIds,
    this.selectedEdgeId,
    this.connectingFromNodeId,
    this.connectingFromPortId,
    this.canUndo = false,
    this.canRedo = false,
    this.pendingViewportFocusNodeId,
    this.viewport = CanvasViewport.defaults,
    this.workspaceRestoreFocusRevision = 0,
  }) : selectedNodeIds = selectedNodeIds ?? const <String>{};

  CanvasState copyWith({
    CanvasGraph? graph,
    PipelineConfig? pipeline,
    CanvasTab? activeTab,
    PipelinePhases? pipelinePhases,
    CanvasViewport? viewport,
    Set<String>? selectedNodeIds,
    bool clearSelectedNodeIds = false,
    String? selectedEdgeId,
    bool clearSelectedEdgeId = false,
    String? connectingFromNodeId,
    bool clearConnectingFromNodeId = false,
    String? connectingFromPortId,
    bool clearConnectingFromPortId = false,
    bool? canUndo,
    bool? canRedo,
    String? pendingViewportFocusNodeId,
    bool clearPendingViewportFocusNodeId = false,
    int? workspaceRestoreFocusRevision,
  }) {
    return CanvasState(
      graph: graph ?? this.graph,
      pipeline: pipeline ?? this.pipeline,
      activeTab: activeTab ?? this.activeTab,
      pipelinePhases: pipelinePhases ?? this.pipelinePhases,
      viewport: viewport ?? this.viewport,
      selectedNodeIds: clearSelectedNodeIds
          ? const <String>{}
          : (selectedNodeIds ?? this.selectedNodeIds),
      selectedEdgeId: clearSelectedEdgeId
          ? null
          : (selectedEdgeId ?? this.selectedEdgeId),
      connectingFromNodeId: clearConnectingFromNodeId
          ? null
          : (connectingFromNodeId ?? this.connectingFromNodeId),
      connectingFromPortId: clearConnectingFromPortId
          ? null
          : (connectingFromPortId ?? this.connectingFromPortId),
      canUndo: canUndo ?? this.canUndo,
      canRedo: canRedo ?? this.canRedo,
      pendingViewportFocusNodeId: clearPendingViewportFocusNodeId
          ? null
          : (pendingViewportFocusNodeId ?? this.pendingViewportFocusNodeId),
      workspaceRestoreFocusRevision:
          workspaceRestoreFocusRevision ?? this.workspaceRestoreFocusRevision,
    );
  }
}

// keepAlive: true — this controller owns a debounce Timer for param edits
// (_pushToCanonical(debounce: true)). Pre-existing risk found while fixing
// the sibling CanonicalDocController bug: an autoDispose controller with a
// live Timer can be torn down (cancelling the timer in ref.onDispose) the
// moment its last listener unsubscribes, silently dropping a pending edit.
@Riverpod(keepAlive: true)
class CanvasController extends _$CanvasController {
  Timer? _debounceTimer;

  // Number of canvas→canonical pushes currently in flight. A counter, not a
  // bool: with overlapping pushes (edit A starts a push, edit B starts a
  // second one, then A's future resolves) a bool would clear while B was
  // still running, letting B's response mirror back over the newer local
  // graph and snap freshly-edited parameters to whatever the backend
  // normalised them to.
  int _pendingPushes = 0;

  // Undo/redo history stacks — graph snapshots only.
  final List<CanvasGraph> _undoStack = [];
  final List<CanvasGraph> _redoStack = [];
  CanvasClipboardPayload? _inMemoryClipboard;

  // "Start Fresh" is an explicit request for blank workflow canvases, not
  // the starter Train/Eval DAGs normally seeded when a pipeline tab first
  // opens. Kept on the controller rather than in persisted CanvasState: it is
  // a session-only initialization policy, and loading a workspace re-enables
  // normal default initialization.
  bool _suppressDefaultPhaseInitialization = false;

  // Position/size/visibility are "UI-local" — the canonical document has no
  // fields for them (changing that would touch NIR graph shape, a
  // downstream-consumer-reviewed contract per neurocnl/AGENTS.md), so they
  // never round-trip through canvasGraphFromCanonical. This map is the local
  // source of truth for layout, re-applied onto every freshly-mirrored graph
  // (see _mirrorProjection) so an external canonical write (NIR import,
  // template load, reload-and-restore) can't silently reset a node's
  // width/height/visibility to their model defaults, and so restored layout
  // from local storage survives future mirrors too.
  final Map<String, _NodeLayout> _layoutOverrides = {};

  static const int _kMaxHistoryDepth = 50;

  @override
  CanvasState build() {
    ref.onDispose(() {
      _debounceTimer?.cancel();
    });

    // Mirror the canvas projection from canonicalDocProvider — the sole
    // source of canvas content. Fires on every canonical doc change,
    // including a file switch (CanonicalDocController re-seeds its state
    // from the newly-active file's canonicalDocument).
    // ponytail: skip when canvas just pushed — avoids redundant self-mirror
    // and prevents state fights when the backend normalises parameters.
    ref.listen<AsyncValue<canonical_doc.CanonicalEditorDocument?>>(
      canonicalDocProvider,
      (prev, next) {
        if (_pendingPushes > 0) return;
        // A mutation in flight publishes a bare `AsyncLoading()` with no
        // previous value, so `next.value` is null. That is "not loaded yet",
        // NOT "the document is empty" — mirroring it would blank the canvas
        // and repopulate a moment later, which is what made node values
        // visibly flash back to their defaults on every CNL keystroke.
        if (next.isLoading) return;
        final projection = next.value?.canvas;
        if (projection == null || projection.nodes.isEmpty) {
          _publishGraph(
            _normalizeGraph(
              CanvasGraph(nodes: [], edges: [], metadata: const {}),
            ),
          );
          return;
        }
        _mirrorProjection(projection);
      },
    );

    // Build initial state.
    final empty = CanvasState(
      graph: _normalizeGraph(
        CanvasGraph(nodes: [], edges: [], metadata: const {}),
      ),
    );

    final currentProjection = ref.read(canonicalDocProvider).value?.canvas;
    if (currentProjection != null && currentProjection.nodes.isNotEmpty) {
      final seeded = canvasGraphFromCanonical(
        currentProjection,
        currentGraph: empty.graph,
      );
      final normalizedSeeded = _normalizeGraph(seeded);
      // Schedule validation after build is complete.
      Future.microtask(() {
        if (!ref.mounted) return;
        ref.read(validationControllerProvider.notifier).validate(seeded);
      });
      return empty.copyWith(graph: normalizedSeeded);
    }

    return empty;
  }

  // ---------------------------------------------------------------------------
  // Internal helpers
  // ---------------------------------------------------------------------------

  static CanvasGraph _normalizeGraph(
    CanvasGraph graph, {
    bool snapNodes = true,
  }) {
    // No viewport normalisation here any more — pan/zoom lives on
    // CanvasState.viewport, not in graph.metadata.
    if (!snapNodes || graph.nodes.isEmpty) {
      return graph;
    }
    return graph.copyWith(nodes: _snapNodesToGrid(graph.nodes));
  }

  static String _graphSignature(CanvasGraph? graph, {bool snapNodes = true}) {
    final normalized = _normalizeGraph(
      graph ?? CanvasGraph(nodes: [], edges: [], metadata: const {}),
      snapNodes: snapNodes,
    );
    return jsonEncode(normalized.toJson());
  }

  CanvasState _buildFromWorkspaceGraph(
    CanvasGraph? graph,
    CanvasState current, {
    bool snapNodes = true,
  }) {
    final nextGraph = _normalizeGraph(
      graph ?? CanvasGraph(nodes: [], edges: [], metadata: const {}),
      snapNodes: snapNodes,
    );
    final preservedSelection = current.selectedNodeIds
        .where((id) => nextGraph.nodes.any((node) => node.id == id))
        .toSet();
    final selectedEdgeId =
        current.selectedEdgeId != null &&
            nextGraph.edges.any((edge) => edge.id == current.selectedEdgeId)
        ? current.selectedEdgeId
        : null;
    final connectingFromNodeId =
        current.connectingFromNodeId != null &&
            nextGraph.nodes.any(
              (node) => node.id == current.connectingFromNodeId,
            )
        ? current.connectingFromNodeId
        : null;

    return current.copyWith(
      graph: nextGraph,
      selectedNodeIds: preservedSelection,
      clearSelectedNodeIds: preservedSelection.isEmpty,
      selectedEdgeId: selectedEdgeId,
      clearSelectedEdgeId: selectedEdgeId == null,
      connectingFromNodeId: connectingFromNodeId,
      clearConnectingFromNodeId: connectingFromNodeId == null,
      connectingFromPortId: connectingFromNodeId == null
          ? null
          : current.connectingFromPortId,
      clearConnectingFromPortId: connectingFromNodeId == null,
    );
  }

  void _publishGraph(CanvasGraph graph, {bool snapNodes = true}) {
    final normalized = _normalizeGraph(graph, snapNodes: snapNodes);

    // Check if the graph actually changed structurally to avoid loops
    final nextSignature = _graphSignature(normalized, snapNodes: false);
    final currentSignature = _graphSignature(state.graph, snapNodes: false);
    if (nextSignature == currentSignature) {
      return;
    }

    state = _buildFromWorkspaceGraph(normalized, state, snapNodes: snapNodes);
  }

  void _mirrorProjection(canonical_doc.CanvasProjection projection) {
    final newGraph = _applyLayoutOverrides(
      canvasGraphFromCanonical(projection, currentGraph: state.graph),
    );
    // A canonical mirror may immediately follow a workspace restore. Preserve
    // the already-applied signed layout rather than re-snapping it on that
    // asynchronous pass.
    _publishGraph(newGraph, snapNodes: false);
    ref.read(validationControllerProvider.notifier).validate(newGraph);
  }

  /// Forces a re-mirror of the graph from the current [canonicalDocProvider]
  /// projection, bypassing `_pendingPushes`. Needed after a workspace
  /// file load: `replaceFromWorkspacePayload` swaps in a brand-new canonical
  /// document, but if a debounced canvas edit was still pushing to the
  /// canonical doc when the load landed, the regular `ref.listen` mirror in
  /// [build] silently skips itself (see `_pendingPushes` above) and the
  /// graph is left showing its stale, pre-load nodes/edges. Call this right
  /// after the workspace payload is applied so the loaded graph always wins.
  void resyncFromCanonicalDocument() {
    _debounceTimer?.cancel();
    _pendingPushes = 0;
    final projection = ref.read(canonicalDocProvider).value?.canvas;
    debugPrint(
      'resyncFromCanonicalDocument: projection has '
      '${projection?.nodes.length ?? 0} nodes / '
      '${projection?.edges.length ?? 0} edges',
    );
    if (projection == null || projection.nodes.isEmpty) {
      _publishGraph(
        _normalizeGraph(CanvasGraph(nodes: [], edges: [], metadata: const {})),
      );
      return;
    }
    _mirrorProjection(projection);
    debugPrint(
      'resyncFromCanonicalDocument: graph now has '
      '${state.graph.nodes.length} nodes / ${state.graph.edges.length} edges',
    );
  }

  /// Clears stale per-node layout overrides (position/size/visibility) left
  /// over from before a workspace load, so a newly-loaded node id can never
  /// be silently overridden by leftover data from a previously-open file.
  void resetLayoutOverrides() {
    _layoutOverrides.clear();
  }

  /// Re-applies [_layoutOverrides] onto [graph] — canvasGraphFromCanonical
  /// never carries width/height/isVisible forward from the existing node
  /// (the canonical document has no such fields), so any mirror of an
  /// externally-changed canonical doc would otherwise silently reset them.
  CanvasGraph _applyLayoutOverrides(CanvasGraph graph) {
    if (_layoutOverrides.isEmpty) return graph;
    return graph.copyWith(
      nodes: [
        for (final node in graph.nodes)
          if (_layoutOverrides[node.id] case final layout?)
            node.copyWith(
              position: <double>[layout.x, layout.y],
              width: layout.width,
              height: layout.height,
              isVisible: layout.isVisible,
            )
          else
            node,
      ],
    );
  }

  void _recordLayout(CanvasNode node) {
    _layoutOverrides[node.id] = (
      x: node.position[0],
      y: node.position[1],
      width: node.width,
      height: node.height,
      isVisible: node.isVisible,
    );
  }

  /// Restores previously-saved node layout (position/size/visibility) from
  /// the JSON shape written by `_buildCanvasSection` in
  /// workspace_file_io.dart — that's where this data actually gets
  /// persisted, since the canonical document/workspace file has no room for
  /// it. Seeds [_layoutOverrides] so later mirrors keep honoring it, and
  /// applies it to the current graph immediately. Malformed entries are
  /// skipped rather than thrown, matching the tolerant-restore behavior of
  /// the rest of `_restoreCanvasFromPayload`.
  void applyNodeLayout(Map<String, dynamic> layoutByNodeId) {
    if (layoutByNodeId.isEmpty) return;
    for (final entry in layoutByNodeId.entries) {
      final raw = entry.value;
      if (raw is! Map) continue;
      final x = raw['x'], y = raw['y'];
      final width = raw['width'], height = raw['height'];
      final isVisible = raw['isVisible'];
      if (x is! num ||
          y is! num ||
          width is! num ||
          height is! num ||
          isVisible is! bool) {
        continue;
      }
      _layoutOverrides[entry.key] = (
        x: x.toDouble(),
        y: y.toDouble(),
        width: width.toDouble(),
        height: height.toDouble(),
        isVisible: isVisible,
      );
    }
    // Workspace layout is already persisted scene data. In particular it may
    // contain negative coordinates, so restoring it must not run add/drop
    // snapping again.
    _publishGraph(_applyLayoutOverrides(state.graph), snapNodes: false);
  }

  void _pushToCanonical({bool debounce = false}) {
    if (debounce) {
      _debounceTimer?.cancel();
      _debounceTimer = Timer(const Duration(milliseconds: 300), _doPush);
    } else {
      _debounceTimer?.cancel();
      _doPush();
    }
  }

  void _doPush() {
    final graph = state.graph;
    _pendingPushes++;
    ref
        .read(canonicalDocControllerProvider.notifier)
        .updateFromCanvas(graph)
        .whenComplete(() {
          if (_pendingPushes > 0) _pendingPushes--;
        });
    ref.read(validationControllerProvider.notifier).validate(graph);
  }

  // ---------------------------------------------------------------------------
  // Public API — undo/redo
  // ---------------------------------------------------------------------------

  /// Capture the current graph into the undo stack before a user-initiated
  /// mutation.  Clears the redo stack — branching history is not supported.
  void _pushUndoHistory() {
    _undoStack.add(state.graph);
    if (_undoStack.length > _kMaxHistoryDepth) _undoStack.removeAt(0);
    _redoStack.clear();
  }

  void undo() {
    if (_undoStack.isEmpty) return;
    _redoStack.add(state.graph);
    final prev = _undoStack.removeLast();
    _publishGraph(prev);
    state = state.copyWith(canUndo: _undoStack.isNotEmpty, canRedo: true);
  }

  void redo() {
    if (_redoStack.isEmpty) return;
    _undoStack.add(state.graph);
    final next = _redoStack.removeLast();
    _publishGraph(next);
    state = state.copyWith(canUndo: true, canRedo: _redoStack.isNotEmpty);
  }

  // ---------------------------------------------------------------------------
  // Public API — graph load
  // ---------------------------------------------------------------------------

  /// Set graph without triggering a backend sync.
  void setGraph(CanvasGraph graph) {
    _publishGraph(graph);
    _hydrateViewportFrom(graph);
  }

  /// Load a project graph and trigger upstream sync.
  void loadProjectGraph(CanvasGraph graph) {
    _publishGraph(graph);
    _hydrateViewportFrom(graph);
    _pushToCanonical();
  }

  /// Seeds [CanvasState.viewport] from a graph arriving from *outside* (a saved
  /// project). Only at these load boundaries, never in [_publishGraph]: an
  /// ordinary edit's metadata carries no zoom/pan, so hydrating there would
  /// snap the camera back to defaults on every keystroke.
  /// Paired with [CanvasState.graphForPersistence] on the way out.
  void _hydrateViewportFrom(CanvasGraph graph) {
    state = state.copyWith(
      viewport: CanvasViewport.fromMetadata(graph.metadata),
    );
  }

  // ---------------------------------------------------------------------------
  // Public API — pipeline tab
  // ---------------------------------------------------------------------------

  /// Switch between the Architecture and Pipeline canvas tabs.
  void setActiveTab(CanvasTab tab) {
    if (state.activeTab == tab) return;
    state = state.copyWith(activeTab: tab);
  }

  /// Update one or more fields of the [PipelineConfig] (Pipeline tab).
  ///
  /// Accepts a [PipelineConfig] produced via [PipelineConfig.copyWith] and
  /// writes it back to state. This is the only write path for pipeline config;
  /// it never touches [CanvasState.graph] or CNL.
  void updatePipeline(PipelineConfig config) {
    state = state.copyWith(pipeline: config);
  }

  /// Replace the Pipeline tab's config and DAGs wholesale — used when
  /// restoring a saved workspace file. Never touches [CanvasState.graph].
  void restorePipelineState({
    required PipelineConfig pipeline,
    required PipelinePhases pipelinePhases,
  }) {
    _suppressDefaultPhaseInitialization = false;
    // Loaded positions are never trusted as-is -- mirrors _publishGraph's
    // default snapNodes:true for the architecture graph.
    var snapped = pipelinePhases;
    for (final phase in PipelinePhaseId.values) {
      snapped = _snapDagPhaseToGrid(snapped, phase);
    }
    state = state.copyWith(pipeline: pipeline, pipelinePhases: snapped);
  }

  /// Mirrors [_referenceNodeForAdd] for a pipeline phase DAG -- the single
  /// selected node if there is exactly one, else the most recently added
  /// node in [dag], else null (empty DAG -- falls back to nearest-free-cell
  /// placement).
  PipelineDagNode? _referenceDagNodeForAdd(PipelineDAG dag) {
    if (dag.nodes.isEmpty) return null;
    if (state.selectedNodeIds.length == 1) {
      final PipelineDagNode? selected = _firstWhereOrNullDag(
        dag.nodes,
        state.selectedNodeIds.first,
      );
      if (selected != null) return selected;
    }
    return dag.nodes.last;
  }

  void addPipelineDagNode(
    PipelinePhaseId phase,
    PipelineDagNode node, {
    bool preferRight = true,
  }) {
    final dag = state.pipelinePhases.dagFor(phase);
    final Set<GridCoord> occupied = _dagOccupiedCells(dag);
    final PipelineDagNode? reference = _referenceDagNodeForAdd(dag);
    final PipelineDagNode snappedNode;
    if (reference == null) {
      snappedNode = _snapDagNodeToFreeCell(node, occupied);
    } else {
      final GridCoord cell = findNextCellRightOrBelow(
        _dagNodeGridCoord(reference),
        occupied,
        preferRight: preferRight,
      );
      final Offset topLeft = gridCoordToCenteredOffset(
        cell,
        nodeWidth: kPipelineDagNodeWidth,
        nodeHeight: pipelineDagNodeHeightFor(node),
      );
      snappedNode = node.copyWith(x: topLeft.dx, y: topLeft.dy);
    }
    final updated = dag.copyWithNode(snappedNode);
    state = state.copyWith(
      pipelinePhases: _phasesWithUpdated(phase, updated),
      selectedNodeIds: {snappedNode.id},
      clearSelectedEdgeId: true,
      pendingViewportFocusNodeId: snappedNode.id,
    );
  }

  void removePipelineDagNode(PipelinePhaseId phase, String nodeId) {
    removePipelineDagNodes(phase, {nodeId});
  }

  void removePipelineDagNodes(PipelinePhaseId phase, Iterable<String> nodeIds) {
    var dag = state.pipelinePhases.dagFor(phase);
    for (final String nodeId in nodeIds) {
      dag = dag.withoutNode(nodeId);
    }
    state = state.copyWith(
      pipelinePhases: _phasesWithUpdated(phase, dag),
      clearSelectedNodeIds: true,
    );
  }

  void addPipelineDagEdge(PipelinePhaseId phase, PipelineDagEdge edge) {
    final updated = state.pipelinePhases.dagFor(phase).copyWithEdge(edge);
    state = state.copyWith(pipelinePhases: _phasesWithUpdated(phase, updated));
  }

  void removePipelineDagEdge(PipelinePhaseId phase, String edgeId) {
    final updated = state.pipelinePhases.dagFor(phase).withoutEdge(edgeId);
    state = state.copyWith(
      pipelinePhases: _phasesWithUpdated(phase, updated),
      clearSelectedEdgeId: true,
    );
  }

  void movePipelineDagNode(
    PipelinePhaseId phase,
    String nodeId,
    double dx,
    double dy,
  ) {
    final updated = state.pipelinePhases
        .dagFor(phase)
        .movedNode(nodeId, dx, dy);
    state = state.copyWith(pipelinePhases: _phasesWithUpdated(phase, updated));
  }

  void updatePipelineDagNodeParams(
    PipelinePhaseId phase,
    String nodeId,
    Map<String, dynamic> params,
  ) {
    final dag = state.pipelinePhases.dagFor(phase);
    final node = dag.nodes.firstWhere((n) => n.id == nodeId);
    final merged = {...node.parameters, ...params};
    final updated = dag.copyWithNode(node.copyWith(parameters: merged));
    state = state.copyWith(pipelinePhases: _phasesWithUpdated(phase, updated));
  }

  /// Rebinds a training/evaluation instance to a stable custom component while
  /// retaining the built-in pipeline type that defines topology and fallback
  /// notebook behavior.
  void replacePipelineDagNodeComponent(
    PipelinePhaseId phase,
    String nodeId,
    String componentId,
  ) {
    final dag = state.pipelinePhases.dagFor(phase);
    final node = dag.nodes.firstWhere((candidate) => candidate.id == nodeId);
    final updated = dag.copyWithNode(
      node.copyWith(customComponentId: componentId),
    );
    state = state.copyWith(pipelinePhases: _phasesWithUpdated(phase, updated));
  }

  void initDefaultPhases({
    required List<String> frameworks,
    required String? dataset,
  }) {
    if (_suppressDefaultPhaseInitialization) return;
    if (state.pipelinePhases.train.nodes.isNotEmpty) return;
    var defaults = buildDefaultPhases(frameworks: frameworks, dataset: dataset);
    for (final phase in PipelinePhaseId.values) {
      defaults = _snapDagPhaseToGrid(defaults, phase);
    }
    state = state.copyWith(pipelinePhases: defaults);
  }

  /// Resets the pipeline portion of the Studio to a genuinely blank slate.
  ///
  /// The architecture graph is owned by the fresh workspace/canonical
  /// document flow, so it is intentionally preserved here. Automatic starter
  /// DAG initialization stays disabled for the rest of this fresh session;
  /// an explicit workspace restore re-enables it in [restorePipelineState].
  void resetPipelineForFreshSession() {
    _suppressDefaultPhaseInitialization = true;
    state = CanvasState(
      graph: state.graph,
      pipeline: const PipelineConfig(),
      activeTab: CanvasTab.architecture,
      pipelinePhases: const PipelinePhases(),
      viewport: state.viewport,
    );
  }

  PipelinePhases _phasesWithUpdated(PipelinePhaseId phase, PipelineDAG dag) =>
      state.pipelinePhases.copyWith(
        train: phase == PipelinePhaseId.train ? dag : null,
        eval: phase == PipelinePhaseId.eval ? dag : null,
        infer: phase == PipelinePhaseId.infer ? dag : null,
      );

  void restoreSelection({
    Set<String>? selectedNodeIds,
    String? selectedEdgeId,
  }) {
    state = state.copyWith(
      selectedNodeIds: selectedNodeIds,
      clearSelectedNodeIds: selectedNodeIds == null || selectedNodeIds.isEmpty,
      selectedEdgeId: selectedEdgeId,
      clearSelectedEdgeId: selectedEdgeId == null,
    );
  }

  void resetGraph() {
    _publishGraph(CanvasGraph(nodes: [], edges: [], metadata: const {}));
    ref.read(canonicalDocControllerProvider.notifier).clear();
  }

  void clearArchitectureGraph() {
    _pushUndoHistory();
    _publishGraph(CanvasGraph(nodes: [], edges: [], metadata: const {}));
    state = state.copyWith(
      clearSelectedNodeIds: true,
      clearSelectedEdgeId: true,
      canUndo: true,
      canRedo: false,
    );
    ref.read(canonicalDocControllerProvider.notifier).clear();
  }

  void clearPipelinePhase(PipelinePhaseId phase) {
    state = state.copyWith(
      pipelinePhases: _phasesWithUpdated(
        phase,
        const PipelineDAG(nodes: [], edges: []),
      ),
      clearSelectedNodeIds: true,
      clearSelectedEdgeId: true,
    );
  }

  void loadDemoReflexArc() {
    const sensoryId = 'sensory';
    const motorId = 'motor';

    final nodes = <CanvasNode>[
      CanvasNode(
        id: sensoryId,
        componentId: 'lif_population',
        nirType: 'nir.LIF',
        label: 'Sensory',
        parameters: const <String, dynamic>{
          'name': 'sensory',
          'n_neurons': 50,
          'threshold': 1.0,
          'tau_rc': 0.02,
          'tau_ref': 0.002,
        },
        position: const <double>[120.0, 200.0],
        metadata: const <String, dynamic>{'category': 'neuron'},
      ),
      CanvasNode(
        id: motorId,
        componentId: 'lif_population',
        nirType: 'nir.LIF',
        label: 'Motor',
        parameters: const <String, dynamic>{
          'name': 'motor',
          'n_neurons': 50,
          'threshold': 1.0,
          'tau_rc': 0.02,
          'tau_ref': 0.002,
        },
        position: const <double>[480.0, 200.0],
        metadata: const <String, dynamic>{'category': 'neuron'},
      ),
    ];

    final edges = <CanvasEdge>[
      CanvasEdge(
        id: 'edge_0',
        sourceNodeId: sensoryId,
        sourcePort: 'out',
        targetNodeId: motorId,
        targetPort: 'in',
        parameters: const <String, dynamic>{
          'synapse_type': 'static_synapse',
          'weight': 1.0,
          'delay': 0.001,
        },
      ),
    ];

    _publishGraph(state.graph.copyWith(nodes: nodes, edges: edges));
    _pushToCanonical();
  }

  // ---------------------------------------------------------------------------
  // Public API — viewport (UI-local, no upstream sync)
  // ---------------------------------------------------------------------------

  void updateViewport({required double zoom, required List<double> pan}) {
    final nextViewport = CanvasViewport(zoom: zoom, pan: [pan[0], pan[1]]);
    if (state.viewport.isCloseTo(nextViewport)) return;
    // Only `viewport` changes — `graph` keeps its identity so nothing that
    // watches the document rebuilds or autosaves. See CanvasState.viewport.
    state = state.copyWith(viewport: nextViewport);
  }

  void resetViewport() {
    updateViewport(
      zoom: CanvasViewport.defaults.zoom,
      pan: CanvasViewport.defaults.pan,
    );
  }

  /// Clears stale interaction state and asks each canvas to establish its
  /// first-node safe focus after a workspace payload has finished restoring.
  /// This deliberately does not touch graph metadata, so project camera
  /// persistence remains separate from workspace-open behaviour.
  void requestWorkspaceRestoreFocus() {
    _debounceTimer?.cancel();
    state = state.copyWith(
      viewport: CanvasViewport.defaults,
      clearSelectedNodeIds: true,
      clearSelectedEdgeId: true,
      clearConnectingFromNodeId: true,
      clearConnectingFromPortId: true,
      clearPendingViewportFocusNodeId: true,
      workspaceRestoreFocusRevision: state.workspaceRestoreFocusRevision + 1,
    );
  }

  // ---------------------------------------------------------------------------
  // Public API — structural mutations (trigger upstream sync)
  // ---------------------------------------------------------------------------

  /// Cells currently owned by [state.graph.nodes], excluding [excludingId] if
  /// given — used to find a free grid cell for a spawn or a drag-release.
  Set<GridCoord> _occupiedCells({String? excludingId}) {
    return state.graph.nodes
        .where((CanvasNode n) => n.id != excludingId)
        .map((CanvasNode n) => _nodeGridCoord(n))
        .toSet();
  }

  static GridCoord _nodeGridCoord(CanvasNode node) {
    return centerToGridCoord(_nodeCenter(node));
  }

  static Offset _nodeCenter(CanvasNode node) {
    return Offset(
      node.position[0] + node.width / 2,
      node.position[1] + node.height / 2,
    );
  }

  static List<CanvasNode> _snapNodesToGrid(List<CanvasNode> nodes) {
    final occupied = <GridCoord>{};
    return [
      for (final CanvasNode node in nodes) _snapNodeToFreeCell(node, occupied),
    ];
  }

  /// Returns [node] with its position snapped to the nearest grid cell not
  /// in [occupied], recording that cell in [occupied] so a second call for a
  /// different node won't land on the same spot.
  static CanvasNode _snapNodeToFreeCell(
    CanvasNode node,
    Set<GridCoord> occupied,
  ) {
    final GridCoord cell = findNearestFreeCell(_nodeCenter(node), occupied);
    occupied.add(cell);
    final Offset topLeft = gridCoordToCenteredOffset(
      cell,
      nodeWidth: node.width,
      nodeHeight: node.height,
    );
    return node.copyWith(position: <double>[topLeft.dx, topLeft.dy]);
  }

  CanvasNode _snapToFreeCell(CanvasNode node, Set<GridCoord> occupied) {
    return _snapNodeToFreeCell(node, occupied);
  }

  // ---------------------------------------------------------------------------
  // Grid-snap — pipeline DAG (mirrors the CanvasNode helpers above; kept
  // separate since PipelineDagNode has no width/height fields of its own --
  // its footprint is derived from its port count via [pipelineDagNodeHeightFor]).
  // ---------------------------------------------------------------------------

  static Offset _dagNodeCenter(PipelineDagNode node) {
    return Offset(
      node.x + kPipelineDagNodeWidth / 2,
      node.y + pipelineDagNodeHeightFor(node) / 2,
    );
  }

  static GridCoord _dagNodeGridCoord(PipelineDagNode node) {
    return centerToGridCoord(_dagNodeCenter(node));
  }

  Set<GridCoord> _dagOccupiedCells(PipelineDAG dag, {String? excludingId}) {
    return dag.nodes
        .where((PipelineDagNode n) => n.id != excludingId)
        .map(_dagNodeGridCoord)
        .toSet();
  }

  static PipelineDagNode _snapDagNodeToFreeCell(
    PipelineDagNode node,
    Set<GridCoord> occupied,
  ) {
    final GridCoord cell = findNearestFreeCell(_dagNodeCenter(node), occupied);
    occupied.add(cell);
    final Offset topLeft = gridCoordToCenteredOffset(
      cell,
      nodeWidth: kPipelineDagNodeWidth,
      nodeHeight: pipelineDagNodeHeightFor(node),
    );
    return node.copyWith(x: topLeft.dx, y: topLeft.dy);
  }

  static List<PipelineDagNode> _snapDagNodesToGrid(
    List<PipelineDagNode> nodes,
  ) {
    final occupied = <GridCoord>{};
    return [
      for (final PipelineDagNode node in nodes)
        _snapDagNodeToFreeCell(node, occupied),
    ];
  }

  /// Snaps every node in [phase]'s DAG within [phases] onto the grid,
  /// preserving edges, and returns the updated [PipelinePhases]. Operates
  /// purely on [phases] (not [state]) so it's safe to call on a freshly
  /// built/loaded value before it's ever assigned to state -- unlike
  /// [_phasesWithUpdated], which always merges against the *current*
  /// `state.pipelinePhases` and would silently discard this data otherwise.
  PipelinePhases _snapDagPhaseToGrid(
    PipelinePhases phases,
    PipelinePhaseId phase,
  ) {
    final dag = phases.dagFor(phase);
    if (dag.nodes.isEmpty) return phases;
    final snapped = _snapDagNodesToGrid(dag.nodes);
    var updated = dag;
    for (final n in snapped) {
      updated = updated.copyWithNode(n);
    }
    return phases.copyWith(
      train: phase == PipelinePhaseId.train ? updated : null,
      eval: phase == PipelinePhaseId.eval ? updated : null,
      infer: phase == PipelinePhaseId.infer ? updated : null,
    );
  }

  /// Commits a dragged pipeline DAG node's final position, snapping it to
  /// the nearest grid cell not already owned by another node in the same
  /// phase. Call this once, on drag release -- [movePipelineDagNode] is what
  /// drives the live, unsnapped visual feedback while the drag is in progress.
  void snapPipelineDagNodeToGrid(PipelinePhaseId phase, String id) {
    final dag = state.pipelinePhases.dagFor(phase);
    final node = _firstWhereOrNullDag(dag.nodes, id);
    if (node == null) return;
    final GridCoord cell = findNearestFreeCell(
      _dagNodeCenter(node),
      _dagOccupiedCells(dag, excludingId: id),
    );
    final Offset topLeft = gridCoordToCenteredOffset(
      cell,
      nodeWidth: kPipelineDagNodeWidth,
      nodeHeight: pipelineDagNodeHeightFor(node),
    );
    final updated = dag.copyWithNode(
      node.copyWith(x: topLeft.dx, y: topLeft.dy),
    );
    state = state.copyWith(pipelinePhases: _phasesWithUpdated(phase, updated));
  }

  static PipelineDagNode? _firstWhereOrNullDag(
    List<PipelineDagNode> nodes,
    String id,
  ) {
    for (final n in nodes) {
      if (n.id == id) return n;
    }
    return null;
  }

  static CanvasNode? _firstWhereOrNull(List<CanvasNode> nodes, String id) {
    for (final n in nodes) {
      if (n.id == id) return n;
    }
    return null;
  }

  /// The node a newly added node should be placed right of/below -- the
  /// single selected node if there is exactly one, otherwise the most
  /// recently added node (nodes are appended in order, so `.last` is it).
  /// Null when the graph is empty, meaning there's nothing to place relative
  /// to (falls back to today's nearest-free-cell placement).
  CanvasNode? _referenceNodeForAdd() {
    final List<CanvasNode> nodes = state.graph.nodes;
    if (nodes.isEmpty) return null;
    if (state.selectedNodeIds.length == 1) {
      final CanvasNode? selected = _firstWhereOrNull(
        nodes,
        state.selectedNodeIds.first,
      );
      if (selected != null) return selected;
    }
    return nodes.last;
  }

  void addNode(CanvasNode node, {bool preferRight = true}) {
    _pushUndoHistory();
    final Set<GridCoord> occupied = _occupiedCells();
    final CanvasNode? reference = _referenceNodeForAdd();
    final CanvasNode snapped;
    if (reference == null) {
      snapped = _snapToFreeCell(node, occupied);
    } else {
      final GridCoord cell = findNextCellRightOrBelow(
        _nodeGridCoord(reference),
        occupied,
        preferRight: preferRight,
      );
      final Offset topLeft = gridCoordToCenteredOffset(
        cell,
        nodeWidth: node.width,
        nodeHeight: node.height,
      );
      snapped = node.copyWith(position: <double>[topLeft.dx, topLeft.dy]);
    }
    _publishGraph(state.graph.copyWith(nodes: [...state.graph.nodes, snapped]));
    state = state.copyWith(
      selectedNodeIds: {snapped.id},
      clearSelectedEdgeId: true,
      canUndo: true,
      canRedo: false,
      pendingViewportFocusNodeId: snapped.id,
    );
    _pushToCanonical();
  }

  /// Clears the transient viewport-follow signal set by [addNode] /
  /// [addPipelineDagNode] once the owning canvas widget has animated to it.
  void clearPendingViewportFocusNodeId() {
    if (state.pendingViewportFocusNodeId == null) return;
    state = state.copyWith(clearPendingViewportFocusNodeId: true);
  }

  void removeNode(String id) {
    _pushUndoHistory();
    final newNodes = state.graph.nodes.where((n) => n.id != id).toList();
    final newEdges = state.graph.edges
        .where((e) => e.sourceNodeId != id && e.targetNodeId != id)
        .toList();
    final remainingSelection = Set<String>.from(state.selectedNodeIds)
      ..remove(id);
    _layoutOverrides.remove(id);
    _publishGraph(state.graph.copyWith(nodes: newNodes, edges: newEdges));
    state = state.copyWith(
      selectedNodeIds: remainingSelection,
      clearSelectedNodeIds: remainingSelection.isEmpty,
      canUndo: true,
      canRedo: false,
    );
    _pushToCanonical();
  }

  void removeEdge(String id) {
    _pushUndoHistory();
    _publishGraph(
      state.graph.copyWith(
        edges: state.graph.edges.where((e) => e.id != id).toList(),
      ),
    );
    state = state.copyWith(
      clearSelectedEdgeId: state.selectedEdgeId == id,
      canUndo: true,
      canRedo: false,
    );
    _pushToCanonical();
  }

  void addEdge(CanvasEdge edge) {
    _pushUndoHistory();
    _publishGraph(state.graph.copyWith(edges: [...state.graph.edges, edge]));
    state = state.copyWith(
      selectedEdgeId: edge.id,
      clearSelectedNodeIds: true,
      canUndo: true,
      canRedo: false,
    );
    _pushToCanonical();
  }

  /// Adds [node] and an edge connecting it, as **one** undoable step.
  ///
  /// [buildEdge] receives the node *after* grid snapping, since the caller
  /// cannot know the final position or predict the placement.
  ///
  /// Exists because the port-anchored `+` creates a node and its wire in a
  /// single user gesture; calling [addNode] then [addEdge] would push two undo
  /// entries and force the user to press undo twice to reverse one click.
  ///
  /// Note there is no pipeline-DAG counterpart: the undo stack holds
  /// `state.graph` only, so `addPipelineDagNode`/`addPipelineDagEdge` are not
  /// undoable in the first place.
  void addNodeWithEdge(
    CanvasNode node,
    CanvasEdge Function(CanvasNode placed) buildEdge, {
    bool preferRight = true,
  }) {
    _pushUndoHistory();

    final Set<GridCoord> occupied = _occupiedCells();
    final CanvasNode? reference = _referenceNodeForAdd();
    final CanvasNode snapped;
    if (reference == null) {
      snapped = _snapToFreeCell(node, occupied);
    } else {
      final GridCoord cell = findNextCellRightOrBelow(
        _nodeGridCoord(reference),
        occupied,
        preferRight: preferRight,
      );
      final Offset topLeft = gridCoordToCenteredOffset(
        cell,
        nodeWidth: node.width,
        nodeHeight: node.height,
      );
      snapped = node.copyWith(position: <double>[topLeft.dx, topLeft.dy]);
    }

    final CanvasEdge edge = buildEdge(snapped);
    _publishGraph(
      state.graph.copyWith(
        nodes: <CanvasNode>[...state.graph.nodes, snapped],
        edges: <CanvasEdge>[...state.graph.edges, edge],
      ),
    );
    state = state.copyWith(
      selectedNodeIds: {snapped.id},
      clearSelectedEdgeId: true,
      canUndo: true,
      canRedo: false,
      pendingViewportFocusNodeId: snapped.id,
    );
    _pushToCanonical();
  }

  void updateNodeParameters(String id, Map<String, dynamic> parameters) {
    _pushUndoHistory();
    // Every display surface (node card, property panel title/field) reads
    // `label ?? parameters['name'] ?? id` — keep `label` in sync with a
    // renamed `parameters['name']` so those reads don't keep resolving to
    // the stale label set once at node creation.
    final renamedTo = parameters['name'];
    _publishGraph(
      state.graph.copyWith(
        nodes: state.graph.nodes
            .map(
              (n) => n.id == id
                  ? n.copyWith(
                      label: renamedTo is String ? renamedTo : n.label,
                      parameters: {...n.parameters, ...parameters},
                    )
                  : n,
            )
            .toList(),
      ),
    );
    state = state.copyWith(canUndo: true, canRedo: false);
    _pushToCanonical(debounce: true);
  }

  /// Rebinds one existing canvas instance to a newly saved custom component
  /// while preserving its geometry, parameters, and graph connections.
  void replaceNodeComponent(
    String id,
    String componentId, {
    String? baseNirType,
  }) {
    _pushUndoHistory();
    _publishGraph(
      state.graph.copyWith(
        nodes: state.graph.nodes
            .map(
              (CanvasNode node) => node.id == id
                  ? node.copyWith(
                      componentId: componentId,
                      nirType: baseNirType,
                      clearNirType: baseNirType == null,
                      metadata: <String, dynamic>{
                        ...node.metadata,
                        'is_custom': true,
                      },
                    )
                  : node,
            )
            .toList(growable: false),
      ),
    );
    state = state.copyWith(canUndo: true, canRedo: false);
    _pushToCanonical();
  }

  /// Sets or clears the network-level timestep (`graph.metadata['dt']`,
  /// seconds). Passing null removes the key entirely — representing "no
  /// network timestep declared" (codegen falls back to its own 1e-4
  /// default) rather than persisting a stale or zero value.
  void setNetworkTimestepSeconds(double? seconds) {
    _pushUndoHistory();
    final nextMetadata = Map<String, dynamic>.from(state.graph.metadata);
    if (seconds == null) {
      nextMetadata.remove('dt');
    } else {
      nextMetadata['dt'] = seconds;
    }
    _publishGraph(state.graph.copyWith(metadata: nextMetadata));
    state = state.copyWith(canUndo: true, canRedo: false);
    _pushToCanonical(debounce: true);
  }

  void updateEdgeParameters(String id, Map<String, dynamic> parameters) {
    _pushUndoHistory();
    _publishGraph(
      state.graph.copyWith(
        edges: state.graph.edges
            .map((e) => e.id == id ? e.copyWith(parameters: parameters) : e)
            .toList(),
      ),
    );
    state = state.copyWith(canUndo: true, canRedo: false);
    _pushToCanonical(debounce: true);
  }

  // ---------------------------------------------------------------------------
  // Public API — position/size/visibility (UI-local)
  // ---------------------------------------------------------------------------

  void updateNodePosition(String id, double x, double y) {
    state = state.copyWith(
      graph: state.graph.copyWith(
        nodes: state.graph.nodes.map((n) {
          if (n.id != id) return n;
          final updated = n.copyWith(position: [x, y]);
          _recordLayout(updated);
          return updated;
        }).toList(),
      ),
    );
  }

  /// Commits a dragged node's final position, snapping it to the nearest
  /// grid cell that isn't already owned by another node. Call this once, on
  /// drag release — [updateNodePosition] is what drives the live, unsnapped
  /// visual feedback while the drag is in progress.
  void snapNodeToGrid(String id) {
    final CanvasNode? node = state.graph.nodes
        .where((CanvasNode n) => n.id == id)
        .firstOrNull;
    if (node == null) {
      return;
    }
    // `_occupiedCells` already excludes this node's own cell, so a drop back
    // onto its own current position resolves to itself without needing to
    // pass `ignoring` — computing that from the live, unsnapped drag
    // position would risk coinciding with another node's real cell.
    final GridCoord cell = findNearestFreeCell(
      _nodeCenter(node),
      _occupiedCells(excludingId: id),
    );
    final Offset topLeft = gridCoordToCenteredOffset(
      cell,
      nodeWidth: node.width,
      nodeHeight: node.height,
    );
    state = state.copyWith(
      graph: state.graph.copyWith(
        nodes: state.graph.nodes.map((n) {
          if (n.id != id) return n;
          final updated = n.copyWith(
            position: <double>[topLeft.dx, topLeft.dy],
          );
          _recordLayout(updated);
          return updated;
        }).toList(),
      ),
    );
  }

  void updateNodeSize(String id, double width, double height) {
    state = state.copyWith(
      graph: state.graph.copyWith(
        nodes: state.graph.nodes.map((n) {
          if (n.id != id) return n;
          final updated = n.copyWith(width: width, height: height);
          _recordLayout(updated);
          return updated;
        }).toList(),
      ),
    );
  }

  void toggleNodeVisibility(String id) {
    state = state.copyWith(
      graph: state.graph.copyWith(
        nodes: state.graph.nodes.map((n) {
          if (n.id != id) return n;
          final updated = n.copyWith(isVisible: !n.isVisible);
          _recordLayout(updated);
          return updated;
        }).toList(),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Public API — selection (UI-local)
  // ---------------------------------------------------------------------------

  void selectNode(String? id) {
    state = state.copyWith(
      selectedNodeIds: id == null ? const <String>{} : {id},
      clearSelectedNodeIds: id == null,
      clearSelectedEdgeId: true,
    );
  }

  void toggleNodeSelection(String id, {bool additive = false}) {
    final next = Set<String>.from(
      additive ? state.selectedNodeIds : const <String>{},
    );
    if (next.contains(id)) {
      next.remove(id);
    } else {
      next.add(id);
    }
    state = state.copyWith(
      selectedNodeIds: next,
      clearSelectedNodeIds: next.isEmpty,
      clearSelectedEdgeId: true,
    );
  }

  void selectNodes(Iterable<String> ids) {
    final next = ids.toSet();
    state = state.copyWith(
      selectedNodeIds: next,
      clearSelectedNodeIds: next.isEmpty,
      clearSelectedEdgeId: true,
    );
  }

  void selectNodesInRect(Rect sceneRect) {
    final selected = <String>{};
    for (final CanvasNode node in state.graph.nodes) {
      // Card footprints come from the shared canvasNodeSize; a node's
      // persisted width/height no longer affect what it covers on screen.
      final bounds = Rect.fromLTWH(
        node.position[0],
        node.position[1],
        kCanvasNodeWidth,
        node.isVisible ? kCanvasNodeBaseHeight : kCanvasNodeCollapsedHeight,
      );
      if (sceneRect.overlaps(bounds)) {
        selected.add(node.id);
      }
    }
    selectNodes(selected);
  }

  /// Lasso-selects every node of [phase]'s DAG overlapping [sceneRect].
  ///
  /// The Architecture-canvas counterpart above; both canvases share the one
  /// `selectedNodeIds` set, so the rest of selection (delete, copy, the
  /// property panel) already works for the pipeline phases.
  void selectPipelineDagNodesInRect(PipelinePhaseId phase, Rect sceneRect) {
    final PipelineDAG dag = state.pipelinePhases.dagFor(phase);
    final selected = <String>{};
    for (final PipelineDagNode node in dag.nodes) {
      final Size size = pipelineDagNodeSize(node);
      if (sceneRect.overlaps(
        Rect.fromLTWH(node.x, node.y, size.width, size.height),
      )) {
        selected.add(node.id);
      }
    }
    selectNodes(selected);
  }

  void clearSelection() {
    state = state.copyWith(
      clearSelectedNodeIds: true,
      clearSelectedEdgeId: true,
    );
  }

  void selectAllNodes() {
    selectNodes(state.graph.nodes.map((CanvasNode node) => node.id));
  }

  void selectEdge(String? id) {
    state = state.copyWith(
      selectedEdgeId: id,
      clearSelectedEdgeId: id == null,
      clearSelectedNodeIds: true,
    );
  }

  void deleteSelection() {
    if (state.selectedNodeIds.isEmpty && state.selectedEdgeId == null) {
      return;
    }
    if (state.selectedNodeIds.isNotEmpty) {
      _pushUndoHistory();
      final ids = state.selectedNodeIds;
      final newNodes = state.graph.nodes
          .where((CanvasNode n) => !ids.contains(n.id))
          .toList();
      final newEdges = state.graph.edges
          .where(
            (CanvasEdge e) =>
                !ids.contains(e.sourceNodeId) && !ids.contains(e.targetNodeId),
          )
          .toList();
      ids.forEach(_layoutOverrides.remove);
      _publishGraph(state.graph.copyWith(nodes: newNodes, edges: newEdges));
      state = state.copyWith(
        clearSelectedNodeIds: true,
        clearSelectedEdgeId: true,
        canUndo: true,
        canRedo: false,
      );
      _pushToCanonical();
      return;
    }
    if (state.selectedEdgeId != null) {
      removeEdge(state.selectedEdgeId!);
    }
  }

  Future<void> copySelection() async {
    if (state.selectedNodeIds.isEmpty) {
      return;
    }
    final payload = CanvasClipboardPayload.fromSelection(
      graph: state.graph,
      selectedNodeIds: state.selectedNodeIds,
    );
    _inMemoryClipboard = payload;
    try {
      await Clipboard.setData(ClipboardData(text: payload.encode()));
    } on Object {
      // Clipboard may be unavailable in tests or restricted environments.
    }
  }

  Future<void> pasteClipboard({Offset offset = const Offset(40, 40)}) async {
    CanvasClipboardPayload? payload = _inMemoryClipboard;
    if (payload == null || payload.nodes.isEmpty) {
      try {
        final clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
        payload = CanvasClipboardPayload.tryDecode(clipboardData?.text ?? '');
      } on Object {
        payload = null;
      }
    }
    if (payload == null || payload.nodes.isEmpty) {
      return;
    }

    _pushUndoHistory();
    final idMap = <String, String>{};
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final pastedNodes = <CanvasNode>[];
    for (var index = 0; index < payload.nodes.length; index += 1) {
      final node = payload.nodes[index];
      final baseId = node.nirType ?? node.componentId;
      final newId = '${baseId}_${timestamp}_$index';
      idMap[node.id] = newId;
      pastedNodes.add(
        node.copyWith(
          id: newId,
          position: <double>[
            node.position[0] + offset.dx,
            node.position[1] + offset.dy,
          ],
        ),
      );
    }

    final pastedEdges = <CanvasEdge>[];
    for (var index = 0; index < payload.edges.length; index += 1) {
      final edge = payload.edges[index];
      final newSource = idMap[edge.sourceNodeId];
      final newTarget = idMap[edge.targetNodeId];
      if (newSource == null || newTarget == null) {
        continue;
      }
      pastedEdges.add(
        edge.copyWith(
          id: 'edge_${timestamp}_$index',
          sourceNodeId: newSource,
          targetNodeId: newTarget,
        ),
      );
    }

    _publishGraph(
      state.graph.copyWith(
        nodes: [...state.graph.nodes, ...pastedNodes],
        edges: [...state.graph.edges, ...pastedEdges],
      ),
      snapNodes: false,
    );
    state = state.copyWith(
      selectedNodeIds: pastedNodes.map((CanvasNode n) => n.id).toSet(),
      clearSelectedEdgeId: true,
      canUndo: true,
      canRedo: false,
    );
    _pushToCanonical();
  }

  Future<void> cutSelection() async {
    await copySelection();
    deleteSelection();
  }

  // ---------------------------------------------------------------------------
  // Public API — connection drag
  // ---------------------------------------------------------------------------

  void startConnecting(String nodeId, String portId) {
    state = state.copyWith(
      connectingFromNodeId: nodeId,
      connectingFromPortId: portId,
    );
  }

  void cancelConnecting() {
    state = state.copyWith(
      clearConnectingFromNodeId: true,
      clearConnectingFromPortId: true,
    );
  }

  // ---------------------------------------------------------------------------
  // Public API — auto-layout (UI-local, no upstream sync)
  // ---------------------------------------------------------------------------

  /// BFS tiering shared by both layout axes: each node's tier is its
  /// topological depth from the nearest input/root node.
  Map<int, List<CanvasNode>> _computeLayoutTiers() {
    final adjacency = <String, List<String>>{};
    final incoming = <String, int>{for (final n in state.graph.nodes) n.id: 0};
    for (final e in state.graph.edges) {
      adjacency.putIfAbsent(e.sourceNodeId, () => []).add(e.targetNodeId);
      incoming.update(e.targetNodeId, (c) => c + 1, ifAbsent: () => 1);
    }

    final tiers = <String, int>{};
    final queue = <String>[];
    for (final n in state.graph.nodes) {
      if ((n.nirType ?? n.componentId) == 'nir.Input' || incoming[n.id] == 0) {
        tiers[n.id] = 0;
        queue.add(n.id);
      }
    }
    if (queue.isEmpty) {
      for (final n in state.graph.nodes) {
        tiers[n.id] = 0;
        queue.add(n.id);
      }
    }

    var i = 0;
    while (i < queue.length) {
      final cur = queue[i++];
      for (final next in adjacency[cur] ?? const <String>[]) {
        final proposed = (tiers[cur] ?? 0) + 1;
        if ((tiers[next] ?? -1) < proposed) {
          tiers[next] = proposed;
          queue.add(next);
        }
      }
    }
    for (final n in state.graph.nodes) {
      tiers.putIfAbsent(n.id, () => 0);
    }

    final grouped = <int, List<CanvasNode>>{};
    for (final n in state.graph.nodes) {
      grouped.putIfAbsent(tiers[n.id] ?? 0, () => []).add(n);
    }
    return grouped;
  }

  /// Lays out the graph in BFS tiers along [axis]. Horizontal: tiers flow
  /// left-to-right (columns), nodes within a tier stack top-to-bottom.
  /// Vertical: tiers flow top-to-bottom (rows), nodes within a tier spread
  /// left-to-right.
  void autoLayoutGraph({CanvasLayoutAxis axis = CanvasLayoutAxis.horizontal}) {
    if (state.graph.nodes.isEmpty) return;
    _pushUndoHistory();

    final grouped = _computeLayoutTiers();
    final nextNodes = <CanvasNode>[];

    if (axis == CanvasLayoutAxis.horizontal) {
      final tierCount = grouped.keys.fold<int>(0, math.max) + 1;
      // Step by whole grid cells (not an arbitrary pixel value) so the ideal
      // position for tier k already lands exactly on grid column/row k --
      // stepping by a non-multiple of the cell size let independent
      // per-node rounding in _snapNodesToGrid drift and skip a column at
      // deeper tiers, leaving unwanted empty space between nodes.
      const hStep = kGridCellWidth;
      const vStep = kGridCellHeight;
      final totalW = math.max(hStep * math.max(0, tierCount - 1), 0.0);
      for (final entry in grouped.entries) {
        for (var j = 0; j < entry.value.length; j++) {
          nextNodes.add(
            entry.value[j].copyWith(
              position: [
                120.0 + entry.key * hStep + (totalW == 0 ? 120.0 : 0.0),
                120.0 + j * vStep,
              ],
            ),
          );
        }
      }
    } else {
      const vStep = kGridCellHeight;
      const hStep = kGridCellWidth;
      for (final entry in grouped.entries) {
        for (var j = 0; j < entry.value.length; j++) {
          nextNodes.add(
            entry.value[j].copyWith(
              position: [120.0 + j * hStep, 120.0 + entry.key * vStep],
            ),
          );
        }
      }
    }

    // Snap the freshly-computed tier positions onto the grid. hStep/vStep
    // above are now whole grid cells, so this is a no-op for a graph with a
    // single node per cell; it still matters when in-tier nodes have custom
    // widths/heights that push a node's center out of its ideal cell.
    // Snapping in tier order (nextNodes' order) keeps each tier's
    // first-choice cell priority matching its layout position, same as
    // _snapNodesToGrid's contract.
    final snappedNodes = _snapNodesToGrid(nextNodes);

    state = state.copyWith(
      graph: state.graph.copyWith(
        nodes: state.graph.nodes
            .map(
              (n) =>
                  snappedNodes.firstWhere((c) => c.id == n.id, orElse: () => n),
            )
            .toList(),
      ),
      canUndo: true,
      canRedo: false,
    );
  }

  /// Auto-layout optimised for mobile (portrait): tiers flow top-to-bottom,
  /// nodes within each tier spread left-to-right.
  void autoLayoutGraphVertical() =>
      autoLayoutGraph(axis: CanvasLayoutAxis.vertical);

  /// BFS tiering for a pipeline-phase DAG, mirroring [_computeLayoutTiers]
  /// but over [PipelineDagNode]/[PipelineDagEdge] instead of [CanvasNode].
  Map<int, List<PipelineDagNode>> _computeDagLayoutTiers(PipelineDAG dag) {
    final adjacency = <String, List<String>>{};
    final incoming = <String, int>{for (final n in dag.nodes) n.id: 0};
    for (final e in dag.edges) {
      adjacency.putIfAbsent(e.sourceNodeId, () => []).add(e.targetNodeId);
      incoming.update(e.targetNodeId, (c) => c + 1, ifAbsent: () => 1);
    }

    final tiers = <String, int>{};
    final queue = <String>[];
    for (final n in dag.nodes) {
      if (incoming[n.id] == 0) {
        tiers[n.id] = 0;
        queue.add(n.id);
      }
    }
    if (queue.isEmpty) {
      for (final n in dag.nodes) {
        tiers[n.id] = 0;
        queue.add(n.id);
      }
    }

    var i = 0;
    while (i < queue.length) {
      final cur = queue[i++];
      for (final next in adjacency[cur] ?? const <String>[]) {
        final proposed = (tiers[cur] ?? 0) + 1;
        if ((tiers[next] ?? -1) < proposed) {
          tiers[next] = proposed;
          queue.add(next);
        }
      }
    }
    for (final n in dag.nodes) {
      tiers.putIfAbsent(n.id, () => 0);
    }

    final grouped = <int, List<PipelineDagNode>>{};
    for (final n in dag.nodes) {
      grouped.putIfAbsent(tiers[n.id] ?? 0, () => []).add(n);
    }
    return grouped;
  }

  /// Auto-layouts a pipeline phase's DAG (train/eval) in BFS tiers along
  /// [axis], mirroring [autoLayoutGraph] for the architecture graph. Pipeline
  /// DAG edits don't participate in undo/redo today (see
  /// [movePipelineDagNode] and siblings, none of which call
  /// [_pushUndoHistory] either) so this doesn't either -- consistent with
  /// the rest of this notifier's pipeline-DAG mutations.
  void autoLayoutPipelineDag(
    PipelinePhaseId phase, {
    CanvasLayoutAxis axis = CanvasLayoutAxis.horizontal,
  }) {
    final dag = state.pipelinePhases.dagFor(phase);
    if (dag.nodes.isEmpty) return;

    final grouped = _computeDagLayoutTiers(dag);
    final nextNodes = <PipelineDagNode>[];

    if (axis == CanvasLayoutAxis.horizontal) {
      // Whole grid cells, not arbitrary pixel steps -- see autoLayoutGraph.
      const hStep = kGridCellWidth;
      const vStep = kGridCellHeight;
      for (final entry in grouped.entries) {
        for (var j = 0; j < entry.value.length; j++) {
          final n = entry.value[j];
          nextNodes.add(
            n.copyWith(x: 120.0 + entry.key * hStep, y: 120.0 + j * vStep),
          );
        }
      }
    } else {
      const vStep = kGridCellHeight;
      const hStep = kGridCellWidth;
      for (final entry in grouped.entries) {
        for (var j = 0; j < entry.value.length; j++) {
          final n = entry.value[j];
          nextNodes.add(
            n.copyWith(x: 120.0 + j * hStep, y: 120.0 + entry.key * vStep),
          );
        }
      }
    }

    // Snap the freshly-computed tier positions onto the grid, same as
    // autoLayoutGraph does for the architecture graph.
    final snappedNodes = _snapDagNodesToGrid(nextNodes);
    var updated = dag;
    for (final n in snappedNodes) {
      updated = updated.copyWithNode(n);
    }

    state = state.copyWith(pipelinePhases: _phasesWithUpdated(phase, updated));
  }
}

/// Direction the BFS-tiered auto-layout flows in: [horizontal] flows
/// left-to-right (tiers as columns), [vertical] flows top-to-bottom (tiers
/// as rows). Also drives node-header and port-placement orientation in
/// [NetworkCanvas]/[PipelinePhaseCanvas].
enum CanvasLayoutAxis { horizontal, vertical }

/// Backward-compat alias consumed by all existing widgets/providers.
final canvasProvider = canvasControllerProvider;
