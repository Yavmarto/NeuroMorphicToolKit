import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:neuro_toolkit/models/backend_deployment.dart';
import 'package:neuro_toolkit/services/deployment/deployment_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

abstract class DeploymentSecretStorage {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class PlatformDeploymentSecretStorage implements DeploymentSecretStorage {
  const PlatformDeploymentSecretStorage({
    FlutterSecureStorage storage = const FlutterSecureStorage(),
  }) : _storage = storage;

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

class DeploymentPersistence {
  DeploymentPersistence({
    required SharedPreferences preferences,
    DeploymentSecretStorage secureStorage =
        const PlatformDeploymentSecretStorage(),
  }) : _preferences = preferences,
       _secureStorage = secureStorage;

  static const _targetsKey = 'clientDeployment.targets.v1';
  static const _activeJobKey = 'clientDeployment.activeJob.v1';
  static const _secretPrefix = 'clientDeployment.credentials.v1.';
  static const _fingerprintPrefix = 'clientDeployment.hostFingerprint.v1.';

  final SharedPreferences _preferences;
  final DeploymentSecretStorage _secureStorage;

  Future<List<DeploymentTarget>> loadTargets() async {
    final raw = _preferences.getString(_targetsKey);
    if (raw == null || raw.isEmpty) return const [];
    final decoded = jsonDecode(raw);
    if (decoded is! List<dynamic>) return const [];
    return decoded
        .whereType<Map<String, dynamic>>()
        .map(DeploymentTarget.fromJson)
        .toList(growable: false);
  }

  Future<void> saveTarget(
    DeploymentTarget target,
    DeploymentRequest request,
  ) async {
    final targets = (await loadTargets())
        .where(
          (candidate) =>
              candidate.id == target.id ||
              target.targetType != 'remote_host' ||
              candidate.targetType != 'remote_host' ||
              candidate.host != target.host,
        )
        .toList();
    final index = targets.indexWhere((candidate) => candidate.id == target.id);
    if (index == -1) {
      targets.add(target);
    } else {
      targets[index] = target;
    }
    await _preferences.setString(
      _targetsKey,
      jsonEncode(targets.map((candidate) => candidate.toJson()).toList()),
    );
    await _secureStorage.write(
      '$_secretPrefix${target.id}',
      jsonEncode(request.toSecretJson()),
    );
  }

  Future<DeploymentRequest> requestForTarget(
    DeploymentTarget target, {
    bool cleanInstall = false,
  }) async {
    final raw = await _secureStorage.read('$_secretPrefix${target.id}') ?? '{}';
    final decoded = jsonDecode(raw);
    final secrets = decoded is Map<String, dynamic>
        ? decoded
        : <String, dynamic>{};
    return DeploymentRequest(
      targetType: target.targetType,
      mode: target.mode,
      displayName: target.displayName,
      host: target.host,
      username: target.username,
      sshPort: target.sshPort,
      authMethod: target.authMode,
      sshPassword: secrets['sshPassword'] as String? ?? '',
      sshPrivateKey: secrets['sshPrivateKey'] as String? ?? '',
      backendPort: target.backendPort,
      namespace: target.namespace,
      context: target.context,
      apiServer: target.apiServer,
      containerEngine: target.containerEngine,
      kubeconfig: secrets['kubeconfig'] as String? ?? '',
      adminToken: secrets['adminToken'] as String? ?? '',
      cleanInstall: cleanInstall,
      moduleEnvironment: target.moduleEnvironment,
      moduleSecrets: _moduleSecretsFromJson(secrets['moduleSecrets']),
    );
  }

  static Map<String, String> _moduleSecretsFromJson(Object? value) {
    if (value is! Map) return const {};
    return value.map(
      (dynamic key, dynamic item) => MapEntry(key.toString(), item.toString()),
    );
  }

  DeploymentJob? loadActiveJob() {
    final raw = _preferences.getString(_activeJobKey);
    if (raw == null || raw.isEmpty) return null;
    final decoded = jsonDecode(raw);
    return decoded is Map<String, dynamic>
        ? DeploymentJob.fromJson(decoded)
        : null;
  }

  Future<void> saveActiveJob(DeploymentJob? job) async {
    if (job == null) {
      await _preferences.remove(_activeJobKey);
      return;
    }
    await _preferences.setString(_activeJobKey, jsonEncode(job.toJson()));
  }

  Future<bool> verifyOrTrustHostKey({
    required String host,
    required int port,
    required Uint8List fingerprint,
  }) async {
    final key = '$_fingerprintPrefix$host:$port';
    final next = base64Encode(fingerprint);
    final trusted = await _secureStorage.read(key);
    if (trusted == null) {
      await _secureStorage.write(key, next);
      return true;
    }
    return trusted == next;
  }

  /// Drops the previously trusted fingerprint for [host]:[port] so the next
  /// connection trusts whatever key the server presents instead of rejecting
  /// it as changed — for when the server's host key legitimately changed
  /// (reinstall, replaced disk) and the user has confirmed that in person.
  Future<void> forgetHostKey({required String host, required int port}) {
    return _secureStorage.delete('$_fingerprintPrefix$host:$port');
  }
}
