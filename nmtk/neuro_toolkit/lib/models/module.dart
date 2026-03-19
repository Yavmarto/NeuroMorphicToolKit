enum ModuleStatus {
  notInstalled,
  installing,
  installed,
  updateAvailable,
}

class Module {
  final String id;
  final String name;
  final String description;
  final int port;
  final bool hasFrontend;
  ModuleStatus status;
  double installProgress;
  bool isLaunched;

  Module({
    required this.id,
    required this.name,
    required this.description,
    required this.port,
    this.hasFrontend = false,
    this.status = ModuleStatus.notInstalled,
    this.installProgress = 0.0,
    this.isLaunched = false,
  });

  // Create a copy of the module with potentially updated fields
  Module copyWith({
    String? id,
    String? name,
    String? description,
    int? port,
    bool? hasFrontend,
    ModuleStatus? status,
    double? installProgress,
    bool? isLaunched,
  }) {
    return Module(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      port: port ?? this.port,
      hasFrontend: hasFrontend ?? this.hasFrontend,
      status: status ?? this.status,
      installProgress: installProgress ?? this.installProgress,
      isLaunched: isLaunched ?? this.isLaunched,
    );
  }
}
