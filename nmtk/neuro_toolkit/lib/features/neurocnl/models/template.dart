/// Hardware configuration preset for a template.
class HardwareConfig {
  final int baudRate;
  final int emgChannels;
  final String learningMode; // 'stdp', 'pes', 'ocl'
  final double simDuration;

  const HardwareConfig({
    required this.baudRate,
    required this.emgChannels,
    required this.learningMode,
    required this.simDuration,
  });

  /// Preset hardware configs keyed by template ID.
  static const Map<String, HardwareConfig> hardwareConfigs = {
    'emg_gripper': HardwareConfig(
      baudRate: 115200,
      emgChannels: 4,
      learningMode: 'pes',
      simDuration: 5.0,
    ),
    'prosthetic_reflex': HardwareConfig(
      baudRate: 115200,
      emgChannels: 2,
      learningMode: 'stdp',
      simDuration: 2.0,
    ),
    'prosthetic_sleep': HardwareConfig(
      baudRate: 115200,
      emgChannels: 2,
      learningMode: 'pes',
      simDuration: 10.0,
    ),
    'slip_reflex': HardwareConfig(
      baudRate: 115200,
      emgChannels: 1,
      learningMode: 'stdp',
      simDuration: 3.0,
    ),
  };
}

/// A CNL template from the template gallery.
class CnlTemplate {
  final String id;
  final String name;
  final String description;
  final String category;
  final List<String> tags;
  final String difficulty;
  final String validationBackend;
  final List<String> supportedTargets;
  final String spec;

  const CnlTemplate({
    required this.id,
    required this.name,
    required this.description,
    required this.category,
    required this.tags,
    required this.difficulty,
    this.validationBackend = 'nir',
    this.supportedTargets = const ['snntorch_sim', 'lava_sim'],
    required this.spec,
  });

  factory CnlTemplate.fromJson(Map<String, dynamic> json) {
    return CnlTemplate(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String,
      category: json['category'] as String? ?? 'Basics',
      tags: (json['tags'] as List).cast<String>(),
      difficulty: json['difficulty'] as String,
      validationBackend: json['validation_backend'] as String? ?? 'nir',
      supportedTargets:
          (json['supported_targets'] as List<dynamic>?)?.cast<String>() ??
          const ['snntorch_sim', 'lava_sim'],
      spec: json['spec'] as String,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'category': category,
    'tags': tags,
    'difficulty': difficulty,
    'validation_backend': validationBackend,
    'supported_targets': supportedTargets,
    'spec': spec,
  };

  /// Whether this template can be run on [backendName] (e.g. 'lava_sim').
  bool supportsTarget(String backendName) =>
      supportedTargets.contains(backendName);

  /// Returns the hardware config preset for this template, if one exists.
  HardwareConfig? get hardwareConfig => HardwareConfig.hardwareConfigs[id];
}
