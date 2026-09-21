/// Locally saved NeuroSense sensor source for Studio setup/deploy.
class NeurosenseSensorTarget {
  const NeurosenseSensorTarget({
    required this.id,
    required this.displayName,
    required this.deviceId,
    this.deviceType = 'synthetic',
    this.serialPort = '',
    this.presetId = '',
    this.isDefault = false,
  });

  final String id;
  final String displayName;
  final String deviceId;
  final String deviceType;
  final String serialPort;
  final String presetId;
  final bool isDefault;

  String get subtitle {
    final parts = <String>[
      if (deviceType.isNotEmpty) deviceType,
      if (deviceId.isNotEmpty) deviceId,
    ];
    return parts.join(' • ');
  }

  factory NeurosenseSensorTarget.fromJson(Map<String, dynamic> json) {
    return NeurosenseSensorTarget(
      id: json['id'] as String? ?? '',
      displayName: json['display_name'] as String? ?? '',
      deviceId: json['device_id'] as String? ?? '',
      deviceType: json['device_type'] as String? ?? 'synthetic',
      serialPort: json['serial_port'] as String? ?? '',
      presetId: json['preset_id'] as String? ?? '',
      isDefault: json['is_default'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'display_name': displayName,
    'device_id': deviceId,
    'device_type': deviceType,
    'serial_port': serialPort,
    'preset_id': presetId,
    'is_default': isDefault,
  };

  NeurosenseSensorTarget copyWith({
    String? id,
    String? displayName,
    String? deviceId,
    String? deviceType,
    String? serialPort,
    String? presetId,
    bool? isDefault,
  }) {
    return NeurosenseSensorTarget(
      id: id ?? this.id,
      displayName: displayName ?? this.displayName,
      deviceId: deviceId ?? this.deviceId,
      deviceType: deviceType ?? this.deviceType,
      serialPort: serialPort ?? this.serialPort,
      presetId: presetId ?? this.presetId,
      isDefault: isDefault ?? this.isDefault,
    );
  }
}

/// Device row from GET /api/neurosense/devices.
class NeurosenseDeviceInfo {
  const NeurosenseDeviceInfo({
    required this.id,
    required this.name,
    required this.type,
    required this.channels,
    required this.samplingRateHz,
    required this.connected,
    this.serialPort,
    this.supportLevel = 'experimental',
  });

  final String id;
  final String name;
  final String type;
  final int channels;
  final int samplingRateHz;
  final bool connected;
  final String? serialPort;
  final String supportLevel;

  factory NeurosenseDeviceInfo.fromJson(Map<String, dynamic> json) {
    return NeurosenseDeviceInfo(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      type: json['type'] as String? ?? '',
      channels: json['channels'] as int? ?? 0,
      samplingRateHz: json['sampling_rate_hz'] as int? ?? 0,
      connected: json['connected'] as bool? ?? false,
      serialPort: json['serial_port'] as String?,
      supportLevel: json['support_level'] as String? ?? 'experimental',
    );
  }
}

/// Preset row from GET /api/neurosense/presets.
class NeurosenseAcquisitionPreset {
  const NeurosenseAcquisitionPreset({
    required this.id,
    required this.name,
    required this.signalType,
    required this.description,
  });

  final String id;
  final String name;
  final String signalType;
  final String description;

  factory NeurosenseAcquisitionPreset.fromJson(Map<String, dynamic> json) {
    return NeurosenseAcquisitionPreset(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      signalType: json['signal_type'] as String? ?? '',
      description: json['description'] as String? ?? '',
    );
  }
}

/// Per-channel quality row from GET /api/neurosense/quality.
class NeurosenseChannelQuality {
  const NeurosenseChannelQuality({
    required this.channel,
    required this.label,
    required this.snrDb,
    required this.status,
    this.suggestion,
  });

  final int channel;
  final String label;
  final double snrDb;
  final String status;
  final String? suggestion;

  factory NeurosenseChannelQuality.fromJson(Map<String, dynamic> json) {
    return NeurosenseChannelQuality(
      channel: json['channel'] as int? ?? 0,
      label: json['label'] as String? ?? '',
      snrDb: (json['snr_db'] as num?)?.toDouble() ?? 0,
      status: json['status'] as String? ?? 'marginal',
      suggestion: json['suggestion'] as String?,
    );
  }
}

/// Signal quality summary from GET /api/neurosense/quality.
class NeurosenseSignalQuality {
  const NeurosenseSignalQuality({required this.channels});

  final List<NeurosenseChannelQuality> channels;

  factory NeurosenseSignalQuality.fromJson(Map<String, dynamic> json) {
    final raw = json['channels'];
    if (raw is! List) {
      return const NeurosenseSignalQuality(channels: []);
    }
    return NeurosenseSignalQuality(
      channels: raw
          .whereType<Map<String, dynamic>>()
          .map(NeurosenseChannelQuality.fromJson)
          .toList(growable: false),
    );
  }
}

/// Spike encoding config from POST /api/neurosense/nir/import.
class NeurosenseEncodingConfig {
  const NeurosenseEncodingConfig({
    required this.method,
    this.refractoryPeriod,
    this.temporalResolution,
    this.rateMaxHz,
    this.temporalPhaseBins,
    this.deltaThreshold,
  });

  final String method;
  final double? refractoryPeriod;
  final double? temporalResolution;
  final double? rateMaxHz;
  final int? temporalPhaseBins;
  final double? deltaThreshold;

  factory NeurosenseEncodingConfig.fromJson(Map<String, dynamic> json) {
    return NeurosenseEncodingConfig(
      method: json['method'] as String? ?? 'rate',
      refractoryPeriod: (json['refractory_period'] as num?)?.toDouble(),
      temporalResolution: (json['temporal_resolution'] as num?)?.toDouble(),
      rateMaxHz: (json['rate_max_hz'] as num?)?.toDouble(),
      temporalPhaseBins: json['temporal_phase_bins'] as int?,
      deltaThreshold: (json['delta_threshold'] as num?)?.toDouble(),
    );
  }

  String get summary {
    final parts = <String>['method: $method'];
    if (rateMaxHz != null)
      parts.add('rate max ${rateMaxHz!.toStringAsFixed(0)} Hz');
    if (temporalPhaseBins != null) {
      parts.add('phase bins $temporalPhaseBins');
    }
    if (deltaThreshold != null) {
      parts.add('delta ${deltaThreshold!.toStringAsFixed(1)} µV');
    }
    return parts.join(' • ');
  }
}
