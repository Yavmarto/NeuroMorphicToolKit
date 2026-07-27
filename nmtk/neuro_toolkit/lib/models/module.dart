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

class PynqLauncherRuntimeConfig {
  const PynqLauncherRuntimeConfig({
    required this.runtimePort,
    required this.sshPort,
    required this.defaultUsername,
    required this.defaultState,
    required this.defaultAuthMode,
    required this.legacyInstallRoot,
    required this.installRootTemplate,
    required this.agentVenvDirName,
    required this.runtimeVenvDirName,
    required this.overlayDirName,
    required this.serviceName,
    required this.agentExecutableName,
    required this.installStatusFilename,
    required this.runtimeLogFilename,
    required this.overlayStagingSubdir,
  });

  final int runtimePort;
  final int sshPort;
  final String defaultUsername;
  final String defaultState;
  final String defaultAuthMode;
  final String legacyInstallRoot;
  final String installRootTemplate;
  final String agentVenvDirName;
  final String runtimeVenvDirName;
  final String overlayDirName;
  final String serviceName;
  final String agentExecutableName;
  final String installStatusFilename;
  final String runtimeLogFilename;
  final String overlayStagingSubdir;

  factory PynqLauncherRuntimeConfig.fromJson(Map<String, dynamic> json) {
    return PynqLauncherRuntimeConfig(
      runtimePort: json['runtimePort'] as int? ?? 8002,
      sshPort: json['sshPort'] as int? ?? 22,
      defaultUsername: json['defaultUsername'] as String? ?? 'xilinx',
      defaultState: json['defaultState'] as String? ?? 'unpaired',
      defaultAuthMode: json['defaultAuthMode'] as String? ?? 'password',
      legacyInstallRoot:
          json['legacyInstallRoot'] as String? ?? '/opt/neurochip-pynq-agent',
      installRootTemplate: json['installRootTemplate'] as String? ??
          '/home/{username}/.local/share/neurochip-pynq-agent',
      agentVenvDirName: json['agentVenvDirName'] as String? ?? 'venv',
      runtimeVenvDirName: json['runtimeVenvDirName'] as String? ?? 'pynq-venv',
      overlayDirName: json['overlayDirName'] as String? ?? 'overlays',
      serviceName: json['serviceName'] as String? ?? 'neurochip-pynq-agent',
      agentExecutableName:
          json['agentExecutableName'] as String? ?? 'neurochip-pynq-agent',
      installStatusFilename:
          json['installStatusFilename'] as String? ?? 'install-status.json',
      runtimeLogFilename:
          json['runtimeLogFilename'] as String? ?? 'runtime.log',
      overlayStagingSubdir:
          json['overlayStagingSubdir'] as String? ?? 'overlay_staging/pynq_z2',
    );
  }

  Map<String, dynamic> toJson() => {
        'runtimePort': runtimePort,
        'sshPort': sshPort,
        'defaultUsername': defaultUsername,
        'defaultState': defaultState,
        'defaultAuthMode': defaultAuthMode,
        'legacyInstallRoot': legacyInstallRoot,
        'installRootTemplate': installRootTemplate,
        'agentVenvDirName': agentVenvDirName,
        'runtimeVenvDirName': runtimeVenvDirName,
        'overlayDirName': overlayDirName,
        'serviceName': serviceName,
        'agentExecutableName': agentExecutableName,
        'installStatusFilename': installStatusFilename,
        'runtimeLogFilename': runtimeLogFilename,
        'overlayStagingSubdir': overlayStagingSubdir,
      };
}

class AkidaLauncherRuntimeConfig {
  const AkidaLauncherRuntimeConfig({
    required this.runtimePort,
    required this.controlPort,
    required this.sshPort,
    required this.defaultState,
    required this.defaultAuthMode,
    required this.installRoot,
    required this.serviceUser,
    required this.venvDirName,
    required this.runtimeServiceName,
    required this.controlServiceName,
    required this.tokenRelativePath,
    required this.installStatusRelativePath,
  });

  final int runtimePort;
  final int controlPort;
  final int sshPort;
  final String defaultState;
  final String defaultAuthMode;
  final String installRoot;
  final String serviceUser;
  final String venvDirName;
  final String runtimeServiceName;
  final String controlServiceName;
  final String tokenRelativePath;
  final String installStatusRelativePath;

  factory AkidaLauncherRuntimeConfig.fromJson(Map<String, dynamic> json) {
    return AkidaLauncherRuntimeConfig(
      runtimePort: json['runtimePort'] as int? ?? 8002,
      controlPort: json['controlPort'] as int? ?? 8091,
      sshPort: json['sshPort'] as int? ?? 22,
      defaultState: json['defaultState'] as String? ?? 'unknown',
      defaultAuthMode: json['defaultAuthMode'] as String? ?? 'password',
      installRoot:
          json['installRoot'] as String? ?? '/opt/neurochip-akida-host',
      serviceUser: json['serviceUser'] as String? ?? 'neurochip',
      venvDirName: json['venvDirName'] as String? ?? 'venv',
      runtimeServiceName: json['runtimeServiceName'] as String? ?? 'neurochip',
      controlServiceName:
          json['controlServiceName'] as String? ?? 'neurochip-akida-control',
      tokenRelativePath:
          json['tokenRelativePath'] as String? ?? 'credentials/api-token',
      installStatusRelativePath:
          json['installStatusRelativePath'] as String? ?? 'install-status.json',
    );
  }

  Map<String, dynamic> toJson() => {
        'runtimePort': runtimePort,
        'controlPort': controlPort,
        'sshPort': sshPort,
        'defaultState': defaultState,
        'defaultAuthMode': defaultAuthMode,
        'installRoot': installRoot,
        'serviceUser': serviceUser,
        'venvDirName': venvDirName,
        'runtimeServiceName': runtimeServiceName,
        'controlServiceName': controlServiceName,
        'tokenRelativePath': tokenRelativePath,
        'installStatusRelativePath': installStatusRelativePath,
      };
}

class LauncherRuntimeConfig {
  const LauncherRuntimeConfig({
    this.pynq,
    this.akida,
  });

  final PynqLauncherRuntimeConfig? pynq;
  final AkidaLauncherRuntimeConfig? akida;

  factory LauncherRuntimeConfig.fromJson(Map<String, dynamic> json) {
    return LauncherRuntimeConfig(
      pynq: json['pynq'] is Map<String, dynamic>
          ? PynqLauncherRuntimeConfig.fromJson(
              json['pynq'] as Map<String, dynamic>,
            )
          : null,
      akida: json['akida'] is Map<String, dynamic>
          ? AkidaLauncherRuntimeConfig.fromJson(
              json['akida'] as Map<String, dynamic>,
            )
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'pynq': pynq?.toJson(),
        'akida': akida?.toJson(),
      };
}

class JupyterKernelConfig {
  const JupyterKernelConfig({required this.displayName});

  final String displayName;

  factory JupyterKernelConfig.fromJson(Map<String, dynamic> json) {
    return JupyterKernelConfig(
      displayName: json['displayName'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {'displayName': displayName};
}

class DeploymentCapability {
  const DeploymentCapability({
    this.supportedModes = const <String>[
      'standalone',
      'docker',
      'kubernetes',
    ],
    this.healthPath = '/health',
    this.requiredPorts = const <int>[],
    this.requiredEnvironment = const <String>[],
    this.secretFields = const <String>[],
    this.defaultContainerImage = '',
    this.composeProfile = '',
    this.chartTemplateId = '',
    this.startupTimeoutSeconds = 120,
    this.readinessTimeoutSeconds = 120,
    this.internalProbeHost = '',
  });

  final List<String> supportedModes;
  final String healthPath;
  final List<int> requiredPorts;
  final List<String> requiredEnvironment;
  final List<String> secretFields;
  final String defaultContainerImage;
  final String composeProfile;
  final String chartTemplateId;
  final double startupTimeoutSeconds;
  final double readinessTimeoutSeconds;
  final String internalProbeHost;

  factory DeploymentCapability.fromJson(Map<String, dynamic> json) {
    return DeploymentCapability(
      supportedModes:
          (json['supportedModes'] as List<dynamic>? ?? const <dynamic>[])
              .map((dynamic value) => value.toString())
              .where((String value) => value.isNotEmpty)
              .toList(growable: false),
      healthPath: json['healthPath'] as String? ?? '/health',
      requiredPorts:
          (json['requiredPorts'] as List<dynamic>? ?? const <dynamic>[])
              .whereType<num>()
              .map((num value) => value.toInt())
              .toList(growable: false),
      requiredEnvironment:
          (json['requiredEnvironment'] as List<dynamic>? ?? const <dynamic>[])
              .map((dynamic value) => value.toString())
              .where((String value) => value.isNotEmpty)
              .toList(growable: false),
      secretFields:
          (json['secretFields'] as List<dynamic>? ?? const <dynamic>[])
              .map((dynamic value) => value.toString())
              .where((String value) => value.isNotEmpty)
              .toList(growable: false),
      defaultContainerImage: json['defaultContainerImage'] as String? ?? '',
      composeProfile: json['composeProfile'] as String? ?? '',
      chartTemplateId: json['chartTemplateId'] as String? ?? '',
      startupTimeoutSeconds:
          (json['startupTimeoutSeconds'] as num?)?.toDouble() ?? 120,
      readinessTimeoutSeconds:
          (json['readinessTimeoutSeconds'] as num?)?.toDouble() ?? 120,
      internalProbeHost: json['internalProbeHost'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'supportedModes': supportedModes,
        'healthPath': healthPath,
        'requiredPorts': requiredPorts,
        'requiredEnvironment': requiredEnvironment,
        'secretFields': secretFields,
        'defaultContainerImage': defaultContainerImage,
        'composeProfile': composeProfile,
        'chartTemplateId': chartTemplateId,
        'startupTimeoutSeconds': startupTimeoutSeconds,
        'readinessTimeoutSeconds': readinessTimeoutSeconds,
        'internalProbeHost': internalProbeHost,
      };
}

class Module {
  final String id;
  final String name;
  final String description;
  final String icon;
  final String directory;
  final int? port;
  final bool required;
  final bool hasFrontend;
  final bool showInLauncherNav;
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
  final List<String> installExtras;
  final String installStrategy;
  final String startStrategy;
  final AkidaRuntimeConfig? akidaRuntime;
  final LauncherRuntimeConfig? launcherRuntime;
  final DeploymentCapability? deployment;
  final AkidaRuntimeState? akidaRuntimeState;
  final JupyterKernelConfig? jupyterKernel;
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
    this.required = false,
    this.hasFrontend = false,
    this.showInLauncherNav = true,
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
    this.installExtras = const [],
    this.installStrategy = 'pip',
    this.startStrategy = 'none',
    this.akidaRuntime,
    this.launcherRuntime,
    this.deployment,
    this.akidaRuntimeState,
    this.jupyterKernel,
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
      required: json['required'] as bool? ?? false,
      hasFrontend: json['hasFrontend'] as bool? ?? false,
      showInLauncherNav: json['showInLauncherNav'] as bool? ?? true,
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
      installExtras:
          (json['installExtras'] as List<dynamic>?)?.cast<String>() ?? const [],
      installStrategy: json['installStrategy'] as String? ?? 'pip',
      startStrategy: json['startStrategy'] as String? ?? 'none',
      akidaRuntime: json['akidaRuntime'] is Map<String, dynamic>
          ? AkidaRuntimeConfig.fromJson(
              json['akidaRuntime'] as Map<String, dynamic>,
            )
          : null,
      launcherRuntime: json['launcherRuntime'] is Map<String, dynamic>
          ? LauncherRuntimeConfig.fromJson(
              json['launcherRuntime'] as Map<String, dynamic>,
            )
          : null,
      deployment: json['deployment'] is Map<String, dynamic>
          ? DeploymentCapability.fromJson(
              json['deployment'] as Map<String, dynamic>,
            )
          : null,
      akidaRuntimeState: json['akidaRuntimeState'] is Map<String, dynamic>
          ? AkidaRuntimeState.fromJson(
              json['akidaRuntimeState'] as Map<String, dynamic>,
            )
          : null,
      jupyterKernel: json['jupyterKernel'] is Map<String, dynamic>
          ? JupyterKernelConfig.fromJson(
              json['jupyterKernel'] as Map<String, dynamic>,
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
    bool? required,
    bool? hasFrontend,
    bool? showInLauncherNav,
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
    List<String>? installExtras,
    String? installStrategy,
    String? startStrategy,
    Object? akidaRuntime = const Object(),
    Object? launcherRuntime = const Object(),
    Object? deployment = const Object(),
    Object? akidaRuntimeState = const Object(),
    Object? jupyterKernel = const Object(),
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
      required: required ?? this.required,
      hasFrontend: hasFrontend ?? this.hasFrontend,
      showInLauncherNav: showInLauncherNav ?? this.showInLauncherNav,
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
      installExtras: installExtras ?? this.installExtras,
      installStrategy: installStrategy ?? this.installStrategy,
      startStrategy: startStrategy ?? this.startStrategy,
      akidaRuntime: akidaRuntime is AkidaRuntimeConfig?
          ? akidaRuntime
          : this.akidaRuntime,
      launcherRuntime: launcherRuntime is LauncherRuntimeConfig?
          ? launcherRuntime
          : this.launcherRuntime,
      deployment:
          deployment is DeploymentCapability? ? deployment : this.deployment,
      akidaRuntimeState: akidaRuntimeState is AkidaRuntimeState?
          ? akidaRuntimeState
          : this.akidaRuntimeState,
      jupyterKernel: jupyterKernel is JupyterKernelConfig?
          ? jupyterKernel
          : this.jupyterKernel,
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

  /// Mirrors the launcher control service's notion of an externally managed
  /// service (`_is_externally_managed_service` in server.py): a `none`-strategy
  /// module on its own, non-monolith port (the monolith/suite-API port is
  /// 9000). These are started outside the launcher — e.g. Jupyter or
  /// lava_backend running via Docker Compose — so the launcher only
  /// health-probes them; it never installs or starts them, and their first
  /// bring-up can include a multi-minute environment build done at deploy time.
  bool get isExternallyManaged =>
      startStrategy == 'none' && effectivePort != null && effectivePort != 9000;

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
        'required': required,
        'hasFrontend': hasFrontend,
        'showInLauncherNav': showInLauncherNav,
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
        'installExtras': installExtras,
        'installStrategy': installStrategy,
        'startStrategy': startStrategy,
        'akidaRuntime': akidaRuntime?.toJson(),
        'launcherRuntime': launcherRuntime?.toJson(),
        'deployment': deployment?.toJson(),
        'akidaRuntimeState': akidaRuntimeState?.toJson(),
        'jupyterKernel': jupyterKernel?.toJson(),
        'preflightStatus': preflightStatus,
        'preflightMessage': preflightMessage,
        'capabilityWarnings': capabilityWarnings,
        'environmentFingerprint': environmentFingerprint,
        'status': status.index,
        'installProgress': installProgress,
        'healthStatus': healthStatus,
      };

  /// Equality based on the fields that change during the 3-second polling
  /// cycle. Two [Module] instances are considered equal when no UI-visible
  /// state has changed, allowing [ModuleProvider] to skip [notifyListeners].
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! Module) return false;
    return id == other.id &&
        status == other.status &&
        healthStatus == other.healthStatus &&
        installProgress == other.installProgress &&
        version == other.version &&
        remoteVersion == other.remoteVersion &&
        isEnabled == other.isEnabled &&
        customPort == other.customPort &&
        preflightStatus == other.preflightStatus &&
        preflightMessage == other.preflightMessage;
  }

  @override
  int get hashCode => Object.hash(
        id,
        status,
        healthStatus,
        installProgress,
        version,
        remoteVersion,
        isEnabled,
        customPort,
        preflightStatus,
        preflightMessage,
      );
}
