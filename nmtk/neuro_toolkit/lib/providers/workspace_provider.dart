// TODO(riverpod-migration): Migrate WorkspaceProvider to AsyncNotifier<WorkspaceState>.
//
// Steps:
//   1. Create immutable WorkspaceState {sessions, focusedModuleId, isLoading, hasSessions}
//   2. Replace `class WorkspaceProvider with ChangeNotifier` with
//      `class WorkspaceNotifier extends AsyncNotifier<WorkspaceState>`
//   3. Move _init() logic into build() — notifyListeners() calls become
//      `state = AsyncData(newState)`
//   4. Update workspaceStateProvider from ChangeNotifierProvider to AsyncNotifierProvider
//   5. Update all call sites in tool_view.dart (24+ references) to use
//      `ref.watch(workspaceStateProvider).valueOrNull?.sessions` etc.
//   6. Update module_tab_bar.dart similarly
//
// Do this on a dedicated branch; tool_view.dart needs simultaneous changes.

import 'package:flutter/foundation.dart';
import 'package:neuro_toolkit/models/workspace_session.dart';
import 'package:neuro_toolkit/services/control_api_service.dart';
import 'package:neuro_toolkit/services/launcher_control_bootstrap_service.dart';

class WorkspaceProvider with ChangeNotifier {
  WorkspaceProvider({
    ControlApiService? controlApiService,
    LauncherBootstrapState? bootstrapState,
  })  : _controlApiService = controlApiService ?? ControlApiService(),
        _bootstrapState = bootstrapState ??
            LauncherBootstrapState.ready(ControlApiService.resolveBaseUri()) {
    _init();
  }

  final ControlApiService _controlApiService;
  final LauncherBootstrapState _bootstrapState;
  List<WorkspaceSession> _sessions = <WorkspaceSession>[];
  String? _focusedModuleId;
  bool _isLoading = true;
  bool _defaultSessionsEnsured = false;

  List<WorkspaceSession> get sessions =>
      List<WorkspaceSession>.unmodifiable(_sessions);
  String? get focusedModuleId => _focusedModuleId;
  bool get isLoading => _isLoading;
  bool get hasSessions => _sessions.isNotEmpty;

  Future<void> _init() async {
    try {
      if (!_bootstrapState.canUseControlApi) {
        _sessions = <WorkspaceSession>[];
        _focusedModuleId = null;
        return;
      }
      await refresh();
    } catch (_) {
      _sessions = <WorkspaceSession>[];
      _focusedModuleId = null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> refresh() async {
    if (!_bootstrapState.canUseControlApi) {
      _sessions = <WorkspaceSession>[];
      _focusedModuleId = null;
      notifyListeners();
      return;
    }
    final snapshot = await _controlApiService.fetchWorkspace();
    _sessions = List<WorkspaceSession>.from(snapshot.sessions);
    _focusedModuleId = snapshot.focusedModuleId;
    notifyListeners();
  }

  Future<void> ensureDefaultSessionsOnce({
    required List<WorkspaceSession> sessions,
    required String? focusedModuleId,
  }) async {
    if (_defaultSessionsEnsured) {
      return;
    }
    _defaultSessionsEnsured = true;
    if (_workspaceMatches(sessions, focusedModuleId)) {
      return;
    }
    final snapshot = await _controlApiService.updateWorkspace(
      sessions: sessions,
      focusedModuleId: focusedModuleId,
    );
    _sessions = List<WorkspaceSession>.from(snapshot.sessions);
    _focusedModuleId = snapshot.focusedModuleId;
    notifyListeners();
  }

  Future<void> openSession(
    String moduleId, {
    required String surfaceMode,
    String? deepLink,
    Map<String, dynamic> restoreState = const <String, dynamic>{},
    String readinessState = 'opening',
  }) async {
    final snapshot = await _controlApiService.createWorkspaceSession(
      moduleId: moduleId,
      surfaceMode: surfaceMode,
      deepLink: deepLink,
      restoreState: restoreState,
      readinessState: readinessState,
    );
    _sessions = List<WorkspaceSession>.from(snapshot.sessions);
    _focusedModuleId = snapshot.focusedModuleId;
    notifyListeners();
  }

  Future<void> focusSession(String moduleId) async {
    if (!_sessions.any((session) => session.moduleId == moduleId)) {
      return;
    }
    _focusedModuleId = moduleId;
    notifyListeners();
    final snapshot = await _controlApiService.updateWorkspace(
      sessions: _sessions,
      focusedModuleId: moduleId,
    );
    _sessions = List<WorkspaceSession>.from(snapshot.sessions);
    _focusedModuleId = snapshot.focusedModuleId;
    notifyListeners();
  }

  Future<void> updateSession(
    String moduleId, {
    String? deepLink,
    Map<String, dynamic>? restoreState,
    String? readinessState,
  }) async {
    final index =
        _sessions.indexWhere((session) => session.moduleId == moduleId);
    if (index == -1) {
      return;
    }
    _sessions[index] = _sessions[index].copyWith(
      deepLink: deepLink,
      restoreState: restoreState,
      readinessState: readinessState,
    );
    notifyListeners();
    final snapshot = await _controlApiService.updateWorkspace(
      sessions: _sessions,
      focusedModuleId: _focusedModuleId,
    );
    _sessions = List<WorkspaceSession>.from(snapshot.sessions);
    _focusedModuleId = snapshot.focusedModuleId;
    notifyListeners();
  }

  Future<void> closeSession(String moduleId) async {
    final snapshot = await _controlApiService.deleteWorkspaceSession(moduleId);
    _sessions = List<WorkspaceSession>.from(snapshot.sessions);
    _focusedModuleId = snapshot.focusedModuleId;
    notifyListeners();
  }

  bool _workspaceMatches(
    List<WorkspaceSession> sessions,
    String? focusedModuleId,
  ) {
    if (_focusedModuleId != focusedModuleId ||
        _sessions.length != sessions.length) {
      return false;
    }
    for (var index = 0; index < sessions.length; index += 1) {
      final current = _sessions[index];
      final desired = sessions[index];
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
