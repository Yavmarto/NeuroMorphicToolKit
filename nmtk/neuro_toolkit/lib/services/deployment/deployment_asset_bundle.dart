import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class _DeploymentBundleIntegrityException implements Exception {
  const _DeploymentBundleIntegrityException(this.files);

  final List<String> files;
}

class DeploymentAssetBundle {
  const DeploymentAssetBundle({
    required this.version,
    required this.manifestHash,
    required this.fileHashes,
  });

  final int version;
  final String manifestHash;
  final Map<String, String> fileHashes;

  /// Every file that makes up a deployment bundle, relative to
  /// `assets/deployment/`. Shared by every collaborator that uploads,
  /// materializes, or hashes bundle contents.
  static const List<String> assetFiles = <String>[
    'deployment-manifest.json',
    'docker-compose.yml',
    'docker-compose.prod.yml',
    'docker-compose.remote.yml',
    'install.sh',
    'migrate_legacy.py',
    'nmtk-stack.sh',
    'monitoring/alertmanager/alertmanager.yml',
    'monitoring/alertmanager/entrypoint.sh',
    'monitoring/loki/loki-config.yml',
    'monitoring/prometheus/alert_rules.yml',
    'monitoring/prometheus/prometheus.yml',
    'monitoring/promtail/promtail-config.yml',
    'monitoring/grafana/provisioning/datasources/ds.yml',
    'monitoring/grafana/provisioning/dashboards/dashboards.yml',
    'monitoring/grafana/dashboards/nmtk-overview.json',
  ];

  static const String _bundleIntegrityRecovery =
      'This app build contains an inconsistent deployment bundle. '
      'Update or reinstall NMTK, then retry setup. The server was not changed.';

  factory DeploymentAssetBundle.fromManifestBytes(Uint8List bytes) {
    final payload = jsonDecode(utf8.decode(bytes));
    if (payload is! Map<String, dynamic>) {
      throw const FormatException('Deployment manifest must be a JSON object.');
    }
    final version = payload['bundleVersion'];
    final files = payload['files'];
    if (version is! int || version <= 0 || files is! Map<String, dynamic>) {
      throw const FormatException(
        'Deployment manifest is missing bundle metadata.',
      );
    }
    final fileHashes = <String, String>{
      for (final entry in files.entries)
        if (entry.value is String && (entry.value as String).isNotEmpty)
          entry.key: entry.value as String,
    };
    if (fileHashes.length != files.length) {
      throw const FormatException(
        'Deployment manifest contains an invalid file hash.',
      );
    }
    return DeploymentAssetBundle(
      version: version,
      manifestHash: sha256.convert(bytes).toString(),
      fileHashes: Map.unmodifiable(fileHashes),
    );
  }

  static void validateRemoteChecksums({
    required DeploymentAssetBundle bundle,
    required Map<String, String> actualChecksums,
  }) {
    final expected = <String, String>{
      ...bundle.fileHashes,
      'deployment-manifest.json': bundle.manifestHash,
    };
    final mismatches = expected.entries
        .where((entry) => actualChecksums[entry.key] != entry.value)
        .map((entry) => entry.key)
        .toList(growable: false);
    if (mismatches.isNotEmpty) {
      throw StateError(
        'Uploaded deployment bundle verification failed for '
        '${mismatches.join(', ')}.',
      );
    }
  }

  /// Parses the standard output format emitted by GNU and BusyBox sha256sum.
  ///
  /// This is deliberately separate from validation so a malformed command
  /// response is reported as an operator-facing transport failure rather than
  /// as though every uploaded file had changed.
  static Map<String, String> parseRemoteChecksumOutput(String output) {
    final checksums = <String, String>{};
    for (final line in output.split('\n')) {
      final match = RegExp(r'^([a-fA-F0-9]{64})\s+\*?(.+)$').firstMatch(line);
      if (match != null) {
        checksums[match.group(2)!] = match.group(1)!.toLowerCase();
      }
    }
    if (checksums.isEmpty) {
      throw const FormatException(
        'Remote checksum verification returned unreadable output.',
      );
    }
    return Map.unmodifiable(checksums);
  }

  /// Returns the exact bytes backing [data], without copying, regardless of
  /// whether the underlying [ByteData] view starts at a non-zero offset.
  static Uint8List exactBytes(ByteData data) =>
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);

  /// Loads and integrity-checks the bundle manifest from [assets], verifying
  /// every file it lists is present, hashed, and unchanged from what the
  /// manifest expects. Throws a sanitized [StateError] on any mismatch so a
  /// broken app build fails setup before it ever touches a server.
  static Future<DeploymentAssetBundle> load(AssetBundle assets) async {
    try {
      final data = await assets.load(
        'assets/deployment/deployment-manifest.json',
      );
      final bundle = DeploymentAssetBundle.fromManifestBytes(exactBytes(data));
      final expectedFiles = assetFiles
          .where((relative) => relative != 'deployment-manifest.json')
          .toSet();
      final manifestFiles = bundle.fileHashes.keys.toSet();
      final invalidFiles = <String>{
        ...expectedFiles.difference(manifestFiles),
        ...manifestFiles.difference(expectedFiles),
      };
      final sha256Pattern = RegExp(r'^[a-f0-9]{64}$');

      for (final relative in expectedFiles.intersection(manifestFiles)) {
        final expectedHash = bundle.fileHashes[relative]!;
        if (!sha256Pattern.hasMatch(expectedHash)) {
          invalidFiles.add(relative);
          continue;
        }
        try {
          final asset = await assets.load('assets/deployment/$relative');
          final actualHash = sha256.convert(exactBytes(asset)).toString();
          if (actualHash != expectedHash) invalidFiles.add(relative);
        } on Object {
          invalidFiles.add(relative);
        }
      }

      if (invalidFiles.isNotEmpty) {
        final sortedFiles = invalidFiles.toList()..sort();
        throw _DeploymentBundleIntegrityException(sortedFiles);
      }
      return bundle;
    } on _DeploymentBundleIntegrityException catch (error) {
      debugPrint(
        'NMTK deployment bundle integrity check failed for: '
        '${error.files.join(', ')}',
      );
      throw StateError(_bundleIntegrityRecovery);
    } on Object {
      debugPrint(
        'NMTK deployment bundle integrity check failed for: '
        'deployment-manifest.json',
      );
      throw StateError(_bundleIntegrityRecovery);
    }
  }
}
