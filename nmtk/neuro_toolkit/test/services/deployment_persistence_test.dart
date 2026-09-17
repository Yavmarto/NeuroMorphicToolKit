import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_toolkit/models/backend_deployment.dart';
import 'package:neuro_toolkit/services/deployment/deployment_persistence.dart';
import 'package:neuro_toolkit/services/deployment/deployment_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MemorySecretStorage implements DeploymentSecretStorage {
  final values = <String, String>{};

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('credentials stay out of ordinary preferences', () async {
    const password = 'do-not-store-in-preferences';
    const privateKey = '-----BEGIN OPENSSH PRIVATE KEY-----secret';
    const adminToken = 'generated-admin-token';
    final preferences = await SharedPreferences.getInstance();
    final secrets = _MemorySecretStorage();
    final persistence = DeploymentPersistence(
      preferences: preferences,
      secureStorage: secrets,
    );
    const target = DeploymentTarget(
      id: 'remote-one',
      displayName: 'Remote',
      targetType: 'remote_host',
      mode: 'docker',
      authMode: 'ssh_password',
      host: '203.0.113.90',
      backendPort: 9000,
    );
    const request = DeploymentRequest(
      targetType: 'remote_host',
      mode: 'docker',
      displayName: 'Remote',
      host: '203.0.113.90',
      username: 'nmtk',
      authMethod: 'ssh_password',
      sshPassword: password,
      sshPrivateKey: privateKey,
      adminToken: adminToken,
    );

    await persistence.saveTarget(target, request);

    final ordinaryValues = jsonEncode(
      preferences
          .getKeys()
          .map((key) => preferences.get(key))
          .toList(growable: false),
    );
    expect(ordinaryValues, isNot(contains(password)));
    expect(ordinaryValues, isNot(contains(privateKey)));
    expect(ordinaryValues, isNot(contains(adminToken)));
    expect(jsonEncode(secrets.values), contains(password));
    expect((await persistence.requestForTarget(target)).adminToken, adminToken);
  });

  test('release metadata round-trips through secure storage', () async {
    final preferences = await SharedPreferences.getInstance();
    final secrets = _MemorySecretStorage();
    final persistence = DeploymentPersistence(
      preferences: preferences,
      secureStorage: secrets,
    );
    const target = DeploymentTarget(
      id: 'remote-release',
      displayName: 'Remote',
      targetType: 'remote_host',
      mode: 'docker',
      authMode: 'ssh_key',
      host: '203.0.113.90',
      backendPort: 9000,
    );
    const request = DeploymentRequest(
      targetType: 'remote_host',
      mode: 'docker',
      displayName: 'Remote',
      host: '203.0.113.90',
      username: 'nmtk-deploy',
      releaseVersion: '1.4.0',
      schemaMigration: true,
    );

    await persistence.saveTarget(target, request);

    final restored = await persistence.requestForTarget(target);
    expect(restored.releaseVersion, '1.4.0');
    expect(restored.schemaMigration, isTrue);
    expect(restored.deploymentImageTag, '1.4.0');
  });

  test('host keys use trust on first use and reject later changes', () async {
    final persistence = DeploymentPersistence(
      preferences: await SharedPreferences.getInstance(),
      secureStorage: _MemorySecretStorage(),
    );

    expect(
      await persistence.verifyOrTrustHostKey(
        host: 'server.local',
        port: 22,
        fingerprint: Uint8List.fromList(utf8.encode('SHA256:first')),
      ),
      isTrue,
    );
    expect(
      await persistence.verifyOrTrustHostKey(
        host: 'server.local',
        port: 22,
        fingerprint: Uint8List.fromList(utf8.encode('SHA256:first')),
      ),
      isTrue,
    );
    expect(
      await persistence.verifyOrTrustHostKey(
        host: 'server.local',
        port: 22,
        fingerprint: Uint8List.fromList(utf8.encode('SHA256:changed')),
      ),
      isFalse,
    );
  });
}
