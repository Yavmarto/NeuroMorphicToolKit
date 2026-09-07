import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/services.dart';
import 'package:neuro_toolkit/services/deployment/deployment_persistence.dart';
import 'package:neuro_toolkit/services/deployment/deployment_service.dart';
import 'package:neuro_toolkit/services/deployment/ssh_deployment_service.dart';

/// Writes an executable fake shell command into [bin], for tests that put a
/// fixture `bin/` directory ahead of the real one on `PATH`.
void writeExecutable(Directory bin, String name, String contents) {
  final file = File('${bin.path}/$name')..writeAsStringSync(contents);
  final chmod = Process.runSync('chmod', ['+x', file.path]);
  if (chmod.exitCode != 0) {
    throw StateError('Could not prepare fake $name command: ${chmod.stderr}');
  }
}

/// In-memory fake of [DeploymentSecretStorage].
class MemorySecretStorage implements DeploymentSecretStorage {
  final Map<String, String> values = <String, String>{};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}

/// Fake [AssetBundle] serving a synthetic deployment manifest and fixture
/// files, with knobs for the corruption/omission/offset scenarios the
/// bundle-integrity tests exercise.
class ManifestAssetBundle extends CachingAssetBundle {
  ManifestAssetBundle({
    this.corruptedFile,
    this.omittedManifestFile,
    this.unexpectedManifestFile,
    this.useOffsetByteData = false,
  });

  final String? corruptedFile;
  final String? omittedManifestFile;
  final String? unexpectedManifestFile;
  final bool useOffsetByteData;

  static const files = <String>[
    'docker-compose.yml',
    'docker-compose.prod.yml',
    'docker-compose.remote.yml',
    'install.sh',
    'migrate_legacy.py',
    'nmtk-stack.sh',
    'monitoring/alertmanager/alertmanager.yml',
    'monitoring/loki/loki-config.yml',
    'monitoring/prometheus/alert_rules.yml',
    'monitoring/prometheus/prometheus.yml',
    'monitoring/promtail/promtail-config.yml',
  ];

  static List<int> _fileBytes(String relative) =>
      utf8.encode('fixture contents for $relative\n');

  ByteData _byteData(List<int> bytes) {
    final exact = Uint8List.fromList(bytes);
    if (!useOffsetByteData) return ByteData.sublistView(exact);
    final padded = Uint8List(exact.length + 7);
    padded.setRange(3, 3 + exact.length, exact);
    return ByteData.view(padded.buffer, 3, exact.length);
  }

  @override
  Future<ByteData> load(String key) async {
    const prefix = 'assets/deployment/';
    if (!key.startsWith(prefix)) {
      throw StateError('Unexpected fixture asset: $key');
    }
    final relative = key.substring(prefix.length);
    if (relative == 'deployment-manifest.json') {
      final hashes = <String, String>{
        for (final file in files)
          file: sha256.convert(_fileBytes(file)).toString(),
      };
      if (omittedManifestFile != null) {
        hashes.remove(omittedManifestFile);
      }
      if (unexpectedManifestFile != null) {
        hashes[unexpectedManifestFile!] = sha256
            .convert(utf8.encode('unexpected fixture'))
            .toString();
      }
      return _byteData(
        utf8.encode(jsonEncode({'bundleVersion': 5, 'files': hashes})),
      );
    }
    if (!files.contains(relative)) {
      throw StateError('Unexpected fixture asset: $key');
    }
    final bytes = relative == corruptedFile
        ? utf8.encode('corrupted fixture contents for $relative\n')
        : _fileBytes(relative);
    return _byteData(bytes);
  }
}

/// Overrides [connect] to return a never-completing future, so tests can
/// exercise setup far enough to observe pre-SSH behavior without ever
/// reaching real network I/O or hanging.
class BlockingSshDeploymentService extends SshDeploymentService {
  BlockingSshDeploymentService();

  @override
  Future<SSHClient> connect({
    required DeploymentRequest request,
    required DeploymentPersistence persistence,
  }) {
    return Completer<SSHClient>().future;
  }
}
