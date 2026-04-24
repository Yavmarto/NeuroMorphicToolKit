import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:neuro_toolkit/services/launcher_control_bootstrap_service.dart';

class _FakeBootstrapEnvironment implements LauncherControlBootstrapEnvironment {
  _FakeBootstrapEnvironment({
    this.isWeb = false,
    this.isNativeDesktop = true,
    this.isBundled = false,
    this.currentDirectory = '/repo/nmtk/neuro_toolkit',
    this.resourcesRootPath = '/bundle/Contents/Resources',
    this.environment = const <String, String>{},
    this.pythonPath = '/usr/bin/python3',
    this.scriptExists = true,
  });

  @override
  final bool isWeb;

  @override
  final bool isNativeDesktop;

  @override
  final bool isBundled;

  @override
  final String currentDirectory;

  @override
  final String resourcesRootPath;

  @override
  final Map<String, String> environment;

  final String? pythonPath;
  final bool scriptExists;
  final List<List<String>> startedCommands = <List<String>>[];

  @override
  Future<String?> findPython() async => pythonPath;

  @override
  Future<bool> fileExists(String path) async => scriptExists;

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
  });

  test('does not start a local process when an explicit control API is set',
      () async {
    final client = MockClient((request) async {
      return http.Response(jsonEncode(<String, String>{'status': 'ok'}), 200);
    });
    final environment = _FakeBootstrapEnvironment();
    final service = LauncherControlBootstrapService(
      environment: environment,
      client: client,
      explicitBaseUriOverride: Uri.parse('http://192.168.1.50:8090'),
    );

    final state = await service.ensureReady();

    expect(state.status, LauncherBootstrapStatus.ready);
    expect(environment.startedCommands, isEmpty);
  });

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
  });
}
