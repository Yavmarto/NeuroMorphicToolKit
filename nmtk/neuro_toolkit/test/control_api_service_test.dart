import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:neuro_toolkit/services/control_api_service.dart';

void main() {
  group('launcher base URL normalization', () {
    test('host-only input uses the launcher default port', () {
      expect(
        ControlApiService.normalizeBaseUrl('192.168.2.90'),
        'http://192.168.2.90:8090',
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
          'host': '192.168.2.90',
          'sshPort': 22,
          'controlPort': 8091,
          'runtimeApiUrl': 'http://192.168.2.90:8002',
          'controlApiUrl': 'http://192.168.2.90:8091',
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
    expect(settings.akidaHosts.single.host, '192.168.2.90');
    expect(
      settings.akidaHosts.single.controlApiUrl,
      'http://192.168.2.90:8091',
    );
  });

  group('suite API address', () {
    ControlApiService serviceAt(String controlBaseUrl, {http.Client? client}) =>
        ControlApiService(
          baseUri: Uri.parse(controlBaseUrl),
          client: client ?? MockClient((_) async => http.Response('{}', 200)),
        );

    test('a remote launcher host implies a remote backend', () {
      expect(
        serviceAt('http://192.168.2.90:8090').suiteApiBaseUri.toString(),
        'http://192.168.2.90:9000',
      );
    });

    test('a loopback launcher host implies a local backend', () {
      expect(
        serviceAt('http://127.0.0.1:8090').suiteApiBaseUri.toString(),
        'http://localhost:9000',
      );
    });

    test('the launcher scheme carries over to a remote backend', () {
      expect(
        serviceAt('https://backend.example:8443').suiteApiBaseUri.toString(),
        'https://backend.example:9000',
      );
    });
  });

  group('ControlApiService.fetchBackendVersion', () {
    Future<String?> versionFrom(http.Response Function(Uri) respond) {
      return ControlApiService(
        baseUri: Uri.parse('http://192.168.2.90:8090'),
        client:
            MockClient((http.Request request) async => respond(request.url)),
      ).fetchBackendVersion();
    }

    test('reads the version the backend reports', () async {
      expect(
        await versionFrom(
          (uri) {
            expect(uri.toString(), 'http://192.168.2.90:9000/api/suite/health');
            return http.Response(
              jsonEncode(<String, String>{
                'status': 'ok',
                'service': 'suite_api',
                'version': 'v1.2.0',
              }),
              200,
            );
          },
        ),
        'v1.2.0',
      );
    });

    test('returns null for a backend too old to report a version', () async {
      // Pre-version-stamping backends answer health without the field; that is
      // "unknown", not an error, and must not surface an update prompt.
      expect(
        await versionFrom(
          (_) => http.Response(
            jsonEncode(
                <String, String>{'status': 'ok', 'service': 'suite_api'}),
            200,
          ),
        ),
        isNull,
      );
    });

    test('returns null when the backend is unreachable or erroring', () async {
      expect(await versionFrom((_) => http.Response('nope', 502)), isNull);
      expect(
        await ControlApiService(
          baseUri: Uri.parse('http://192.168.2.90:8090'),
          client: MockClient((_) async => throw http.ClientException('down')),
        ).fetchBackendVersion(),
        isNull,
      );
    });

    test('returns null on a malformed body', () async {
      expect(
        await versionFrom((_) => http.Response('not json', 200)),
        isNull,
      );
    });
  });

  test('Akida runtime update operations use the selected host contract',
      () async {
    final requests = <http.Request>[];
    final service = ControlApiService(
      baseUri: Uri.parse('http://192.168.2.90:8090'),
      client: MockClient((request) async {
        requests.add(request);
        return http.Response(
          jsonEncode(<String, dynamic>{
            'jobId': 'job-1',
            'hostId': 'host-1',
            'artifactVersion': '0.6.0',
            'artifactSha256': 'abc',
            'stage': request.method == 'POST' ? 'queued' : 'completed',
            'progress': request.method == 'POST' ? 0 : 100,
            'message': 'Ready',
            'status': request.method == 'POST' ? 'queued' : 'completed',
            'installedVersion': '0.6.0',
          }),
          request.method == 'POST' ? 202 : 200,
        );
      }),
    );

    final created = await service.startAkidaRuntimeUpdate('host-1');
    final completed = await service.fetchAkidaRuntimeUpdate(
      'host-1',
      created.jobId,
    );

    expect(created.isTerminal, isFalse);
    expect(completed.isCompleted, isTrue);
    expect(completed.installedVersion, '0.6.0');
    expect(requests.map((request) => request.url.port), everyElement(8090));
    expect(
      requests.map((request) => request.url.path),
      <String>[
        '/api/launcher/akida/hosts/host-1/runtime-update-jobs',
        '/api/launcher/akida/hosts/host-1/runtime-update-jobs/job-1',
      ],
    );
  });
}
