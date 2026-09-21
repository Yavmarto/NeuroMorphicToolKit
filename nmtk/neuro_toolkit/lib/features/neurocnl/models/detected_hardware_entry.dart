/// One piece of hardware discovered by a backend local scan.
///
/// Mirrors the Neurochip backend's `DetectedHardwareEntry`
/// (`neurochip/contracts/hardware_contracts.py`), returned by
/// `GET /api/neurochip/hardware/detected`. `alreadyRegistered` reports
/// whether the same physical device is already known to the launcher's
/// saved-target store (the launcher passes its saved device identifiers as
/// `registered_identifier` query params), so auto-add can create a target for
/// only the unregistered hits.
///
/// Only chip types with a local scan surface appear here: Akida, Speck, and
/// serial/Teensy. PYNQ and SpiNNaker2 are network-attached and are never
/// returned (see CEL-120).
class DetectedHardwareEntry {
  const DetectedHardwareEntry({
    required this.chipType,
    required this.displayName,
    required this.identifier,
    this.alreadyRegistered = false,
  });

  /// One of `akida`, `speck`, `teensy`.
  final String chipType;
  final String displayName;

  /// Stable device identifier (serial / USB address / serial port).
  final String identifier;
  final bool alreadyRegistered;

  /// Whether [chipType] has a paired-host model the launcher can auto-create.
  ///
  /// Akida and Speck same-host USB devices auto-add today; serial/Teensy hits
  /// are reported but not auto-added until those paired-host models exist.
  bool get isAutoAddable => chipType == 'akida' || chipType == 'speck';

  factory DetectedHardwareEntry.fromJson(Map<String, dynamic> json) {
    return DetectedHardwareEntry(
      chipType: json['chip_type'] as String? ?? '',
      displayName: json['display_name'] as String? ?? '',
      identifier: json['identifier'] as String? ?? '',
      alreadyRegistered: json['already_registered'] as bool? ?? false,
    );
  }
}
