int _readResourceInt(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is double) {
    return value.round();
  }
  return 0;
}

double _readResourceDouble(Object? value) {
  if (value is double) {
    return value;
  }
  if (value is int) {
    return value.toDouble();
  }
  return 0;
}

/// Live host stats from `GET /api/suite/system/resources`.
class SystemGpuStats {
  const SystemGpuStats({
    required this.name,
    required this.memoryTotal,
    required this.memoryUsed,
    required this.utilization,
  });

  final String name;
  final int memoryTotal;
  final int memoryUsed;
  final int utilization;

  factory SystemGpuStats.fromJson(Map<String, dynamic> json) {
    return SystemGpuStats(
      name: json['name'] is String ? json['name'] as String : 'GPU',
      memoryTotal: _readResourceInt(json['memory_total']),
      memoryUsed: _readResourceInt(json['memory_used']),
      utilization: _readResourceInt(json['utilization']),
    );
  }
}

class SystemResourcesSnapshot {
  const SystemResourcesSnapshot({
    required this.cpuPercent,
    required this.cpuCores,
    required this.memoryTotal,
    required this.memoryUsed,
    required this.memoryPercent,
    required this.gpus,
    required this.hostname,
    required this.platform,
    required this.uptimeSeconds,
  });

  final double cpuPercent;
  final int cpuCores;
  final int memoryTotal;
  final int memoryUsed;
  final double memoryPercent;

  /// Null when the backend reports no GPU hardware; an empty list is treated
  /// the same as absent for display purposes.
  final List<SystemGpuStats>? gpus;
  final String hostname;
  final String platform;
  final double uptimeSeconds;

  bool get hasGpu => gpus != null && gpus!.isNotEmpty;

  factory SystemResourcesSnapshot.fromJson(Map<String, dynamic> json) {
    final cpu = json['cpu'];
    final memory = json['memory'];
    final host = json['host'];
    return SystemResourcesSnapshot(
      cpuPercent: cpu is Map<String, dynamic>
          ? _readResourceDouble(cpu['percent'])
          : 0,
      cpuCores: cpu is Map<String, dynamic>
          ? _readResourceInt(cpu['cores'])
          : 0,
      memoryTotal: memory is Map<String, dynamic>
          ? _readResourceInt(memory['total'])
          : 0,
      memoryUsed: memory is Map<String, dynamic>
          ? _readResourceInt(memory['used'])
          : 0,
      memoryPercent: memory is Map<String, dynamic>
          ? _readResourceDouble(memory['percent'])
          : 0,
      gpus: _parseGpus(json['gpu']),
      hostname: host is Map<String, dynamic> && host['hostname'] is String
          ? host['hostname'] as String
          : '',
      platform: host is Map<String, dynamic> && host['platform'] is String
          ? host['platform'] as String
          : '',
      uptimeSeconds: host is Map<String, dynamic>
          ? _readResourceDouble(host['uptime'])
          : 0,
    );
  }

  static List<SystemGpuStats>? _parseGpus(Object? value) {
    if (value == null) {
      return null;
    }
    if (value is! List<dynamic>) {
      return null;
    }
    final parsed = value
        .whereType<Map<String, dynamic>>()
        .map(SystemGpuStats.fromJson)
        .toList(growable: false);
    return parsed.isEmpty ? null : parsed;
  }
}

String formatResourceBytes(int bytes) {
  if (bytes < 1024) {
    return '$bytes B';
  }
  final kilobytes = bytes / 1024;
  if (kilobytes < 1024) {
    return '${kilobytes.toStringAsFixed(1)} KB';
  }
  final megabytes = kilobytes / 1024;
  if (megabytes < 1024) {
    return '${megabytes.toStringAsFixed(1)} MB';
  }
  return '${(megabytes / 1024).toStringAsFixed(1)} GB';
}

String formatResourceUptime(double seconds) {
  final totalSeconds = seconds.round();
  final days = totalSeconds ~/ 86400;
  final hours = (totalSeconds % 86400) ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;
  if (days > 0) {
    return '${days}d ${hours}h';
  }
  if (hours > 0) {
    return '${hours}h ${minutes}m';
  }
  return '${minutes}m';
}
