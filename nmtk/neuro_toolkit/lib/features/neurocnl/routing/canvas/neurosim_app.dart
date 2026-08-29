// ignore_for_file: unused_element, unused_local_variable
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';

import 'package:neuro_toolkit/features/neurocnl/providers/canvas/canvas_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/canvas/project_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/canvas/simulation_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/screens/canvas/canvas_screen.dart';
import 'package:neuro_toolkit/features/neurocnl/screens/canvas/export_screen.dart';
import 'package:neuro_toolkit/features/neurocnl/screens/canvas/project_screen.dart';
import 'package:neuro_toolkit/features/neurocnl/screens/canvas/sweep_screen.dart';
import 'package:neuro_toolkit/features/neurocnl/routing/canvas/neurosim_nav_section.dart';
import 'package:neuro_toolkit/features/neurocnl/routing/canvas/neurosim_route_state.dart';
import 'package:neuro_toolkit/features/neurocnl/routing/canvas/neurosim_workspace_controller.dart';

class NeuroSimApp extends ConsumerStatefulWidget {
  const NeuroSimApp({
    super.key,
    this.showShellChrome = true,
    this.initialLocation = '/',
    this.initialSnapshot,
  });

  final bool showShellChrome;
  final String initialLocation;
  final String? initialSnapshot;

  @override
  ConsumerState<NeuroSimApp> createState() => _NeuroSimAppState();
}

class _NeuroSimAppState extends ConsumerState<NeuroSimApp> {
  ProviderSubscription<NeurosimWorkspaceState>? _workspaceSubscription;
  ProviderSubscription<CanvasState>? _canvasSubscription;
  ProviderSubscription<SimulationState>? _simulationSubscription;
  bool _applyingWorkspace = false;
  String? _loadedProjectId;
  NeuroSimNavSection _activeCanvasSection = NeuroSimNavSection.canvas;

  @override
  void initState() {
    super.initState();
    _workspaceSubscription = ref.listenManual<NeurosimWorkspaceState>(
      neurosimWorkspaceProvider,
      (_, _) => _syncFromWorkspace(),
    );
    _installProviderListeners();
    ref
        .read(neurosimWorkspaceProvider.notifier)
        .initialize(
          location: widget.initialLocation,
          snapshot: widget.initialSnapshot,
        )
        .then((_) {
          if (mounted) {
            _syncFromWorkspace(forceProjectReload: true);
          }
        });
  }

  @override
  void dispose() {
    _workspaceSubscription?.close();
    _canvasSubscription?.close();
    _simulationSubscription?.close();
    super.dispose();
  }

  void _installProviderListeners() {
    _canvasSubscription = ref.listenManual<CanvasState>(canvasProvider, (
      _,
      next,
    ) {
      final ws = ref.read(neurosimWorkspaceProvider);
      if (_applyingWorkspace || !ws.isHydrated) return;
      ref
          .read(neurosimWorkspaceProvider.notifier)
          .updateSelection(
            selectedNodeId: next.primarySelectedNodeId,
            clearSelectedNodeId: next.primarySelectedNodeId == null,
            selectedEdgeId: next.selectedEdgeId,
            clearSelectedEdgeId: next.selectedEdgeId == null,
          );
    });
    _simulationSubscription = ref.listenManual<SimulationState>(
      simulationProvider,
      (_, next) {
        final ws = ref.read(neurosimWorkspaceProvider);
        if (_applyingWorkspace || !ws.isHydrated) return;
        final completedResults =
            next.status == SimulationStatus.completed && next.results != null
            ? next.results!.toJson()
            : null;
        ref
            .read(neurosimWorkspaceProvider.notifier)
            .updatePreviewState(
              currentTime: next.currentTime,
              previewResults: completedResults,
            );
      },
    );
  }

  Future<void> _syncFromWorkspace({bool forceProjectReload = false}) async {
    final workspaceState = ref.read(neurosimWorkspaceProvider);
    if (!mounted || !workspaceState.isHydrated || _applyingWorkspace) return;

    final routeState = workspaceState.routeState;
    _applyingWorkspace = true;

    try {
      if (routeState.selectedProjectId != null &&
          (forceProjectReload ||
              _loadedProjectId != routeState.selectedProjectId)) {
        try {
          final project = await ref
              .read(currentProjectProvider.notifier)
              .loadProject(routeState.selectedProjectId!);
          if (!mounted) return;
          ref.read(canvasProvider.notifier).loadProjectGraph(project.graph);
          _loadedProjectId = project.id;
        } catch (_) {
          if (!mounted) return;
          _loadedProjectId = null;
          ref.read(currentProjectProvider.notifier).clearCurrentProject();
          ref.read(canvasProvider.notifier).resetGraph();
          ref.read(simulationProvider.notifier).reset();
          await ref
              .read(neurosimWorkspaceProvider.notifier)
              .restoreMissingProjectFallback();
          return;
        }
      }

      final canvasNotifier = ref.read(canvasProvider.notifier);
      final canvasState = ref.read(canvasProvider);
      final hasSelectedNode =
          routeState.selectedNodeId != null &&
          canvasState.graph.nodes.any(
            (node) => node.id == routeState.selectedNodeId,
          );
      final hasSelectedEdge =
          routeState.selectedEdgeId != null &&
          canvasState.graph.edges.any(
            (edge) => edge.id == routeState.selectedEdgeId,
          );
      canvasNotifier.restoreSelection(
        selectedNodeIds: hasSelectedNode ? {routeState.selectedNodeId!} : null,
        selectedEdgeId: hasSelectedEdge ? routeState.selectedEdgeId : null,
      );

      ref
          .read(simulationProvider.notifier)
          .restoreSnapshot(
            resultsJson: routeState.previewResults,
            currentTime: routeState.previewCurrentTime,
          );
    } finally {
      _applyingWorkspace = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final workspaceState = ref.watch(neurosimWorkspaceProvider);
    // NeuroSimApp is always embedded inside an ancestor MaterialApp (either
    // the neurocnl studio's app.dart or the main toolkit's MaterialApp).
    // Do NOT create another MaterialApp here — that would break the inherited
    // theme and always render in dark mode. Render _buildShell directly.
    return _buildShell(workspaceState);
  }

  Widget _buildShell(NeurosimWorkspaceState workspaceState) {
    if (!workspaceState.isHydrated) {
      return const Center(child: CircularProgressIndicator());
    }

    final routeState = workspaceState.routeState;
    final content = _buildContent(routeState);
    if (!widget.showShellChrome) {
      return Scaffold(
        backgroundColor: NmtkShellTokens.of(context).shellBackground,
        body: SafeArea(bottom: false, child: content),
      );
    }

    final headerActions = _buildHeaderActions(routeState);
    final tokens = NmtkShellTokens.of(context);

    return Scaffold(
      backgroundColor: tokens.shellBackground,
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            if (headerActions != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                decoration: BoxDecoration(
                  color: tokens.topBarBackground,
                  border: Border(
                    bottom: BorderSide(color: tokens.chromeBorder),
                  ),
                ),
                child: headerActions,
              ),
            Expanded(child: content),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(NeurosimRouteState routeState) {
    final notifier = ref.read(neurosimWorkspaceProvider.notifier);
    final activeCanvasSection = routeState.target == NeurosimRouteTarget.preview
        ? NeuroSimNavSection.simulate
        : _activeCanvasSection;
    switch (routeState.target) {
      case NeurosimRouteTarget.projectList:
        return ProjectScreen(
          selectedProjectId: routeState.selectedProjectId,
          onProjectSelected: (projectId) {
            notifier.openProjects(projectId: projectId);
          },
          onLoadIntoCanvas: (project) {
            notifier.openCanvas(projectId: project.id);
          },
          onProjectDeleted: (projectId) {
            if (routeState.selectedProjectId == projectId) {
              notifier.openProjects();
            }
          },
        );
      case NeurosimRouteTarget.sweep:
        return const SweepScreen();
      case NeurosimRouteTarget.export:
        return const ExportScreen();
      case NeurosimRouteTarget.canvas:
      case NeurosimRouteTarget.preview:
        return CanvasScreen(
          initialUri: null,
          activeSection: activeCanvasSection,
        );
    }
  }

  String _pageTitle(NeurosimRouteState routeState) {
    final activeCanvasSection = routeState.target == NeurosimRouteTarget.preview
        ? NeuroSimNavSection.simulate
        : _activeCanvasSection;
    return switch (routeState.target) {
      NeurosimRouteTarget.projectList => 'Saved Projects',
      NeurosimRouteTarget.sweep => 'Parameter Sweep',
      NeurosimRouteTarget.export => 'Export Design',
      NeurosimRouteTarget.canvas ||
      NeurosimRouteTarget.preview => switch (activeCanvasSection) {
        NeuroSimNavSection.canvas => 'Visual Network Canvas',
        NeuroSimNavSection.simulate => 'Visual Simulation',
        NeuroSimNavSection.sweep => 'Parameter Sweep',
        NeuroSimNavSection.export => 'Export Design',
      },
    };
  }

  int _selectedTopBarIndex(NeurosimRouteState routeState) {
    return switch (routeState.target) {
      NeurosimRouteTarget.projectList => 0,
      NeurosimRouteTarget.canvas || NeurosimRouteTarget.preview => 1,
      NeurosimRouteTarget.sweep => 2,
      NeurosimRouteTarget.export => 3,
    };
  }

  Widget? _buildHeaderActions(NeurosimRouteState routeState) {
    if (routeState.target != NeurosimRouteTarget.canvas &&
        routeState.target != NeurosimRouteTarget.preview) {
      return null;
    }

    final notifier = ref.read(neurosimWorkspaceProvider.notifier);
    final activeCanvasSection = routeState.target == NeurosimRouteTarget.preview
        ? NeuroSimNavSection.simulate
        : _activeCanvasSection;
    return CanvasScreenHeaderActions(
      activeSection: activeCanvasSection,
      onOpenCanvas: () {
        setState(() => _activeCanvasSection = NeuroSimNavSection.canvas);
        notifier.updatePreviewVisibility(false);
      },
      onOpenSimulation: () {
        setState(() => _activeCanvasSection = NeuroSimNavSection.simulate);
        notifier.updatePreviewVisibility(true);
      },
    );
  }

  void _handleTopBarDestinationSelected(int index, {bool preview = false}) {
    final notifier = ref.read(neurosimWorkspaceProvider.notifier);
    final projectId = ref
        .read(neurosimWorkspaceProvider)
        .routeState
        .selectedProjectId;
    switch (index) {
      case 0:
        notifier.openProjects(projectId: projectId);
        break;
      case 1:
        setState(() {
          _activeCanvasSection = preview
              ? NeuroSimNavSection.simulate
              : NeuroSimNavSection.canvas;
        });
        notifier.openCanvas(projectId: projectId, showPreview: preview);
        break;
      case 2:
        notifier.openSweep(projectId: projectId);
        break;
      case 3:
        notifier.openExport(projectId: projectId);
        break;
      default:
        break;
    }
  }
}
