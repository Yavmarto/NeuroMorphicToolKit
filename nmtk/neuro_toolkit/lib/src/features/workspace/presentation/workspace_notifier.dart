import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:neuro_toolkit/providers/riverpod_providers.dart';
import 'package:neuro_toolkit/models/workspace_session.dart';
import 'package:neuro_toolkit/src/features/workspace/domain/workspace_state.dart';

part 'workspace_notifier.g.dart';

@Riverpod(keepAlive: true)
class WorkspaceNotifier extends _$WorkspaceNotifier {
  @override
  Future<WorkspaceState> build() async {
    final bootstrapState = ref.watch(launcherBootstrapStateProvider);
    if (!bootstrapState.canUseControlApi) {
      return const WorkspaceState();
    }

    final controlApi = ref.watch(controlApiServiceProvider);
    try {
      final snapshot = await controlApi.fetchWorkspace();
      return WorkspaceState(
        sessions: List<WorkspaceSession>.from(snapshot.sessions),
        focusedModuleId: snapshot.focusedModuleId,
      );
    } catch (_) {
      return const WorkspaceState();
    }
  }

  Future<void> refresh() async {
    final bootstrapState = ref.read(launcherBootstrapStateProvider);
    if (!bootstrapState.canUseControlApi) {
      state = const AsyncData(WorkspaceState());
      return;
    }

    final controlApi = ref.read(controlApiServiceProvider);
    final snapshot = await controlApi.fetchWorkspace();
    state = state.whenData(
      (s) => s.copyWith(
        sessions: List<WorkspaceSession>.from(snapshot.sessions),
        focusedModuleId: snapshot.focusedModuleId,
      ),
    );
  }

  Future<void> ensureDefaultSessionsOnce({
    required List<WorkspaceSession> sessions,
    required String? focusedModuleId,
  }) async {
    final currentState = state.value;
    if (currentState == null || currentState.defaultSessionsEnsured) {
      return;
    }

    if (_workspaceMatches(currentState.sessions, currentState.focusedModuleId,
        sessions, focusedModuleId)) {
      state = state.whenData((s) => s.copyWith(defaultSessionsEnsured: true));
      return;
    }

    final controlApi = ref.read(controlApiServiceProvider);
    final snapshot = await controlApi.updateWorkspace(
      sessions: sessions,
      focusedModuleId: focusedModuleId,
    );

    state = state.whenData(
      (s) => s.copyWith(
        sessions: List<WorkspaceSession>.from(snapshot.sessions),
        focusedModuleId: snapshot.focusedModuleId,
        defaultSessionsEnsured: true,
      ),
    );
  }

  Future<void> openSession(
    String moduleId, {
    required String surfaceMode,
    String? deepLink,
    Map<String, dynamic> restoreState = const <String, dynamic>{},
    String readinessState = 'opening',
  }) async {
    final controlApi = ref.read(controlApiServiceProvider);
    final snapshot = await controlApi.createWorkspaceSession(
      moduleId: moduleId,
      surfaceMode: surfaceMode,
      deepLink: deepLink,
      restoreState: restoreState,
      readinessState: readinessState,
    );
    state = state.whenData(
      (s) => s.copyWith(
        sessions: List<WorkspaceSession>.from(snapshot.sessions),
        focusedModuleId: snapshot.focusedModuleId,
      ),
    );
  }

  Future<void> focusSession(String moduleId) async {
    final currentState = state.value;
    if (currentState == null ||
        !currentState.sessions.any((session) => session.moduleId == moduleId)) {
      return;
    }

    // Optimistic UI update
    state = state.whenData((s) => s.copyWith(focusedModuleId: moduleId));

    final controlApi = ref.read(controlApiServiceProvider);
    final snapshot = await controlApi.updateWorkspace(
      sessions: currentState.sessions,
      focusedModuleId: moduleId,
    );

    state = state.whenData(
      (s) => s.copyWith(
        sessions: List<WorkspaceSession>.from(snapshot.sessions),
        focusedModuleId: snapshot.focusedModuleId,
      ),
    );
  }

  Future<void> updateSession(
    String moduleId, {
    String? deepLink,
    Map<String, dynamic>? restoreState,
    String? readinessState,
  }) async {
    final currentState = state.value;
    if (currentState == null) return;

    final index = currentState.sessions
        .indexWhere((session) => session.moduleId == moduleId);
    if (index == -1) return;

    final updatedSessions = List<WorkspaceSession>.from(currentState.sessions);
    updatedSessions[index] = updatedSessions[index].copyWith(
      deepLink: deepLink,
      restoreState: restoreState,
      readinessState: readinessState,
    );

    // Optimistic UI update
    state = state.whenData((s) => s.copyWith(sessions: updatedSessions));

    final controlApi = ref.read(controlApiServiceProvider);
    final snapshot = await controlApi.updateWorkspace(
      sessions: updatedSessions,
      focusedModuleId: currentState.focusedModuleId,
    );

    state = state.whenData(
      (s) => s.copyWith(
        sessions: List<WorkspaceSession>.from(snapshot.sessions),
        focusedModuleId: snapshot.focusedModuleId,
      ),
    );
  }

  Future<void> closeSession(String moduleId) async {
    final controlApi = ref.read(controlApiServiceProvider);
    final snapshot = await controlApi.deleteWorkspaceSession(moduleId);
    state = state.whenData(
      (s) => s.copyWith(
        sessions: List<WorkspaceSession>.from(snapshot.sessions),
        focusedModuleId: snapshot.focusedModuleId,
      ),
    );
  }

  bool _workspaceMatches(
    List<WorkspaceSession> currentSessions,
    String? currentFocusedModuleId,
    List<WorkspaceSession> targetSessions,
    String? targetFocusedModuleId,
  ) {
    if (currentFocusedModuleId != targetFocusedModuleId ||
        currentSessions.length != targetSessions.length) {
      return false;
    }
    for (var index = 0; index < targetSessions.length; index += 1) {
      final current = currentSessions[index];
      final desired = targetSessions[index];
      if (current.moduleId != desired.moduleId ||
          current.surfaceMode != desired.surfaceMode ||
          current.deepLink != desired.deepLink ||
          !mapEquals(current.restoreState, desired.restoreState) ||
          current.readinessState != desired.readinessState) {
        return false;
      }
    }
    return true;
  }
}
