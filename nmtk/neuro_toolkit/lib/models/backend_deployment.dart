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

class DeploymentJob {
  const DeploymentJob({
    required this.id,
    required this.targetId,
    required this.mode,
    required this.stage,
    required this.percent,
    required this.stageLabel,
    required this.logs,
    this.error = '',
    this.updatedAt,
  });

  final String id;
  final String targetId;
  final String mode;
  final String stage;
  final double percent;
  final String stageLabel;
  final List<String> logs;
  final String error;
  final DateTime? updatedAt;

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
      error: json['error'] as String? ?? '',
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? ''),
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
        'error': error,
        if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
      };

  DeploymentJob copyWith({
    String? stage,
    double? percent,
    String? stageLabel,
    List<String>? logs,
    String? error,
    DateTime? updatedAt,
  }) {
    return DeploymentJob(
      id: id,
      targetId: targetId,
      mode: mode,
      stage: stage ?? this.stage,
      percent: percent ?? this.percent,
      stageLabel: stageLabel ?? this.stageLabel,
      logs: logs ?? this.logs,
      error: error ?? this.error,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
