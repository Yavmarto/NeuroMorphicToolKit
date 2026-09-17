import 'package:neuro_toolkit/features/neurocnl/models/detected_hardware_entry.dart';
import 'package:neuro_toolkit/ui_core/models/akida_deployment_model.dart';

/// What one hardware scan did, for the caller to report.
class HardwareAutoAddResult {
  const HardwareAutoAddResult({
    this.addedNames = const <String>[],
    this.alreadyRegisteredCount = 0,
    this.unsupportedByChipType = const <String, int>{},
  });

  /// Display names of targets auto-created by the scan.
  final List<String> addedNames;

  /// Detected devices already registered (skipped, no duplicate created).
  final int alreadyRegisteredCount;

  /// Detected-but-unregistered devices per chip type that have no paired-host
  /// model yet (`speck` / `teensy`), keyed by chip type.
  final Map<String, int> unsupportedByChipType;

  bool get addedAny => addedNames.isNotEmpty;

  String describe() {
    final parts = <String>[];
    if (addedNames.isNotEmpty) {
      final quoted = addedNames.map((name) => '"$name"').join(', ');
      parts.add(
        'Added ${addedNames.length} detected ${addedNames.length == 1 ? 'device' : 'devices'} '
        'as same-host target${addedNames.length == 1 ? '' : 's'} ($quoted) — '
        'name only, no SSH credentials needed.',
      );
    }
    if (alreadyRegisteredCount > 0) {
      parts.add(
        '$alreadyRegisteredCount already-registered '
        '${alreadyRegisteredCount == 1 ? 'device' : 'devices'} skipped.',
      );
    }
    final unsupported = unsupportedByChipType.entries.toList(growable: false);
    if (unsupported.isNotEmpty) {
      final labels = unsupported
          .map(
            (e) =>
                '${e.value} ${chipTypeLabel(e.key)}'
                '${e.value == 1 ? '' : 's'}',
          )
          .join(', ');
      parts.add('$labels detected but not auto-added (no target model yet).');
    }
    if (parts.isEmpty) {
      return 'No new hardware detected on the backend host.';
    }
    return 'Hardware scan complete: ${parts.join(' ')}';
  }
}

String chipTypeLabel(String chipType) => switch (chipType) {
  'akida' => 'Akida',
  'speck' => 'Speck',
  'teensy' => 'Teensy',
  _ => chipType,
};

/// Auto-creates same-host hardware targets from the backend's local scan.
///
/// Wires CEL-121's `GET /hardware/detected` to CEL-122's launcher behaviour:
/// on backend connect (and on demand from the manage-targets dialog) the
/// launcher asks the connected backend which physical hardware it can see, and
/// for every device that is not already a saved target it creates the matching
/// entry using the same-host no-credentials path — `AkidaHostAuthMode.none` +
/// `sameHostAsBackend: true` — name only, no SSH credentials, because the
/// device lives on the machine that already runs the backend.
///
/// Only `akida` has a paired-host model today; Speck and serial/Teensy hits are
/// reported as detected-but-not-auto-addable (see CEL-120).
class HardwareTargetAutoScanner {
  HardwareTargetAutoScanner({
    required this.detectDevices,
    required this.fetchAkidaHosts,
    required this.createSameHostAkidaHost,
  });

  /// Runs the backend scan; already-saved identifiers are passed through so
  /// the backend marks those hits `already_registered`.
  final Future<List<DetectedHardwareEntry>> Function({
    required List<String> registeredIdentifiers,
  })
  detectDevices;

  final Future<List<AkidaPairedHost>> Function() fetchAkidaHosts;

  /// Creates one same-host Akida target. Returning the saved host lets the
  /// scanner report its display name.
  final Future<AkidaPairedHost> Function(DetectedHardwareEntry entry)
  createSameHostAkidaHost;

  Future<HardwareAutoAddResult> run() async {
    final existing = await fetchAkidaHosts();
    final knownIdentifiers = existing
        .map((host) => host.deviceIdentifier.trim())
        .where((id) => id.isNotEmpty)
        .toSet();

    final detected = await detectDevices(
      registeredIdentifiers: knownIdentifiers.toList(growable: false),
    );

    var alreadyRegisteredCount = 0;
    final unsupportedByChipType = <String, int>{};
    final addedNames = <String>[];
    for (final entry in detected) {
      final identifier = entry.identifier.trim();
      if (identifier.isEmpty) {
        continue;
      }
      final knownAlready =
          entry.alreadyRegistered || knownIdentifiers.contains(identifier);
      if (knownAlready) {
        alreadyRegisteredCount++;
        continue;
      }
      if (!entry.isAutoAddable) {
        unsupportedByChipType[entry.chipType] =
            (unsupportedByChipType[entry.chipType] ?? 0) + 1;
        continue;
      }
      final saved = await createSameHostAkidaHost(entry);
      addedNames.add(saved.displayName);
      knownIdentifiers.add(identifier);
    }

    return HardwareAutoAddResult(
      addedNames: addedNames,
      alreadyRegisteredCount: alreadyRegisteredCount,
      unsupportedByChipType: unsupportedByChipType,
    );
  }
}
