import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:neuro_toolkit/services/launcher_control_bootstrap_service.dart';

class _FakeBootstrapEnvironment implements LauncherControlBootstrapEnvironment {
  _FakeBootstrapEnvironment({this.pythonPath = '/usr/bin/python3'});

  @override
  final bool isWeb = false;

  @override
  final bool isNativeDesktop = true;

  @override
  final bool isBundled = false;

  @override
  final String currentDirectory = '/tmp';

  @override
  final String resourcesRootPath = '/tmp/resources';

  @override
  final Map<String, String> environment = const <String, String>{};

  final String? pythonPath;
  final List<List<String>> startedCommands = <List<String>>[];

  @override
  Future<String?> findPython() async => pythonPath;

  @override
  Future<bool> fileExists(String path) async => true;

  @override
  Future<Process> startProcess(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) async {
    startedCommands.add(<String>[
      executable,
      ...arguments,
      if (workingDirectory != null) 'cwd=$workingDirectory',
      if (environment?['PYTHONPATH'] != null)
        'py=${environment!['PYTHONPATH']!}',
    ]);
    return _FakeProcess();
  }
}

class _FakeProcess implements Process {
  @override
  Future<int> get exitCode async => 0;

  @override
  int get pid => 1;

  @override
  IOSink get stdin => throw UnimplementedError();

  @override
  Stream<List<int>> get stderr => const Stream<List<int>>.empty();

  @override
  Stream<List<int>> get stdout => const Stream<List<int>>.empty();

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) => true;
}

void main() {
  test('starts local control API when localhost is not healthy', () async {
    var healthChecks = 0;
    final client = MockClient((request) async {
      if (request.url.path == '/health') {
        healthChecks += 1;
        if (healthChecks < 2) {
          throw const SocketException('Connection refused');
        }
        return http.Response(jsonEncode(<String, String>{'status': 'ok'}), 200);
      }
      return http.Response('', 404);
    });
    final environment = _FakeBootstrapEnvironment();
    final service = LauncherControlBootstrapService(
      environment: environment,
      client: client,
      startupTimeout: const Duration(seconds: 2),
      pollInterval: const Duration(milliseconds: 10),
    );

    final state = await service.ensureReady();

    expect(state.status, LauncherBootstrapStatus.ready);
    expect(environment.startedCommands, hasLength(1));
    expect(
      environment.startedCommands.single.join(' '),
      contains('scripts/launcher_control_service.py'),
    );
    expect(
      environment.startedCommands.single.join(' '),
      contains('--host 0.0.0.0'),
    );
  });

  test(
    'does not start a local process when an explicit control API is set',
    () async {
      final client = MockClient((request) async {
        return http.Response(jsonEncode(<String, String>{'status': 'ok'}), 200);
      });
      final environment = _FakeBootstrapEnvironment();
      final service = LauncherControlBootstrapService(
        environment: environment,
        client: client,
        explicitBaseUriOverride: Uri.parse('http://198.51.100.50:8090'),
      );

      final state = await service.ensureReady();

      expect(state.status, LauncherBootstrapStatus.ready);
      expect(environment.startedCommands, isEmpty);
    },
  );

  test('polls explicit control API until suite_api reports ready', () async {
    var healthChecks = 0;
    final client = MockClient((request) async {
      if (request.url.path == '/health') {
        healthChecks += 1;
        if (healthChecks <= 2) {
          return http.Response(
            jsonEncode(<String, dynamic>{
              'status': 'ok',
              'suiteApiStatus': 'starting',
            }),
            200,
          );
        }
        return http.Response(
          jsonEncode(<String, dynamic>{
            'status': 'ok',
            'suiteApiStatus': 'ready',
          }),
          200,
        );
      }
      return http.Response('', 404);
    });
    final environment = _FakeBootstrapEnvironment();
    final service = LauncherControlBootstrapService(
      environment: environment,
      client: client,
      startupTimeout: const Duration(seconds: 2),
      pollInterval: const Duration(milliseconds: 10),
      explicitBaseUriOverride: Uri.parse('http://127.0.0.1:8090'),
    );

    final state = await service.ensureReady();

    expect(state.status, LauncherBootstrapStatus.ready);
    expect(environment.startedCommands, isEmpty);
    expect(healthChecks, greaterThanOrEqualTo(3));
  });

  test(
    'surfaces suite_api failure through explicit control API polling',
    () async {
      final client = MockClient((request) async {
        if (request.url.path == '/health') {
          return http.Response(
            jsonEncode(<String, dynamic>{
              'status': 'ok',
              'suiteApiStatus': 'preflight_failed',
              'suiteApiMessage': 'suite_api venv install failed',
            }),
            200,
          );
        }
        return http.Response('', 404);
      });
      final environment = _FakeBootstrapEnvironment();
      final service = LauncherControlBootstrapService(
        environment: environment,
        client: client,
        startupTimeout: const Duration(seconds: 2),
        pollInterval: const Duration(milliseconds: 10),
        explicitBaseUriOverride: Uri.parse('http://127.0.0.1:8090'),
      );

      final state = await service.ensureReady();

      expect(state.status, LauncherBootstrapStatus.preflightFailed);
      expect(state.message, contains('suite_api venv install failed'));
      expect(environment.startedCommands, isEmpty);
      // The control API answered /health — it's reachable even though the
      // target (suite_api) isn't ready, so "Set up a new server" shouldn't be
      // blocked on this.
      expect(state.controlApiReachable, isTrue);
    },
  );

  test('returns preflight failure when Python is unavailable', () async {
    final client = MockClient((request) async {
      throw const SocketException('Connection refused');
    });
    final service = LauncherControlBootstrapService(
      environment: _FakeBootstrapEnvironment(pythonPath: null),
      client: client,
      startupTimeout: const Duration(milliseconds: 50),
      pollInterval: const Duration(milliseconds: 10),
    );

    final state = await service.ensureReady();

    expect(state.status, LauncherBootstrapStatus.preflightFailed);
    expect(state.message, contains('Python 3 was not found'));
    // Genuinely unreachable — /health never answered.
    expect(state.controlApiReachable, isFalse);
  });

  test('waits until suite_api reports ready', () async {
    var healthChecks = 0;
    final client = MockClient((request) async {
      if (request.url.path == '/health') {
        healthChecks += 1;
        if (healthChecks == 1) {
          throw const SocketException('Connection refused');
        }
        if (healthChecks == 2) {
          return http.Response(
            jsonEncode(<String, dynamic>{
              'status': 'ok',
              'suiteApiStatus': 'starting',
            }),
            200,
          );
        }
        return http.Response(
          jsonEncode(<String, dynamic>{
            'status': 'ok',
            'suiteApiStatus': 'ready',
          }),
          200,
        );
      }
      return http.Response('', 404);
    });
    final environment = _FakeBootstrapEnvironment();
    final service = LauncherControlBootstrapService(
      environment: environment,
      client: client,
      startupTimeout: const Duration(seconds: 2),
      pollInterval: const Duration(milliseconds: 10),
    );

    final state = await service.ensureReady();

    expect(state.status, LauncherBootstrapStatus.ready);
    expect(environment.startedCommands, hasLength(1));
    expect(healthChecks, greaterThanOrEqualTo(2));
  });

  test(
    'surfaces suite_api preflight failure from control API health',
    () async {
      var healthChecks = 0;
      final client = MockClient((request) async {
        if (request.url.path == '/health') {
          healthChecks += 1;
          if (healthChecks == 1) {
            throw const SocketException('Connection refused');
          }
          return http.Response(
            jsonEncode(<String, dynamic>{
              'status': 'ok',
              'suiteApiStatus': 'preflight_failed',
              'suiteApiMessage': 'suite_api runtime dependencies are missing',
            }),
            200,
          );
        }
        return http.Response('', 404);
      });
      final environment = _FakeBootstrapEnvironment();
      final service = LauncherControlBootstrapService(
        environment: environment,
        client: client,
        startupTimeout: const Duration(seconds: 2),
        pollInterval: const Duration(milliseconds: 10),
      );

      final state = await service.ensureReady();

      expect(state.status, LauncherBootstrapStatus.preflightFailed);
      expect(
        state.message,
        contains('suite_api runtime dependencies are missing'),
      );
      expect(environment.startedCommands, hasLength(1));
      expect(state.controlApiReachable, isTrue);
    },
  );

  test('detects a clean unprovisioned host via connection-refused, without '
      'waiting out the full timeout', () async {
    var healthChecks = 0;
    final client = MockClient((request) async {
      healthChecks += 1;
      throw const SocketException(
        'Connection refused',
        osError: OSError('Connection refused', 61),
      );
    });
    final service = LauncherControlBootstrapService(
      client: client,
      startupTimeout: const Duration(seconds: 5),
      pollInterval: const Duration(milliseconds: 10),
      explicitBaseUriOverride: Uri.parse('http://198.51.100.99:8090'),
    );

    final state = await service.ensureReady();

    expect(state.status, LauncherBootstrapStatus.preflightFailed);
    expect(state.hostReachableNoServer, isTrue);
    expect(state.message, contains('reachable'));
    expect(state.message, contains('nothing is installed'));
    // Connection-refused is deterministic — stop polling instead of burning
    // the full 5s timeout.
    expect(healthChecks, lessThan(10));
  });

  test('treats a timed-out/unreachable host as not installable', () async {
    final client = MockClient((request) async {
      throw const SocketException('Network is unreachable');
    });
    final service = LauncherControlBootstrapService(
      client: client,
      startupTimeout: const Duration(milliseconds: 50),
      pollInterval: const Duration(milliseconds: 10),
      explicitBaseUriOverride: Uri.parse('http://192.0.2.1:8090'),
    );

    final state = await service.ensureReady();

    expect(state.status, LauncherBootstrapStatus.preflightFailed);
    expect(state.hostReachableNoServer, isFalse);
    expect(state.controlApiReachable, isFalse);
  });
}
