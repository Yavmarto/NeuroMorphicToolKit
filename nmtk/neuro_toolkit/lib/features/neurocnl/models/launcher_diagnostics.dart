class LauncherDiagnostics {
  const LauncherDiagnostics({
    required this.available,
    this.suiteApiStatus,
    this.suiteApiMessage,
    this.logLines = const <String>[],
    this.errorMessage,
  });

  final bool available;
  final String? suiteApiStatus;
  final String? suiteApiMessage;
  final List<String> logLines;
  final String? errorMessage;

  factory LauncherDiagnostics.fromJson(
    Map<String, dynamic> settings,
    Map<String, dynamic> logs,
  ) {
    final rawLines = logs['lines'] as List<dynamic>? ?? const <dynamic>[];
    return LauncherDiagnostics(
      available: true,
      suiteApiStatus: settings['suiteApiStatus'] as String?,
      suiteApiMessage: settings['suiteApiMessage'] as String?,
      logLines: rawLines.whereType<String>().toList(growable: false),
    );
  }

  factory LauncherDiagnostics.unavailable(String message) =>
      LauncherDiagnostics(available: false, errorMessage: message);
}
