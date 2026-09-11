class DeploymentTarget {
  const DeploymentTarget({
    required this.id,
    required this.displayName,
    required this.targetType,
    required this.mode,
    required this.authMode,
    required this.backendPort,
    this.host = '',
    this.sshPort = 22,
    this.username = '',
    this.installRoot = '',
    this.namespace = '',
    this.context = '',
    this.apiServer = '',
    this.imageTag = 'latest',
    this.domain = '',
    this.containerEngine = 'docker',
    this.lastReadiness = 'unknown',
    this.lastDeployedVersion = '',
    this.lastFailureReason = '',
    this.updatedAt,
    this.moduleEnvironment = const <String, String>{},
  });

  final String id;
  final String displayName;
  final String targetType;
  final String mode;
  final String authMode;
  final String host;
  final int sshPort;
  final String username;
  final String installRoot;
  final int backendPort;
  final String namespace;
  final String context;
  final String apiServer;
  final String imageTag;
  final String domain;
  final String containerEngine;
  final String lastReadiness;
  final String lastDeployedVersion;
  final String lastFailureReason;
  final DateTime? updatedAt;
  final Map<String, String> moduleEnvironment;

  factory DeploymentTarget.fromJson(Map<String, dynamic> json) {
    return DeploymentTarget(
      id: json['id'] as String? ?? '',
      displayName: json['displayName'] as String? ?? '',
      targetType: json['targetType'] as String? ?? 'local',
      mode: json['mode'] as String? ?? 'standalone',
      authMode: json['authMode'] as String? ?? 'none',
      host: json['host'] as String? ?? '',
      sshPort: json['sshPort'] as int? ?? 22,
      username: json['username'] as String? ?? '',
      installRoot: json['installRoot'] as String? ?? '',
      backendPort: json['backendPort'] as int? ?? 9000,
      namespace: json['namespace'] as String? ?? '',
      context: json['context'] as String? ?? '',
      apiServer: json['apiServer'] as String? ?? '',
      imageTag: json['imageTag'] as String? ?? 'latest',
      domain: json['domain'] as String? ?? '',
      containerEngine: json['containerEngine'] as String? ?? 'docker',
      lastReadiness: json['lastReadiness'] as String? ?? 'unknown',
      lastDeployedVersion: json['lastDeployedVersion'] as String? ?? '',
      lastFailureReason: json['lastFailureReason'] as String? ?? '',
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? ''),
      moduleEnvironment: _stringMap(json['moduleEnvironment']),
    );
  }

  static Map<String, String> _stringMap(Object? value) {
    if (value is! Map) return const {};
    return value.map(
      (dynamic key, dynamic item) => MapEntry(key.toString(), item.toString()),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'displayName': displayName,
    'targetType': targetType,
    'mode': mode,
    'authMode': authMode,
    'host': host,
    'sshPort': sshPort,
    'username': username,
    'installRoot': installRoot,
    'backendPort': backendPort,
    'namespace': namespace,
    'context': context,
    'apiServer': apiServer,
    'imageTag': imageTag,
    'domain': domain,
    'containerEngine': containerEngine,
    'lastReadiness': lastReadiness,
    'lastDeployedVersion': lastDeployedVersion,
    'lastFailureReason': lastFailureReason,
    if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
    if (moduleEnvironment.isNotEmpty) 'moduleEnvironment': moduleEnvironment,
  };

  DeploymentTarget copyWith({
    String? host,
    String? apiServer,
    String? lastReadiness,
    String? lastFailureReason,
    DateTime? updatedAt,
  }) {
    return DeploymentTarget(
      id: id,
      displayName: displayName,
      targetType: targetType,
      mode: mode,
      authMode: authMode,
      backendPort: backendPort,
      host: host ?? this.host,
      sshPort: sshPort,
      username: username,
      installRoot: installRoot,
      namespace: namespace,
      context: context,
      apiServer: apiServer ?? this.apiServer,
      imageTag: imageTag,
      domain: domain,
      containerEngine: containerEngine,
      lastReadiness: lastReadiness ?? this.lastReadiness,
      lastDeployedVersion: lastDeployedVersion,
      lastFailureReason: lastFailureReason ?? this.lastFailureReason,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

class DeploymentPreflightResult {
  const DeploymentPreflightResult({
    required this.status,
    required this.message,
    required this.blockingFindings,
    required this.degradedFindings,
    required this.suggestedRecovery,
  });

  final String status;
  final String message;
  final List<String> blockingFindings;
  final List<String> degradedFindings;
  final String suggestedRecovery;

  factory DeploymentPreflightResult.fromJson(Map<String, dynamic> json) {
    return DeploymentPreflightResult(
      status: json['status'] as String? ?? 'failed',
      message: json['message'] as String? ?? '',
      blockingFindings:
          (json['blockingFindings'] as List<dynamic>? ?? const <dynamic>[])
              .map((dynamic value) => value.toString())
              .toList(growable: false),
      degradedFindings:
          (json['degradedFindings'] as List<dynamic>? ?? const <dynamic>[])
              .map((dynamic value) => value.toString())
              .toList(growable: false),
      suggestedRecovery: json['suggestedRecovery'] as String? ?? '',
    );
  }
}

class RemoteUserBootstrapResult {
  const RemoteUserBootstrapResult({
    required this.username,
    required this.sshPrivateKey,
  });

  final String username;
  final String sshPrivateKey;

  factory RemoteUserBootstrapResult.fromJson(Map<String, dynamic> json) {
    return RemoteUserBootstrapResult(
      username: json['username'] as String? ?? '',
      sshPrivateKey: json['sshPrivateKey'] as String? ?? '',
    );
  }
}

class DeploymentFailureDetails {
  const DeploymentFailureDetails({
    required this.code,
    required this.phase,
    required this.summary,
    required this.recovery,
    this.technicalDetails = '',
    this.exitCode,
    this.existingConnectionReachable,
  });

  final String code;
  final String phase;
  final String summary;
  final String recovery;
  final String technicalDetails;
  final int? exitCode;
  final bool? existingConnectionReachable;

  factory DeploymentFailureDetails.fromJson(Map<String, dynamic> json) {
    return DeploymentFailureDetails(
      code: json['code'] as String? ?? 'unknown_setup_failure',
      phase: json['phase'] as String? ?? 'failed',
      summary: json['summary'] as String? ?? 'Server setup failed.',
      recovery: json['recovery'] as String? ?? 'Review the details and retry.',
      technicalDetails: json['technicalDetails'] as String? ?? '',
      exitCode: json['exitCode'] as int?,
      existingConnectionReachable: json['existingConnectionReachable'] as bool?,
    );
  }

  Map<String, dynamic> toJson() => {
    'code': code,
    'phase': phase,
    'summary': summary,
    'recovery': recovery,
    'technicalDetails': technicalDetails,
    if (exitCode != null) 'exitCode': exitCode,
    if (existingConnectionReachable != null)
      'existingConnectionReachable': existingConnectionReachable,
  };

  DeploymentFailureDetails copyWithConnection(bool reachable) {
    return DeploymentFailureDetails(
      code: code,
      phase: phase,
      summary: summary,
      recovery: recovery,
      technicalDetails: technicalDetails,
      exitCode: exitCode,
      existingConnectionReachable: reachable,
    );
  }
}

class DeploymentActiveOperation {
  const DeploymentActiveOperation({
    required this.label,
    required this.startedAt,
    required this.timeoutSeconds,
    this.automaticRecovery = false,
  });

  final String label;
  final DateTime startedAt;
  final int timeoutSeconds;
  final bool automaticRecovery;

  factory DeploymentActiveOperation.fromJson(Map<String, dynamic> json) {
    return DeploymentActiveOperation(
      label: json['label'] as String? ?? 'Preparing server',
      startedAt:
          DateTime.tryParse(json['startedAt'] as String? ?? '') ??
          DateTime.now(),
      timeoutSeconds: json['timeoutSeconds'] as int? ?? 0,
      automaticRecovery: json['automaticRecovery'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
    'label': label,
    'startedAt': startedAt.toIso8601String(),
    'timeoutSeconds': timeoutSeconds,
    'automaticRecovery': automaticRecovery,
  };
}

class DeploymentJob {
  const DeploymentJob({
    required this.id,
    required this.targetId,
    required this.mode,
    required this.stage,
    required this.percent,
    required this.stageLabel,
    required this.logs,
    this.terminalOutput = const [],
    this.requiresEphemeralAdministrator = false,
    this.error = '',
    this.bundleVersion = 0,
    this.bundleManifestHash = '',
    this.imageTag = 'latest',
    this.updatedAt,
    this.lastProgressAt,
    this.failureDetails,
    this.activeOperation,
  });

  final String id;
  final String targetId;
  final String mode;
  final String stage;
  final double percent;
  final String stageLabel;
  final List<String> logs;
  final List<String> terminalOutput;
  final bool requiresEphemeralAdministrator;
  final String error;
  final int bundleVersion;
  final String bundleManifestHash;
  final String imageTag;
  final DateTime? updatedAt;

  /// When the deployment last reported something genuinely new — a stage, a
  /// percentage, or a line of server output.
  ///
  /// Distinct from [updatedAt], which also moves for liveness heartbeats and
  /// re-reads of unchanged state. Stall detection must use this one, otherwise a
  /// deployment that has stopped making progress still looks fresh.
  final DateTime? lastProgressAt;
  final DeploymentFailureDetails? failureDetails;
  final DeploymentActiveOperation? activeOperation;

  bool get isTerminal =>
      stage == 'completed' || stage == 'failed' || stage == 'cancelled';

  factory DeploymentJob.fromJson(Map<String, dynamic> json) {
    return DeploymentJob(
      id: json['id'] as String? ?? '',
      targetId: json['targetId'] as String? ?? '',
      mode: json['mode'] as String? ?? 'standalone',
      stage: json['stage'] as String? ?? 'queued',
      percent: (json['percent'] as num?)?.toDouble() ?? 0,
      stageLabel: json['stageLabel'] as String? ?? '',
      logs: (json['logs'] as List<dynamic>? ?? const <dynamic>[])
          .map((dynamic value) => value.toString())
          .toList(growable: false),
      terminalOutput:
          (json['terminalOutput'] as List<dynamic>? ?? const <dynamic>[])
              .map((dynamic value) => value.toString())
              .toList(growable: false),
      requiresEphemeralAdministrator:
          json['requiresEphemeralAdministrator'] as bool? ?? false,
      error: json['error'] as String? ?? '',
      bundleVersion: json['bundleVersion'] as int? ?? 0,
      bundleManifestHash: json['bundleManifestHash'] as String? ?? '',
      imageTag: json['imageTag'] as String? ?? 'latest',
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? ''),
      lastProgressAt: DateTime.tryParse(
        json['lastProgressAt'] as String? ?? '',
      ),
      failureDetails: json['failureDetails'] is Map<String, dynamic>
          ? DeploymentFailureDetails.fromJson(
              json['failureDetails'] as Map<String, dynamic>,
            )
          : null,
      activeOperation: json['activeOperation'] is Map<String, dynamic>
          ? DeploymentActiveOperation.fromJson(
              json['activeOperation'] as Map<String, dynamic>,
            )
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'targetId': targetId,
    'mode': mode,
    'stage': stage,
    'percent': percent,
    'stageLabel': stageLabel,
    'logs': logs,
    'terminalOutput': terminalOutput,
    'requiresEphemeralAdministrator': requiresEphemeralAdministrator,
    'error': error,
    'bundleVersion': bundleVersion,
    'bundleManifestHash': bundleManifestHash,
    'imageTag': imageTag,
    if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
    if (lastProgressAt != null)
      'lastProgressAt': lastProgressAt!.toIso8601String(),
    if (failureDetails != null) 'failureDetails': failureDetails!.toJson(),
    if (activeOperation != null) 'activeOperation': activeOperation!.toJson(),
  };

  DeploymentJob copyWith({
    String? stage,
    double? percent,
    String? stageLabel,
    List<String>? logs,
    List<String>? terminalOutput,
    bool? requiresEphemeralAdministrator,
    String? error,
    int? bundleVersion,
    String? bundleManifestHash,
    String? imageTag,
    DateTime? updatedAt,
    DateTime? lastProgressAt,
    DeploymentFailureDetails? failureDetails,
    bool clearFailureDetails = false,
    DeploymentActiveOperation? activeOperation,
    bool clearActiveOperation = false,
  }) {
    return DeploymentJob(
      id: id,
      targetId: targetId,
      mode: mode,
      stage: stage ?? this.stage,
      percent: percent ?? this.percent,
      stageLabel: stageLabel ?? this.stageLabel,
      logs: logs ?? this.logs,
      terminalOutput: terminalOutput ?? this.terminalOutput,
      requiresEphemeralAdministrator:
          requiresEphemeralAdministrator ?? this.requiresEphemeralAdministrator,
      error: error ?? this.error,
      bundleVersion: bundleVersion ?? this.bundleVersion,
      bundleManifestHash: bundleManifestHash ?? this.bundleManifestHash,
      imageTag: imageTag ?? this.imageTag,
      updatedAt: updatedAt ?? this.updatedAt,
      lastProgressAt: lastProgressAt ?? this.lastProgressAt,
      failureDetails: clearFailureDetails
          ? null
          : failureDetails ?? this.failureDetails,
      activeOperation: clearActiveOperation
          ? null
          : activeOperation ?? this.activeOperation,
    );
  }
}
