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
  ModuleStatus status;
  double installProgress;

  Module({
    required this.id,
    required this.name,
    required this.description,
    this.status = ModuleStatus.notInstalled,
    this.installProgress = 0.0,
  });

  // Create a copy of the module with potentially updated fields
  Module copyWith({
    String? id,
    String? name,
    String? description,
    ModuleStatus? status,
    double? installProgress,
  }) {
    return Module(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      status: status ?? this.status,
      installProgress: installProgress ?? this.installProgress,
    );
  }
}
