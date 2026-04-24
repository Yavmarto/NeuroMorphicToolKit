import 'package:flutter/foundation.dart';
import 'package:neuro_toolkit/models/workspace_session.dart';
import 'package:neuro_toolkit/services/control_api_service.dart';

class WorkspaceProvider with ChangeNotifier {
  WorkspaceProvider({ControlApiService? controlApiService})
      : _controlApiService = controlApiService ?? ControlApiService() {
    _init();
  }

  final ControlApiService _controlApiService;
  List<WorkspaceSession> _sessions = <WorkspaceSession>[];
  String? _focusedModuleId;
  bool _isLoading = true;

  List<WorkspaceSession> get sessions =>
      List<WorkspaceSession>.unmodifiable(_sessions);
  String? get focusedModuleId => _focusedModuleId;
  bool get isLoading => _isLoading;
  bool get hasSessions => _sessions.isNotEmpty;

  Future<void> _init() async {
    try {
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
    final snapshot = await _controlApiService.fetchWorkspace();
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
}
