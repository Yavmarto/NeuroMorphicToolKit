import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_toolkit/features/server/provision/provision_service.dart';
import 'package:neuro_toolkit/services/deployment/deployment_asset_bundle.dart';
import 'package:neuro_toolkit/services/deployment/job_registry.dart';
import 'package:neuro_toolkit/services/deployment/deployment_persistence.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late ProvisionService service;
  late JobRegistry registry;

  setUp(() {
    SharedPreferences.setMockInitialValues(const {});
    service = ProvisionService();
    registry = JobRegistry(
      persistenceFactory: () async =>
          DeploymentPersistence(preferences: await SharedPreferences.getInstance()),
    );
  });

  Future<DeploymentAssetBundle> unusedLoadBundle() =>
      throw StateError('should not reach the bundle loader');
  Future<void> unusedRunDeployment(job, target, request, bundle) =>
      throw StateError('should not reach the deployment runner');
  Future<bool> unusedIsApiReady(target) async => false;

  test('rejects a non-IPv4 host before opening SSH', () async {
    await expectLater(
      () => service.setupRemoteServer(
        const RemoteServerSetupRequest(
          host: 'not-an-ip',
          adminUsername: 'root',
          adminPassword: 'secret',
          containerEngine: 'docker',
        ),
        registry: registry,
        loadBundle: unusedLoadBundle,
        runDeployment: unusedRunDeployment,
        isApiReady: unusedIsApiReady,
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('rejects a request with neither password nor private key', () async {
    await expectLater(
      () => service.setupRemoteServer(
        const RemoteServerSetupRequest(
          host: '203.0.113.90',
          adminUsername: 'root',
          containerEngine: 'docker',
        ),
        registry: registry,
        loadBundle: unusedLoadBundle,
        runDeployment: unusedRunDeployment,
        isApiReady: unusedIsApiReady,
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('rejects an unsupported container engine', () async {
    await expectLater(
      () => service.setupRemoteServer(
        const RemoteServerSetupRequest(
          host: '203.0.113.90',
          adminUsername: 'root',
          adminPassword: 'secret',
          containerEngine: 'kubernetes',
        ),
        registry: registry,
        loadBundle: unusedLoadBundle,
        runDeployment: unusedRunDeployment,
        isApiReady: unusedIsApiReady,
      ),
      throwsA(isA<FormatException>()),
    );
  });
}
