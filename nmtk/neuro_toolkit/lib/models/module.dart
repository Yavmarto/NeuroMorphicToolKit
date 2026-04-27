enum ModuleStatus {
  notInstalled,
  installing,
  installed,
  starting,
  running,
  stopping,
  error,
  degraded,
  updating,
}

class AkidaRuntimeConfig {
  const AkidaRuntimeConfig({
    required this.supportedPlatforms,
    required this.pythonRange,
    required this.requiredPackages,
    required this.docsUrl,
    this.localModeFallback = 'simulator_only',
  });

  final List<String> supportedPlatforms;
  final String pythonRange;
  final List<String> requiredPackages;
  final String docsUrl;
  final String localModeFallback;

  factory AkidaRuntimeConfig.fromJson(Map<String, dynamic> json) {
    return AkidaRuntimeConfig(
      supportedPlatforms:
          (json['supportedPlatforms'] as List<dynamic>? ?? const <dynamic>[])
              .map((dynamic value) => value.toString())
              .toList(growable: false),
      pythonRange: json['pythonRange'] as String? ?? '>=3.10,<3.13',
      requiredPackages:
          (json['requiredPackages'] as List<dynamic>? ?? const <dynamic>[])
              .map((dynamic value) => value.toString())
              .toList(growable: false),
      docsUrl: json['docsUrl'] as String? ?? '',
      localModeFallback:
          json['localModeFallback'] as String? ?? 'simulator_only',
    );
  }

  Map<String, dynamic> toJson() => {
        'supportedPlatforms': supportedPlatforms,
        'pythonRange': pythonRange,
        'requiredPackages': requiredPackages,
        'docsUrl': docsUrl,
        'localModeFallback': localModeFallback,
      };
}

class AkidaRuntimeState {
  const AkidaRuntimeState({
    required this.status,
    this.message,
    this.preparedAt,
  });

  final String status;
  final String? message;
  final String? preparedAt;

  factory AkidaRuntimeState.fromJson(Map<String, dynamic> json) {
    return AkidaRuntimeState(
      status: json['status'] as String? ?? 'idle',
      message: json['message'] as String?,
      preparedAt: json['preparedAt'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'status': status,
        'message': message,
        'preparedAt': preparedAt,
      };
}

class Module {
  final String id;
  final String name;
  final String description;
  final String icon;
  final String directory;
  final int? port;
  final bool hasFrontend;
  final String frontendStatus;
  final bool requiresMuJoCo;
  final String sourcePath;
  final String runPath;
  final String uvicornTarget;
  final List<String> localDeps;
  final String version;
  final String remoteVersion;
  final bool versionPinned;
  final String? remoteUrl;
  final bool isEnabled;
  final int? customPort;
  final bool startOnLaunch;
  final List<String> requiredImports;
  final List<String> optionalImports;
  final String installStrategy;
  final String startStrategy;
  final AkidaRuntimeConfig? akidaRuntime;
  final AkidaRuntimeState? akidaRuntimeState;
  String preflightStatus;
  String? preflightMessage;
  List<String> capabilityWarnings;
  String? environmentFingerprint;
  ModuleStatus status;
  double installProgress;
  String? healthStatus;

  Module({
    required this.id,
    required this.name,
    required this.description,
    this.icon = 'extension',
    required this.directory,
    this.port,
    this.hasFrontend = false,
    this.frontendStatus = 'No',
    this.requiresMuJoCo = false,
    this.sourcePath = '.',
    this.runPath = '.',
    this.uvicornTarget = '',
    this.localDeps = const [],
    this.version = '0.0.0',
    this.remoteVersion = '0.0.0',
    this.versionPinned = false,
    this.remoteUrl,
    this.isEnabled = true,
    this.customPort,
    this.startOnLaunch = false,
    this.requiredImports = const [],
    this.optionalImports = const [],
    this.installStrategy = 'pip',
    this.startStrategy = 'none',
    this.akidaRuntime,
    this.akidaRuntimeState,
    this.preflightStatus = 'ok',
    this.preflightMessage,
    this.capabilityWarnings = const [],
    this.environmentFingerprint,
    this.status = ModuleStatus.notInstalled,
    this.installProgress = 0.0,
    this.healthStatus,
  });

  factory Module.fromJson(Map<String, dynamic> json) {
    return Module(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String,
      icon: json['icon'] as String? ?? 'extension',
      directory:
          json['installPath'] as String? ?? json['directory'] as String? ?? '',
      port: json['port'] as int?,
      hasFrontend: json['hasFrontend'] as bool? ?? false,
      frontendStatus: json['frontendStatus'] as String? ?? 'No',
      requiresMuJoCo: json['requiresMuJoCo'] as bool? ?? false,
      sourcePath: json['sourcePath'] as String? ?? '.',
      runPath:
          json['runPath'] as String? ?? json['sourcePath'] as String? ?? '.',
      uvicornTarget: json['uvicornTarget'] as String? ?? '',
      localDeps:
          (json['localDeps'] as List<dynamic>?)?.cast<String>() ?? const [],
      version: json['version'] as String? ?? '0.0.0',
      remoteVersion: json['remoteVersion'] as String? ?? '0.0.0',
      versionPinned: json['versionPinned'] as bool? ?? false,
      remoteUrl: json['remoteUrl'] as String?,
      isEnabled: json['isEnabled'] as bool? ?? true,
      customPort: json['customPort'] as int?,
      startOnLaunch: json['startOnLaunch'] as bool? ?? false,
      requiredImports:
          (json['requiredImports'] as List<dynamic>?)?.cast<String>() ??
              const [],
      optionalImports:
          (json['optionalImports'] as List<dynamic>?)?.cast<String>() ??
              const [],
      installStrategy: json['installStrategy'] as String? ?? 'pip',
      startStrategy: json['startStrategy'] as String? ?? 'none',
      akidaRuntime: json['akidaRuntime'] is Map<String, dynamic>
          ? AkidaRuntimeConfig.fromJson(
              json['akidaRuntime'] as Map<String, dynamic>,
            )
          : null,
      akidaRuntimeState: json['akidaRuntimeState'] is Map<String, dynamic>
          ? AkidaRuntimeState.fromJson(
              json['akidaRuntimeState'] as Map<String, dynamic>,
            )
          : null,
      preflightStatus: json['preflightStatus'] as String? ?? 'ok',
      preflightMessage: json['preflightMessage'] as String?,
      capabilityWarnings:
          (json['capabilityWarnings'] as List<dynamic>?)?.cast<String>() ??
              const [],
      environmentFingerprint: json['environmentFingerprint'] as String?,
      status: json['status'] != null
          ? ModuleStatus.values[json['status'] as int]
          : ModuleStatus.notInstalled,
      installProgress: (json['installProgress'] as num?)?.toDouble() ?? 0.0,
      healthStatus: json['healthStatus'] as String?,
    );
  }

  Module copyWith({
    String? id,
    String? name,
    String? description,
    String? icon,
    String? directory,
    int? port,
    bool? hasFrontend,
    String? frontendStatus,
    bool? requiresMuJoCo,
    String? sourcePath,
    String? runPath,
    String? uvicornTarget,
    List<String>? localDeps,
    String? version,
    String? remoteVersion,
    bool? versionPinned,
    Object? remoteUrl = const Object(),
    bool? isEnabled,
    Object? customPort = const Object(),
    bool? startOnLaunch,
    List<String>? requiredImports,
    List<String>? optionalImports,
    String? installStrategy,
    String? startStrategy,
    Object? akidaRuntime = const Object(),
    Object? akidaRuntimeState = const Object(),
    String? preflightStatus,
    Object? preflightMessage = const Object(),
    List<String>? capabilityWarnings,
    Object? environmentFingerprint = const Object(),
    ModuleStatus? status,
    double? installProgress,
    Object? healthStatus = const Object(),
  }) {
    return Module(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      icon: icon ?? this.icon,
      directory: directory ?? this.directory,
      port: port ?? this.port,
      hasFrontend: hasFrontend ?? this.hasFrontend,
      frontendStatus: frontendStatus ?? this.frontendStatus,
      requiresMuJoCo: requiresMuJoCo ?? this.requiresMuJoCo,
      sourcePath: sourcePath ?? this.sourcePath,
      runPath: runPath ?? this.runPath,
      uvicornTarget: uvicornTarget ?? this.uvicornTarget,
      localDeps: localDeps ?? this.localDeps,
      version: version ?? this.version,
      remoteVersion: remoteVersion ?? this.remoteVersion,
      versionPinned: versionPinned ?? this.versionPinned,
      remoteUrl: remoteUrl is String? ? remoteUrl : this.remoteUrl,
      isEnabled: isEnabled ?? this.isEnabled,
      customPort: customPort is int? ? customPort : this.customPort,
      startOnLaunch: startOnLaunch ?? this.startOnLaunch,
      requiredImports: requiredImports ?? this.requiredImports,
      optionalImports: optionalImports ?? this.optionalImports,
      installStrategy: installStrategy ?? this.installStrategy,
      startStrategy: startStrategy ?? this.startStrategy,
      akidaRuntime: akidaRuntime is AkidaRuntimeConfig?
          ? akidaRuntime
          : this.akidaRuntime,
      akidaRuntimeState: akidaRuntimeState is AkidaRuntimeState?
          ? akidaRuntimeState
          : this.akidaRuntimeState,
      preflightStatus: preflightStatus ?? this.preflightStatus,
      preflightMessage: preflightMessage is String?
          ? preflightMessage
          : this.preflightMessage,
      capabilityWarnings: capabilityWarnings ?? this.capabilityWarnings,
      environmentFingerprint: environmentFingerprint is String?
          ? environmentFingerprint
          : this.environmentFingerprint,
      status: status ?? this.status,
      installProgress: installProgress ?? this.installProgress,
      healthStatus: healthStatus is String? ? healthStatus : this.healthStatus,
    );
  }

  int? get effectivePort => customPort ?? port;

  bool get isPreflightFailed => preflightStatus == 'failed';

  bool get isPreflightDegraded => preflightStatus == 'degraded';

  String? get statusMessage {
    if (preflightMessage != null && preflightMessage!.isNotEmpty) {
      return preflightMessage;
    }
    if (capabilityWarnings.isNotEmpty) {
      return capabilityWarnings.join(' | ');
    }
    return healthStatus;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'icon': icon,
        'directory': directory,
        'port': port,
        'hasFrontend': hasFrontend,
        'frontendStatus': frontendStatus,
        'requiresMuJoCo': requiresMuJoCo,
        'sourcePath': sourcePath,
        'runPath': runPath,
        'uvicornTarget': uvicornTarget,
        'version': version,
        'remoteVersion': remoteVersion,
        'versionPinned': versionPinned,
        'remoteUrl': remoteUrl,
        'isEnabled': isEnabled,
        'customPort': customPort,
        'startOnLaunch': startOnLaunch,
        'requiredImports': requiredImports,
        'optionalImports': optionalImports,
        'installStrategy': installStrategy,
        'startStrategy': startStrategy,
        'akidaRuntime': akidaRuntime?.toJson(),
        'akidaRuntimeState': akidaRuntimeState?.toJson(),
        'preflightStatus': preflightStatus,
        'preflightMessage': preflightMessage,
        'capabilityWarnings': capabilityWarnings,
        'environmentFingerprint': environmentFingerprint,
        'status': status.index,
        'installProgress': installProgress,
        'healthStatus': healthStatus,
      };
}
