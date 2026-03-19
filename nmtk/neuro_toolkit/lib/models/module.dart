enum ModuleStatus {
  notInstalled,
  installing,
  installed,
  starting,
  running,
  stopping,
  error,
  degraded,
}

class Module {
  final String id;
  final String name;
  final String description;
  final String directory;
  final int port;
  ModuleStatus status;
  double installProgress;
  String? healthStatus;

  Module({
    required this.id,
    required this.name,
    required this.description,
    required this.directory,
    required this.port,
    this.status = ModuleStatus.notInstalled,
    this.installProgress = 0.0,
    this.healthStatus,
  });

  // Create a copy of the module with potentially updated fields
  Module copyWith({
    String? id,
    String? name,
    String? description,
    String? directory,
    int? port,
    ModuleStatus? status,
    double? installProgress,
    String? healthStatus,
  }) {
    return Module(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      directory: directory ?? this.directory,
      port: port ?? this.port,
      status: status ?? this.status,
      installProgress: installProgress ?? this.installProgress,
      healthStatus: healthStatus ?? this.healthStatus,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'directory': directory,
        'port': port,
        'status': status.index,
        'installProgress': installProgress,
        'healthStatus': healthStatus,
      };

  factory Module.fromJson(Map<String, dynamic> json) => Module(
        id: json['id'],
        name: json['name'],
        description: json['description'],
        directory: json['directory'],
        port: json['port'],
        status: ModuleStatus.values[json['status']],
        installProgress: json['installProgress']?.toDouble() ?? 0.0,
        healthStatus: json['healthStatus'],
      );
}
