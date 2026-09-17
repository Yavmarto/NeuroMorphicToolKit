/// Health status returned by the /health endpoint.
class HealthStatus {
  final String status;
  final String neurocnlVersion;
  final DateTime timestamp;
  final Map<String, ModuleInfo> modules;
  final DiskInfo disk;
  final String? nengoVersion;
  final bool nengoAvailable;
  final bool mujocoAvailable;
  final String? mujocoVersion;

  const HealthStatus({
    required this.status,
    required this.neurocnlVersion,
    required this.timestamp,
    required this.modules,
    required this.disk,
    this.nengoVersion,
    required this.nengoAvailable,
    required this.mujocoAvailable,
    this.mujocoVersion,
  });

  factory HealthStatus.fromJson(Map<String, dynamic> json) {
    final modulesMap = <String, ModuleInfo>{};
    final rawModules = json['modules'];
    if (rawModules is Map<String, dynamic>) {
      for (final entry in rawModules.entries) {
        final moduleJson = entry.value;
        if (moduleJson is Map<String, dynamic>) {
          modulesMap[entry.key] = ModuleInfo.fromJson(moduleJson);
        }
      }
    }

    return HealthStatus(
      status: json['status'] as String? ?? 'unknown',
      neurocnlVersion: json['neurocnl_version'] as String? ?? 'unknown',
      timestamp: _parseTimestamp(json['timestamp']),
      modules: modulesMap,
      disk: DiskInfo.fromJson(json['disk'] as Map<String, dynamic>?),
      nengoVersion: json['nengo_version'] as String?,
      nengoAvailable: json['nengo_available'] as bool? ?? false,
      mujocoAvailable: json['mujoco_available'] as bool? ?? false,
      mujocoVersion: json['mujoco_version'] as String?,
    );
  }

  static DateTime _parseTimestamp(Object? raw) {
    if (raw is String) {
      return DateTime.tryParse(raw) ?? DateTime.fromMillisecondsSinceEpoch(0);
    }
    return DateTime.fromMillisecondsSinceEpoch(0);
  }
}

/// Information about an optional backend module.
class ModuleInfo {
  final bool available;
  final String? version;

  const ModuleInfo({required this.available, this.version});

  factory ModuleInfo.fromJson(Map<String, dynamic> json) {
    return ModuleInfo(
      available: json['available'] as bool,
      version: json['version'] as String?,
    );
  }
}

/// Backend disk space information.
class DiskInfo {
  final double totalGb;
  final double usedGb;
  final double freeGb;
  final bool? lowSpace;

  const DiskInfo({
    required this.totalGb,
    required this.usedGb,
    required this.freeGb,
    this.lowSpace,
  });

  factory DiskInfo.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return const DiskInfo(totalGb: 0, usedGb: 0, freeGb: 0);
    }
    return DiskInfo(
      totalGb: (json['total_gb'] as num? ?? 0).toDouble(),
      usedGb: (json['used_gb'] as num? ?? 0).toDouble(),
      freeGb: (json['free_gb'] as num? ?? 0).toDouble(),
      lowSpace: json['low_space'] as bool?,
    );
  }
}
