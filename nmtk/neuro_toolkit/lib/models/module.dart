enum ModuleStatus {
  notInstalled,
  installing,
  installed,
  updateAvailable,
  running,
}

class Module {
  final String id;
  final String name;
  final String description;
  final String icon;
  final int? backendPort;
  final String installPath;
  final bool hasFrontend;
  final String frontendStatus;
  final bool requiresMuJoCo;
  ModuleStatus status;
  double installProgress;

  Module({
    required this.id,
    required this.name,
    required this.description,
    required this.icon,
    this.backendPort,
    required this.installPath,
    required this.hasFrontend,
    required this.frontendStatus,
    required this.requiresMuJoCo,
    this.status = ModuleStatus.notInstalled,
    this.installProgress = 0.0,
  });

  factory Module.fromJson(Map<String, dynamic> json) {
    return Module(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String,
      icon: json['icon'] as String,
      backendPort: json['port'] as int?,
      installPath: json['installPath'] as String,
      hasFrontend: json['hasFrontend'] as bool,
      frontendStatus: json['frontendStatus'] as String,
      requiresMuJoCo: json['requiresMuJoCo'] as bool,
    );
  }

  // Create a copy of the module with potentially updated fields
  Module copyWith({
    String? id,
    String? name,
    String? description,
    String? icon,
    int? backendPort,
    String? installPath,
    bool? hasFrontend,
    String? frontendStatus,
    bool? requiresMuJoCo,
    ModuleStatus? status,
    double? installProgress,
  }) {
    return Module(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      icon: icon ?? this.icon,
      backendPort: backendPort ?? this.backendPort,
      installPath: installPath ?? this.installPath,
      hasFrontend: hasFrontend ?? this.hasFrontend,
      frontendStatus: frontendStatus ?? this.frontendStatus,
      requiresMuJoCo: requiresMuJoCo ?? this.requiresMuJoCo,
      status: status ?? this.status,
      installProgress: installProgress ?? this.installProgress,
    );
  }
}
