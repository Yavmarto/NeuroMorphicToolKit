import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_toolkit/services/control_api_service.dart';

void main() {
  group('launcher base URL normalization', () {
    test('host-only input uses the launcher default port', () {
      expect(
        ControlApiService.normalizeBaseUrl('192.168.2.51'),
        'http://192.168.2.51:8090',
      );
    });

    test('explicit scheme and port are preserved', () {
      expect(
        ControlApiService.normalizeBaseUrl('https://launcher.example:8443/'),
        'https://launcher.example:8443',
      );
    });

    test('rejects paths, queries, and non-HTTP schemes', () {
      expect(
        () => ControlApiService.normalizeBaseUrl(
          'http://launcher.example/internal',
        ),
        throwsFormatException,
      );
      expect(
        () => ControlApiService.normalizeBaseUrl('ssh://launcher.example'),
        throwsFormatException,
      );
    });
  });

  test('legacy optional Akida metadata cannot block launcher readiness', () {
    final settings = LauncherControlSettings.fromJson(<String, dynamic>{
      'logLevel': 'info',
      'mujocoAvailable': false,
      'pythonAvailable': true,
      'backendDeploymentReady': true,
      'selectedBackendDeploymentTarget': null,
      'pynqBoards': <dynamic>[],
      'akidaHosts': <dynamic>[
        <String, dynamic>{
          'id': 'cc422a68-1377-45c3-9947-2f2756ef164a',
          'displayName': 'Hp prodesk',
          'host': '192.168.2.51',
          'sshPort': 22,
          'controlPort': 8091,
          'runtimeApiUrl': 'http://192.168.2.51:8002',
          'controlApiUrl': 'http://192.168.2.51:8090',
          'authMode': 'ssh_key',
          'runtimeMode': 'unknown',
          'state': 'simulator_only',
          'lastReadinessMessage':
              'TensorFlow is unavailable; simulator remains optional.',
          'lastVerifiedAt': '2026-06-03T14:13:46.391711+00:00',
          'capabilitySnapshot': null,
          'isDefault': true,
          'hasPassword': false,
        },
        <String, dynamic>{
          // Deliberately malformed optional inventory entry.
          'id': 'stale-host',
          'sshPort': 'not-an-integer',
        },
      ],
      'selectedAkidaHostId': 'cc422a68-1377-45c3-9947-2f2756ef164a',
    });

    expect(settings.backendDeploymentReady, isTrue);
    expect(settings.akidaHosts, hasLength(1));
    expect(settings.akidaHosts.single.host, '192.168.2.51');
    expect(
      settings.akidaHosts.single.controlApiUrl,
      'http://192.168.2.51:8090',
    );
  });
}
