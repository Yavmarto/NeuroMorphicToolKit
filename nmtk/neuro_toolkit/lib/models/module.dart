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
    this.uvicornTarget = 'app.main:app',
    this.localDeps = const [],
    this.version = '0.0.0',
    this.remoteVersion = '0.0.0',
    this.versionPinned = false,
    this.remoteUrl,
    this.isEnabled = true,
    this.customPort,
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
      uvicornTarget: json['uvicornTarget'] as String? ?? 'app.main:app',
      localDeps:
          (json['localDeps'] as List<dynamic>?)?.cast<String>() ?? const [],
      version: json['version'] as String? ?? '0.0.0',
      remoteVersion: json['remoteVersion'] as String? ?? '0.0.0',
      versionPinned: json['versionPinned'] as bool? ?? false,
      remoteUrl: json['remoteUrl'] as String?,
      isEnabled: json['isEnabled'] as bool? ?? true,
      customPort: json['customPort'] as int?,
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
      status: status ?? this.status,
      installProgress: installProgress ?? this.installProgress,
      healthStatus: healthStatus is String? ? healthStatus : this.healthStatus,
    );
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
        'status': status.index,
        'installProgress': installProgress,
        'healthStatus': healthStatus,
      };
}
