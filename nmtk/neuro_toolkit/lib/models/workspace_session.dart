class WorkspaceSession {
  const WorkspaceSession({
    required this.moduleId,
    this.surfaceMode = 'embedded',
    this.deepLink,
    this.restoreState = const <String, dynamic>{},
    this.readinessState = 'opening',
  });

  final String moduleId;
  final String surfaceMode;
  final String? deepLink;
  final Map<String, dynamic> restoreState;
  final String readinessState;

  factory WorkspaceSession.fromJson(Map<String, dynamic> json) {
    return WorkspaceSession(
      moduleId: json['moduleId'] as String? ?? '',
      surfaceMode: json['surfaceMode'] as String? ?? 'embedded',
      deepLink: json['deepLink'] as String?,
      restoreState: json['restoreState'] is Map<String, dynamic>
          ? Map<String, dynamic>.from(
              json['restoreState'] as Map<String, dynamic>)
          : const <String, dynamic>{},
      readinessState: json['readinessState'] as String? ?? 'opening',
    );
  }

  Map<String, dynamic> toJson() => {
        'moduleId': moduleId,
        'surfaceMode': surfaceMode,
        'deepLink': deepLink,
        'restoreState': restoreState,
        'readinessState': readinessState,
      };

  WorkspaceSession copyWith({
    String? moduleId,
    String? surfaceMode,
    Object? deepLink = const Object(),
    Map<String, dynamic>? restoreState,
    String? readinessState,
  }) {
    return WorkspaceSession(
      moduleId: moduleId ?? this.moduleId,
      surfaceMode: surfaceMode ?? this.surfaceMode,
      deepLink: deepLink is String? ? deepLink : this.deepLink,
      restoreState: restoreState ?? this.restoreState,
      readinessState: readinessState ?? this.readinessState,
    );
  }
}

class WorkspaceSnapshot {
  const WorkspaceSnapshot({
    required this.sessions,
    required this.focusedModuleId,
  });

  final List<WorkspaceSession> sessions;
  final String? focusedModuleId;

  factory WorkspaceSnapshot.fromJson(Map<String, dynamic> json) {
    final rawSessions = json['sessions'] as List<dynamic>? ?? const <dynamic>[];
    return WorkspaceSnapshot(
      sessions: rawSessions
          .whereType<Map<String, dynamic>>()
          .map(WorkspaceSession.fromJson)
          .toList(growable: false),
      focusedModuleId: json['focusedModuleId'] as String?,
    );
  }
}
