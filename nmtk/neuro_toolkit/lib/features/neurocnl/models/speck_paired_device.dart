// Local model for a Speck device paired to the connected backend host.
//
// Speck boards are USB-attached to the machine that runs the Neurochip
// hardware worker. No SSH provisioning is required — auto-add only stores the
// display name and stable device identifier.

class SpeckPairedDevice {
  const SpeckPairedDevice({
    required this.id,
    required this.displayName,
    required this.deviceIdentifier,
    this.isDefault = false,
    this.sameHostAsBackend = true,
  });

  final String id;
  final String displayName;
  final String deviceIdentifier;
  final bool isDefault;
  final bool sameHostAsBackend;

  SpeckPairedDevice copyWith({
    String? id,
    String? displayName,
    String? deviceIdentifier,
    bool? isDefault,
    bool? sameHostAsBackend,
  }) {
    return SpeckPairedDevice(
      id: id ?? this.id,
      displayName: displayName ?? this.displayName,
      deviceIdentifier: deviceIdentifier ?? this.deviceIdentifier,
      isDefault: isDefault ?? this.isDefault,
      sameHostAsBackend: sameHostAsBackend ?? this.sameHostAsBackend,
    );
  }

  factory SpeckPairedDevice.fromJson(Map<String, dynamic> json) {
    return SpeckPairedDevice(
      id: json['id'] as String? ?? '',
      displayName: json['displayName'] as String? ?? '',
      deviceIdentifier: json['deviceIdentifier'] as String? ?? '',
      isDefault: json['isDefault'] as bool? ?? false,
      sameHostAsBackend: json['sameHostAsBackend'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'displayName': displayName,
    'deviceIdentifier': deviceIdentifier,
    'isDefault': isDefault,
    'sameHostAsBackend': sameHostAsBackend,
  };
}
