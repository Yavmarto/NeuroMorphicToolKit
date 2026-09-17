import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_toolkit/services/deployment/client_deployment_service.dart';
import 'package:neuro_toolkit/services/deployment/deployment_asset_bundle.dart';
import 'package:neuro_toolkit/services/deployment/deployment_persistence.dart';
import 'package:neuro_toolkit/services/deployment/deployment_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'deployment/client_deployment_test_fakes.dart';

void main() {
  test(
    'deployment bundle accepts exact slices from offset asset data',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final persistence = DeploymentPersistence(
        preferences: await SharedPreferences.getInstance(),
        secureStorage: MemorySecretStorage(),
      );
      final service = ClientDeploymentService(
        assets: ManifestAssetBundle(useOffsetByteData: true),
        persistenceFactory: () async => persistence,
        ssh: BlockingSshDeploymentService(),
      );

      final job = await service.setupRemoteServer(
        const RemoteServerSetupRequest(
          host: '203.0.113.35',
          adminUsername: 'root',
          adminPassword: 'temporary-admin-secret',
          containerEngine: 'podman',
        ),
      );

      expect(job.bundleVersion, 5);
      expect(job.bundleManifestHash, hasLength(64));
      expect(persistence.loadActiveJob()?.id, job.id);
    },
  );

  test(
    'invalid deployment bundles fail before persistence or SSH setup',
    () async {
      final cases = <({String name, AssetBundle assets})>[
        (
          name: 'mismatched contents',
          assets: ManifestAssetBundle(corruptedFile: 'docker-compose.yml'),
        ),
        (
          name: 'missing manifest entry',
          assets: ManifestAssetBundle(omittedManifestFile: 'install.sh'),
        ),
        (
          name: 'unexpected manifest entry',
          assets: ManifestAssetBundle(unexpectedManifestFile: 'unexpected.yml'),
        ),
      ];

      for (final testCase in cases) {
        var persistenceCalls = 0;
        final service = ClientDeploymentService(
          assets: testCase.assets,
          persistenceFactory: () async {
            persistenceCalls += 1;
            throw StateError('Persistence must not be reached.');
          },
          ssh: BlockingSshDeploymentService(),
        );

        await expectLater(
          service.setupRemoteServer(
            const RemoteServerSetupRequest(
              host: '203.0.113.36',
              adminUsername: 'root',
              adminPassword: 'temporary-admin-secret',
              containerEngine: 'podman',
            ),
          ),
          throwsA(
            isA<StateError>()
                .having(
                  (error) => error.message,
                  'message',
                  'This app build contains an inconsistent deployment bundle. '
                      'Update or reinstall NMTK, then retry setup. '
                      'The server was not changed.',
                )
                .having(
                  (error) => error.toString(),
                  'safe error',
                  isNot(contains('temporary-admin-secret')),
                ),
          ),
          reason: testCase.name,
        );
        expect(persistenceCalls, 0, reason: testCase.name);
      }
    },
  );

  test('deployment bundle verifies every uploaded asset checksum', () {
    const deploymentFiles = <String>[
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
    const checksum =
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
    final bundle = DeploymentAssetBundle.fromManifestBytes(
      Uint8List.fromList(
        utf8.encode(
          jsonEncode({
            'bundleVersion': 3,
            'files': {for (final file in deploymentFiles) file: checksum},
          }),
        ),
      ),
    );

    final parsed = DeploymentAssetBundle.parseRemoteChecksumOutput(
      <String>[
        for (final file in deploymentFiles) '$checksum  $file',
        '${bundle.manifestHash}  deployment-manifest.json',
      ].join('\n'),
    );

    expect(
      () => DeploymentAssetBundle.validateRemoteChecksums(
        bundle: bundle,
        actualChecksums: {
          for (final file in deploymentFiles) file: checksum,
          'install.sh': 'different',
          'deployment-manifest.json': bundle.manifestHash,
        },
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('install.sh'),
        ),
      ),
    );
    expect(
      () => DeploymentAssetBundle.validateRemoteChecksums(
        bundle: bundle,
        actualChecksums: {
          for (final file in deploymentFiles) file: checksum,
          'deployment-manifest.json': bundle.manifestHash,
        },
      ),
      returnsNormally,
    );
    expect(parsed, {
      for (final file in deploymentFiles) file: checksum,
      'deployment-manifest.json': bundle.manifestHash,
    });
  });

  test('deployment bundle reports unreadable checksum output separately', () {
    expect(
      () => DeploymentAssetBundle.parseRemoteChecksumOutput(
        'remote command did not produce checksums',
      ),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('unreadable output'),
        ),
      ),
    );
  });
}
