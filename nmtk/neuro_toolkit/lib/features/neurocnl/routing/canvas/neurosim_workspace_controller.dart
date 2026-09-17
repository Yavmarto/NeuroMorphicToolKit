import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:neuro_toolkit/features/neurocnl/routing/canvas/neurosim_deep_link.dart';
import 'package:neuro_toolkit/features/neurocnl/routing/canvas/neurosim_restoration_snapshot.dart';
import 'package:neuro_toolkit/features/neurocnl/routing/canvas/neurosim_route_state.dart';

part 'neurosim_workspace_controller.g.dart';

/// Immutable state for [NeurosimWorkspaceController].
class NeurosimWorkspaceState {
  const NeurosimWorkspaceState({
    this.routeState = const NeurosimRouteState(
      target: NeurosimRouteTarget.canvas,
    ),
    this.isHydrated = false,
  });

  final NeurosimRouteState routeState;
  final bool isHydrated;

  NeurosimWorkspaceState copyWith({
    NeurosimRouteState? routeState,
    bool? isHydrated,
  }) {
    return NeurosimWorkspaceState(
      routeState: routeState ?? this.routeState,
      isHydrated: isHydrated ?? this.isHydrated,
    );
  }
}

@riverpod
class NeurosimWorkspaceController extends _$NeurosimWorkspaceController {
  static const String snapshotStorageKey =
      'neurosim.shell.restoration_snapshot.v1';

  @override
  NeurosimWorkspaceState build() {
    return const NeurosimWorkspaceState();
  }

  Future<void> initialize({String location = '/', String? snapshot}) async {
    if (state.isHydrated) return;
    final routeState = await _resolveInitialState(
      location: location,
      snapshot: snapshot,
    );
    if (!ref.mounted) return;
    state = NeurosimWorkspaceState(routeState: routeState, isHydrated: true);
    await _persist(routeState);
  }

  Future<NeurosimRouteState> _resolveInitialState({
    required String location,
    String? snapshot,
  }) async {
    if (snapshot != null && snapshot.isNotEmpty) {
      try {
        return NeurosimRestorationSnapshot.fromEncoded(snapshot).toRouteState();
      } catch (e) {
        debugPrint('Neurosim: discarding malformed launch snapshot: $e');
      }
    }

    if (location.isNotEmpty && location != '/') {
      return NeurosimModuleDeepLink.fromLocation(location).toRouteState();
    }

    try {
      final preferences = await SharedPreferences.getInstance();
      final encoded = preferences.getString(snapshotStorageKey);
      if (encoded != null && encoded.isNotEmpty) {
        try {
          return NeurosimRestorationSnapshot.fromEncoded(
            encoded,
          ).toRouteState();
        } catch (e) {
          debugPrint(
            'Neurosim: ignoring malformed stored restoration snapshot: $e',
          );
        }
      }
    } catch (_) {
      return const NeurosimRouteState(target: NeurosimRouteTarget.canvas);
    }

    return const NeurosimRouteState(target: NeurosimRouteTarget.canvas);
  }

  Future<void> openCanvas({
    String? projectId,
    String? selectedNodeId,
    String? selectedEdgeId,
    bool showPreview = false,
  }) async {
    final routeState = NeurosimRouteState(
      target: showPreview
          ? NeurosimRouteTarget.preview
          : NeurosimRouteTarget.canvas,
      selectedProjectId: projectId,
      selectedNodeId: selectedNodeId,
      selectedEdgeId: selectedEdgeId,
      showPreview: showPreview,
      previewCurrentTime: state.routeState.previewCurrentTime,
      previewResults: state.routeState.previewResults,
    );
    if (!ref.mounted) return;
    state = state.copyWith(routeState: routeState);
    await _persist(routeState);
  }

  Future<void> openProjects({String? projectId}) async {
    final routeState = state.routeState.copyWith(
      target: NeurosimRouteTarget.projectList,
      selectedProjectId: projectId,
    );
    if (!ref.mounted) return;
    state = state.copyWith(routeState: routeState);
    await _persist(routeState);
  }

  Future<void> openPreview({String? projectId}) async {
    final routeState = state.routeState.copyWith(
      target: NeurosimRouteTarget.preview,
      selectedProjectId: projectId,
      showPreview: true,
    );
    if (!ref.mounted) return;
    state = state.copyWith(routeState: routeState);
    await _persist(routeState);
  }

  Future<void> openSweep({String? projectId}) async {
    final routeState = state.routeState.copyWith(
      target: NeurosimRouteTarget.sweep,
      selectedProjectId: projectId,
    );
    if (!ref.mounted) return;
    state = state.copyWith(routeState: routeState);
    await _persist(routeState);
  }

  Future<void> openExport({String? projectId}) async {
    final routeState = state.routeState.copyWith(
      target: NeurosimRouteTarget.export,
      selectedProjectId: projectId,
    );
    if (!ref.mounted) return;
    state = state.copyWith(routeState: routeState);
    await _persist(routeState);
  }

  Future<void> restoreMissingProjectFallback() async {
    const routeState = NeurosimRouteState(
      target: NeurosimRouteTarget.projectList,
    );
    if (!ref.mounted) return;
    state = state.copyWith(routeState: routeState);
    await _persist(routeState);
  }

  Future<void> updateSelection({
    String? selectedNodeId,
    bool clearSelectedNodeId = false,
    String? selectedEdgeId,
    bool clearSelectedEdgeId = false,
  }) async {
    final routeState = state.routeState.copyWith(
      selectedNodeId: selectedNodeId,
      clearSelectedNodeId: clearSelectedNodeId,
      selectedEdgeId: selectedEdgeId,
      clearSelectedEdgeId: clearSelectedEdgeId,
    );
    if (!ref.mounted) return;
    state = state.copyWith(routeState: routeState);
    await _persist(routeState);
  }

  Future<void> updatePreviewVisibility(bool showPreview) async {
    final routeState = state.routeState.copyWith(
      target: showPreview
          ? NeurosimRouteTarget.preview
          : (state.routeState.target == NeurosimRouteTarget.preview
                ? NeurosimRouteTarget.canvas
                : state.routeState.target),
      showPreview: showPreview,
    );
    if (!ref.mounted) return;
    state = state.copyWith(routeState: routeState);
    await _persist(routeState);
  }

  Future<void> updatePreviewState({
    required double currentTime,
    Map<String, dynamic>? previewResults,
  }) async {
    final routeState = state.routeState.copyWith(
      previewCurrentTime: currentTime,
      previewResults: previewResults,
      clearPreviewResults: previewResults == null,
    );
    if (!ref.mounted) return;
    state = state.copyWith(routeState: routeState);
    await _persist(routeState);
  }

  Future<void> _persist(NeurosimRouteState routeState) async {
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(
        snapshotStorageKey,
        NeurosimRestorationSnapshot.fromRouteState(routeState).encode(),
      );
    } catch (e) {
      debugPrint('Neurosim: failed to persist restoration snapshot: $e');
    }
  }
}

/// Backward-compat alias.
final neurosimWorkspaceProvider = neurosimWorkspaceControllerProvider;
