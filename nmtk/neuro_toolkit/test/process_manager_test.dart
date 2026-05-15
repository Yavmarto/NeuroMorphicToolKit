// ignore_for_file: unawaited_futures
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:neuro_toolkit/models/module.dart';
import 'package:neuro_toolkit/services/process_manager.dart';
import 'package:path/path.dart' as p;

class MockProcess implements Process {
  final StreamController<List<int>> _stdoutController =
      StreamController<List<int>>.broadcast();
  final StreamController<List<int>> _stderrController =
      StreamController<List<int>>.broadcast();
  final Completer<int> _exitCodeCompleter = Completer<int>();

  @override
  Stream<List<int>> get stdout => _stdoutController.stream;

  @override
  Stream<List<int>> get stderr => _stderrController.stream;

  @override
  Future<int> get exitCode => _exitCodeCompleter.future;

  @override
  int get pid => 123;

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    if (!_exitCodeCompleter.isCompleted) {
      _exitCodeCompleter.complete(0);
    }
    return true;
  }

  void simulateExit(int code) {
    if (!_exitCodeCompleter.isCompleted) {
      _exitCodeCompleter.complete(code);
    }
  }

  void simulateStdout(String data) {
    _stdoutController.add(utf8.encode(data));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockProcessRunner implements ProcessRunner {
  final Map<String, MockProcess> mockProcesses = {};
  final List<InvocationRecord> calls = [];
  ProcessResult? runResult;

  @override
  Future<Process> start(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    bool includeParentEnvironment = true,
    bool runInShell = false,
    ProcessStartMode mode = ProcessStartMode.normal,
  }) async {
    calls.add(
      InvocationRecord('start', executable, arguments, workingDirectory),
    );
    final process = mockProcesses[executable] ?? MockProcess();
    // Remove if it was a one-off mock to ensure next call gets a fresh one or a different mock
    if (mockProcesses.containsKey(executable)) {
      mockProcesses.remove(executable);
    }
    return process;
  }

  @override
  Future<ProcessResult> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    bool includeParentEnvironment = true,
    bool runInShell = false,
    Encoding? stdoutEncoding = systemEncoding,
    Encoding? stderrEncoding = systemEncoding,
  }) async {
    calls.add(InvocationRecord('run', executable, arguments, workingDirectory));

    // Simulate venv creation by creating the directory/file on disk
    if (arguments.contains('venv')) {
      final venvPath = p.join(workingDirectory!, 'venv');
      Directory(venvPath).createSync(recursive: true);
      final pythonBin = Platform.isWindows
          ? p.join(venvPath, 'Scripts', 'python.exe')
          : p.join(venvPath, 'bin', 'python');
      File(pythonBin).createSync(recursive: true);
    }

    // Special case for lsof to avoid hanging if ProcessManager calls it
    if (executable == 'lsof') {
      return ProcessResult(
        0,
        1,
        '',
        '',
      ); // Return 1 to indicate no process found
    }

    return runResult ?? ProcessResult(0, 0, 'success', '');
  }
}

class InvocationRecord {
  final String method;
  final String executable;
  final List<String> arguments;
  final String? workingDirectory;

  InvocationRecord(
    this.method,
    this.executable,
    this.arguments,
    this.workingDirectory,
  );
}

void main() {
  const MethodChannel channel = MethodChannel(
    'plugins.flutter.io/path_provider',
  );
  TestWidgetsFlutterBinding.ensureInitialized();

  late ProcessManager processManager;
  late MockProcessRunner mockRunner;

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
      return '.';
    });

    mockRunner = MockProcessRunner();
    processManager = ProcessManager(
      processRunner: mockRunner,
      httpClient: MockClient(
        (request) async => http.Response('{"status":"ok"}', 200),
      ),
    );
    processManager.resetForTesting();
    processManager.startupHealthGracePeriod = Duration.zero;
    processManager.startupHealthProbeInterval = const Duration(
      milliseconds: 10,
    );
    processManager.platformOverride = null;
  });

  test('ProcessManager provides status updates', () {
    expect(processManager.statusUpdates, isA<Stream<Module>>());
  });

  test('ProcessManager can be initialized with a mock runner', () {
    final manager = ProcessManager(processRunner: mockRunner);
    expect(manager, isNotNull);
  });

  test('installModule creates venv and installs dependencies', () async {
    final tempDir = Directory.systemTemp.createTempSync('nmtk_test_install');
    final installDir = p.join(tempDir.path, 'src');
    Directory(installDir).createSync(recursive: true);

    final module = Module(
      id: 'test_module',
      name: 'Test Module',
      description: 'Description',
      directory: tempDir.path,
      sourcePath: 'src',
    );

    await processManager.installModule(module);

    // Check that venv was created
    expect(mockRunner.calls.any((c) => c.arguments.contains('venv')), isTrue);
    // Check that pip install . was called
    expect(
      mockRunner.calls.any(
        (c) => c.arguments.contains('install') && c.arguments.contains('.'),
      ),
      isTrue,
    );

    tempDir.deleteSync(recursive: true);
  });

  test('installModule includes configured pip extras', () async {
    final tempDir =
        Directory.systemTemp.createTempSync('nmtk_test_install_extras');
    final installDir = p.join(tempDir.path, 'src');
    Directory(installDir).createSync(recursive: true);

    final module = Module(
      id: 'test_module_extras',
      name: 'Test Module',
      description: 'Description',
      directory: tempDir.path,
      sourcePath: 'src',
      installExtras: const ['training', 'lava'],
    );

    await processManager.installModule(module);

    expect(
      mockRunner.calls.any(
        (c) =>
            c.arguments.contains('install') &&
            c.arguments.contains('.[training,lava]'),
      ),
      isTrue,
    );

    tempDir.deleteSync(recursive: true);
  });

  test('installModule reuses an existing .venv without recreating venv',
      () async {
    final tempDir = Directory.systemTemp.createTempSync(
      'nmtk_test_install_dotvenv',
    );
    final installDir = p.join(tempDir.path, 'src');
    final dotVenvPath = p.join(installDir, '.venv');
    Directory(dotVenvPath).createSync(recursive: true);
    final dotVenvPython = Platform.isWindows
        ? p.join(dotVenvPath, 'Scripts', 'python.exe')
        : p.join(dotVenvPath, 'bin', 'python');
    final dotVenvPip = Platform.isWindows
        ? p.join(dotVenvPath, 'Scripts', 'pip.exe')
        : p.join(dotVenvPath, 'bin', 'pip');
    File(dotVenvPython).createSync(recursive: true);
    File(dotVenvPip).createSync(recursive: true);

    final module = Module(
      id: 'test_module_dotvenv_install',
      name: 'Test Module',
      description: 'Description',
      directory: tempDir.path,
      sourcePath: 'src',
    );

    await processManager.installModule(module);

    expect(
      mockRunner.calls.any(
        (c) =>
            c.method == 'run' &&
            c.arguments.length >= 3 &&
            c.arguments[0] == '-m' &&
            c.arguments[1] == 'venv',
      ),
      isFalse,
    );
    expect(
      mockRunner.calls.any(
        (c) => c.executable == dotVenvPip && c.arguments.contains('install'),
      ),
      isTrue,
    );

    tempDir.deleteSync(recursive: true);
  });

  test(
    'prepareAkidaRuntime installs configured package set on supported hosts',
    () async {
      final tempDir = Directory.systemTemp.createTempSync(
        'nmtk_test_prepare_akida',
      );
      final installDir = tempDir.path;
      final venvPath = p.join(installDir, 'venv');
      Directory(venvPath).createSync(recursive: true);
      final pythonExe = Platform.isWindows
          ? p.join(venvPath, 'Scripts', 'python.exe')
          : p.join(venvPath, 'bin', 'python');
      final pipExe = Platform.isWindows
          ? p.join(venvPath, 'Scripts', 'pip.exe')
          : p.join(venvPath, 'bin', 'pip');
      File(pythonExe).createSync(recursive: true);
      File(pipExe).createSync(recursive: true);

      mockRunner.runResult = ProcessResult(0, 0, '3.11.8\n', '');
      processManager.platformOverride = 'linux';

      final module = Module(
        id: 'Neurochip',
        name: 'Neurochip',
        description: 'Execution, flashing, and diagnostics',
        directory: installDir,
        sourcePath: '.',
        akidaRuntime: const AkidaRuntimeConfig(
          supportedPlatforms: ['linux', 'windows'],
          pythonRange: '>=3.10,<3.13',
          requiredPackages: [
            'tensorflow==2.19.*',
            'akida==2.19.1',
            'cnn2snn==2.19.1',
            'akida-models==1.13.1',
          ],
          docsUrl: 'https://doc.brainchipinc.com/installation.html',
        ),
      );

      final updatedModule = await processManager.prepareAkidaRuntime(module);

      expect(updatedModule.akidaRuntimeState?.status, 'ready');
      expect(
        mockRunner.calls.any(
          (call) =>
              call.arguments.contains('install') &&
              call.arguments.contains('akida==2.19.1') &&
              call.arguments.contains('akida-models==1.13.1'),
        ),
        isTrue,
      );

      tempDir.deleteSync(recursive: true);
    },
  );

  test(
    'prepareAkidaRuntime reports remote host guidance for unsupported Python',
    () async {
      final tempDir = Directory.systemTemp.createTempSync(
        'nmtk_test_prepare_akida_py',
      );
      final installDir = tempDir.path;
      final venvPath = p.join(installDir, 'venv');
      Directory(venvPath).createSync(recursive: true);
      final pythonExe = Platform.isWindows
          ? p.join(venvPath, 'Scripts', 'python.exe')
          : p.join(venvPath, 'bin', 'python');
      final pipExe = Platform.isWindows
          ? p.join(venvPath, 'Scripts', 'pip.exe')
          : p.join(venvPath, 'bin', 'pip');
      File(pythonExe).createSync(recursive: true);
      File(pipExe).createSync(recursive: true);

      mockRunner.runResult = ProcessResult(0, 0, '3.9.18\n', '');
      processManager.platformOverride = 'linux';

      final module = Module(
        id: 'Neurochip',
        name: 'Neurochip',
        description: 'Execution, flashing, and diagnostics',
        directory: installDir,
        sourcePath: '.',
        akidaRuntime: const AkidaRuntimeConfig(
          supportedPlatforms: ['linux', 'windows'],
          pythonRange: '>=3.10,<3.13',
          requiredPackages: [
            'tensorflow==2.19.*',
            'akida==2.19.1',
            'cnn2snn==2.19.1',
            'akida-models==1.13.1',
          ],
          docsUrl: 'https://doc.brainchipinc.com/installation.html',
        ),
      );

      final updatedModule = await processManager.prepareAkidaRuntime(module);

      expect(updatedModule.akidaRuntimeState?.status, 'unsupported_python');
      expect(
        updatedModule.akidaRuntimeState?.message,
        contains('Linux or Windows Neurochip host'),
      );
      expect(
        mockRunner.calls.where((call) => call.arguments.contains('install')),
        isEmpty,
      );

      tempDir.deleteSync(recursive: true);
    },
  );

  test('startModule starts uvicorn and updates status', () async {
    final tempDir = Directory.systemTemp.createTempSync('nmtk_test_start');
    final runDir = tempDir.path;

    final venvPath = p.join(runDir, 'venv');
    Directory(venvPath).createSync(recursive: true);
    final pythonExe = Platform.isWindows
        ? p.join(venvPath, 'Scripts', 'python.exe')
        : p.join(venvPath, 'bin', 'python');
    File(pythonExe).createSync(recursive: true);

    final module = Module(
      id: 'test_module_start',
      name: 'Test Module',
      description: 'Description',
      directory: runDir,
      sourcePath: '.',
      runPath: '.',
      port: 8001,
      uvicornTarget: 'main:app',
    );

    final mockProcess = MockProcess();
    mockRunner.mockProcesses[pythonExe] = mockProcess;

    // Use a completer to wait for the status update
    final completer = Completer<Module>();
    final subscription = processManager.statusUpdates.listen((m) {
      if (m.id == 'test_module_start' && m.status == ModuleStatus.starting) {
        if (!completer.isCompleted) completer.complete(m);
      }
    });

    await processManager.startModule(module);

    final updatedModule = await completer.future.timeout(
      const Duration(seconds: 10),
    );
    expect(updatedModule.status, ModuleStatus.starting);

    expect(
      mockRunner.calls.any((c) => c.arguments.contains('uvicorn')),
      isTrue,
    );
    expect(mockRunner.calls.any((c) => c.arguments.contains('8001')), isTrue);

    await subscription.cancel();
    tempDir.deleteSync(recursive: true);
  });

  test('startModule uses .venv python when venv is absent', () async {
    final tempDir = Directory.systemTemp.createTempSync(
      'nmtk_test_start_dotvenv',
    );
    final runDir = tempDir.path;
    final dotVenvPath = p.join(runDir, '.venv');
    Directory(dotVenvPath).createSync(recursive: true);
    final pythonExe = Platform.isWindows
        ? p.join(dotVenvPath, 'Scripts', 'python.exe')
        : p.join(dotVenvPath, 'bin', 'python');
    File(pythonExe).createSync(recursive: true);

    final module = Module(
      id: 'test_module_start_dotvenv',
      name: 'Test Module',
      description: 'Description',
      directory: runDir,
      sourcePath: '.',
      runPath: '.',
      port: 8011,
      uvicornTarget: 'main:app',
    );

    final mockProcess = MockProcess();
    mockRunner.mockProcesses[pythonExe] = mockProcess;

    await processManager.startModule(module);

    expect(
      mockRunner.calls.any(
        (c) =>
            c.method == 'start' &&
            c.executable == pythonExe &&
            c.arguments.contains('uvicorn') &&
            c.arguments.contains('8011'),
      ),
      isTrue,
    );

    tempDir.deleteSync(recursive: true);
  });

  test('stopModule kills the process', () async {
    final tempDir = Directory.systemTemp.createTempSync('nmtk_test_stop');
    final runDir = tempDir.path;

    final venvPath = p.join(runDir, 'venv');
    Directory(venvPath).createSync(recursive: true);
    final pythonExe = Platform.isWindows
        ? p.join(venvPath, 'Scripts', 'python.exe')
        : p.join(venvPath, 'bin', 'python');
    File(pythonExe).createSync(recursive: true);

    final module = Module(
      id: 'test_module_stop',
      name: 'Test Module',
      description: 'Description',
      directory: runDir,
      port: 8002,
    );

    final mockProcess = MockProcess();
    mockRunner.mockProcesses[pythonExe] = mockProcess;

    final completer = Completer<void>();
    final subscription = processManager.statusUpdates.listen((m) {
      if (m.id == 'test_module_stop' && m.status == ModuleStatus.starting) {
        if (!completer.isCompleted) completer.complete();
      }
    });

    await processManager.startModule(module);
    await completer.future.timeout(const Duration(seconds: 5));

    // Wait a bit for startModule to proceed
    await Future<void>.delayed(const Duration(milliseconds: 100));

    await processManager.stopModule('test_module_stop');

    expect(await mockProcess.exitCode, 0);
    await subscription.cancel();

    tempDir.deleteSync(recursive: true);
  });

  test('_killProcessOnPort calls lsof and kills process', () async {
    mockRunner.runResult = ProcessResult(0, 0, '1234\n5678', '');

    // This is hard to test directly because Process.killPid is a static method
    // and cannot be easily mocked in Dart without additional libraries or
    // wrapping it. However, we can at least verify that lsof was called.

    // Since _killProcessOnPort is private, we trigger it via startModule
    final tempDir = Directory.systemTemp.createTempSync('nmtk_test_killport');
    final module = Module(
      id: 'test_kill',
      name: 'Test',
      description: 'Test',
      directory: tempDir.path,
      port: 8003,
    );

    // Mock python existence to avoid installModule call
    final venvPath = p.join(tempDir.path, 'venv');
    Directory(venvPath).createSync(recursive: true);
    final pythonExe = Platform.isWindows
        ? p.join(venvPath, 'Scripts', 'python.exe')
        : p.join(venvPath, 'bin', 'python');
    File(pythonExe).createSync(recursive: true);

    await processManager.startModule(module);

    // Verify lsof was called for the port
    expect(
      mockRunner.calls.any(
        (c) => c.executable == 'lsof' && c.arguments.contains(':8003'),
      ),
      isTrue,
    );

    tempDir.deleteSync(recursive: true);
  });

  test('installModule throws when directory missing', () async {
    final module = Module(
      id: 'missing',
      name: 'Missing',
      description: 'Missing',
      directory: '/non/existent/path',
    );

    expect(
      () => processManager.installModule(module),
      throwsA(isA<Exception>()),
    );
  });

  test('installModule updates status to error on failure', () async {
    final tempDir = Directory.systemTemp.createTempSync('nmtk_test_fail');
    final module = Module(
      id: 'fail_module',
      name: 'Fail',
      description: 'Fail',
      directory: tempDir.path,
    );

    mockRunner.runResult = ProcessResult(0, 1, '', 'pip install failed');

    // Wait for error status
    final completer = Completer<ModuleStatus>();
    processManager.statusUpdates.listen((m) {
      if (m.id == 'fail_module') {
        completer.complete(m.status);
      }
    });

    try {
      await processManager.installModule(module);
    } catch (_) {}

    final status = await completer.future.timeout(const Duration(seconds: 5));
    expect(status, ModuleStatus.error);

    tempDir.deleteSync(recursive: true);
  });

  test(
    'single transport failure followed by success does not restart module',
    () async {
      final tempDir = Directory.systemTemp.createTempSync(
        'nmtk_test_health_single',
      );
      final runDir = tempDir.path;
      final venvPath = p.join(runDir, 'venv');
      Directory(venvPath).createSync(recursive: true);
      final pythonExe = Platform.isWindows
          ? p.join(venvPath, 'Scripts', 'python.exe')
          : p.join(venvPath, 'bin', 'python');
      File(pythonExe).createSync(recursive: true);

      final module = Module(
        id: 'health_single',
        name: 'Health Single',
        description: 'Desc',
        directory: runDir,
        port: 8003,
        status: ModuleStatus.installed,
      );

      await processManager.init([module]);

      var requestCount = 0;
      processManager.httpClient = MockClient((request) async {
        requestCount++;
        if (requestCount == 1) {
          throw http.ClientException('Connection reset by peer', request.url);
        }
        return http.Response('{"status":"ok"}', 200);
      });
      mockRunner.mockProcesses[pythonExe] = MockProcess();

      await processManager.startModule(module);

      final updatedModule = processManager.moduleStateForTesting(module.id)!;
      expect(updatedModule.status, ModuleStatus.running);
      expect(processManager.consecutiveHealthFailuresFor(module.id), 0);
      expect(processManager.hasScheduledRetryFor(module.id), isFalse);

      tempDir.deleteSync(recursive: true);
    },
  );

  test('startup grace allows a slow backend to become healthy', () async {
    final tempDir = Directory.systemTemp.createTempSync(
      'nmtk_test_health_grace',
    );
    final runDir = tempDir.path;
    final venvPath = p.join(runDir, 'venv');
    Directory(venvPath).createSync(recursive: true);
    final pythonExe = Platform.isWindows
        ? p.join(venvPath, 'Scripts', 'python.exe')
        : p.join(venvPath, 'bin', 'python');
    File(pythonExe).createSync(recursive: true);

    final module = Module(
      id: 'health_grace',
      name: 'Health Grace',
      description: 'Desc',
      directory: runDir,
      port: 8009,
      status: ModuleStatus.installed,
    );

    await processManager.init([module]);
    processManager.startupHealthGracePeriod = const Duration(seconds: 1);
    processManager.startupHealthProbeInterval = const Duration(
      milliseconds: 10,
    );

    var requestCount = 0;
    processManager.httpClient = MockClient((request) async {
      requestCount++;
      if (requestCount < 3) {
        throw http.ClientException('Connection refused', request.url);
      }
      return http.Response('{"status":"ok"}', 200);
    });
    mockRunner.mockProcesses[pythonExe] = MockProcess();

    await processManager.startModule(module);

    final updatedModule = processManager.moduleStateForTesting(module.id)!;
    expect(updatedModule.status, ModuleStatus.running);
    expect(processManager.hasScheduledRetryFor(module.id), isFalse);

    tempDir.deleteSync(recursive: true);
  });

  test(
    'two consecutive failed probe cycles trigger failure handling and retry',
    () async {
      final tempDir = Directory.systemTemp.createTempSync(
        'nmtk_test_health_retry',
      );
      final runDir = tempDir.path;
      final venvPath = p.join(runDir, 'venv');
      Directory(venvPath).createSync(recursive: true);
      final pythonExe = Platform.isWindows
          ? p.join(venvPath, 'Scripts', 'python.exe')
          : p.join(venvPath, 'bin', 'python');
      File(pythonExe).createSync(recursive: true);

      final module = Module(
        id: 'health_retry',
        name: 'Health Retry',
        description: 'Desc',
        directory: runDir,
        port: 8004,
        status: ModuleStatus.installed,
      );

      await processManager.init([module]);

      processManager.httpClient = MockClient((request) async {
        throw http.ClientException('Connection reset by peer', request.url);
      });
      mockRunner.mockProcesses[pythonExe] = MockProcess();

      await processManager.startModule(module);
      expect(processManager.consecutiveHealthFailuresFor(module.id), 1);

      await processManager.checkHealthForTesting(module);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final updatedModule = processManager.moduleStateForTesting(module.id)!;
      expect(updatedModule.status, ModuleStatus.error);
      expect(updatedModule.healthStatus, contains('Retrying in'));
      expect(processManager.hasScheduledRetryFor(module.id), isTrue);
      expect(processManager.consecutiveHealthFailuresFor(module.id), 0);

      tempDir.deleteSync(recursive: true);
    },
  );

  test('successful probe resets consecutive failure counter', () async {
    final module = Module(
      id: 'health_reset',
      name: 'Health Reset',
      description: 'Desc',
      directory: Directory.systemTemp.path,
      port: 8005,
      status: ModuleStatus.installed,
    );

    await processManager.init([module]);

    processManager.httpClient = MockClient(
      (_) async => http.Response('Error', 500),
    );
    await processManager.checkHealthForTesting(module);

    final afterFailure = processManager.moduleStateForTesting(module.id)!;
    expect(afterFailure.status, ModuleStatus.degraded);
    expect(processManager.consecutiveHealthFailuresFor(module.id), 1);

    processManager.httpClient = MockClient(
      (_) async => http.Response('{"status":"ok"}', 200),
    );
    await processManager.checkHealthForTesting(module);

    final afterRecovery = processManager.moduleStateForTesting(module.id)!;
    expect(afterRecovery.status, ModuleStatus.running);
    expect(processManager.consecutiveHealthFailuresFor(module.id), 0);
  });

  test('health responses preserve 200, 404, and 503 semantics', () async {
    final scenarios = <({
      String id,
      int statusCode,
      String body,
      ModuleStatus expectedStatus,
      bool expectedHealthy,
    })>[
      (
        id: 'health_200',
        statusCode: 200,
        body: '{"status":"ok"}',
        expectedStatus: ModuleStatus.running,
        expectedHealthy: true,
      ),
      (
        id: 'health_404',
        statusCode: 404,
        body: 'Not Found',
        expectedStatus: ModuleStatus.running,
        expectedHealthy: true,
      ),
      (
        id: 'health_503',
        statusCode: 503,
        body: '{"status":"degraded"}',
        expectedStatus: ModuleStatus.degraded,
        expectedHealthy: false,
      ),
    ];

    for (final scenario in scenarios) {
      final module = Module(
        id: scenario.id,
        name: scenario.id,
        description: 'Desc',
        directory: Directory.systemTemp.path,
        port: 8100 + scenarios.indexOf(scenario),
        status: ModuleStatus.installed,
      );

      await processManager.init([module]);
      processManager.httpClient = MockClient(
        (_) async => http.Response(scenario.body, scenario.statusCode),
      );

      final healthy = await processManager.checkHealthForTesting(module);
      final updatedModule = processManager.moduleStateForTesting(module.id)!;

      expect(healthy, scenario.expectedHealthy);
      expect(updatedModule.status, scenario.expectedStatus);
      expect(processManager.consecutiveHealthFailuresFor(module.id), 0);
    }
  });

  test('Simultaneous management of 1, 3, and 7 modules', () async {
    for (int count in [1, 3, 7]) {
      mockRunner.calls.clear();
      final modules = List.generate(
        count,
        (i) => Module(
          id: 'module_${count}_$i',
          name: 'Module $i',
          description: 'Description $i',
          directory: Directory.systemTemp
              .createTempSync('sim_module_${count}_$i')
              .path,
          port: 8100 + (count * 10) + i,
          status: ModuleStatus.installed,
        ),
      );

      for (var m in modules) {
        final pythonExe = Platform.isWindows
            ? p.join(m.directory, 'venv', 'Scripts', 'python.exe')
            : p.join(m.directory, 'venv', 'bin', 'python');
        Directory(p.dirname(pythonExe)).createSync(recursive: true);
        File(pythonExe).createSync();
        mockRunner.mockProcesses[pythonExe] = MockProcess();
      }

      await processManager.init(modules);

      // Start all
      final futures =
          modules.map((m) => processManager.startModule(m)).toList();
      await Future.wait(futures);

      // Stop all
      final stopFutures =
          modules.map((m) => processManager.stopModule(m.id)).toList();
      await Future.wait(stopFutures);

      // Verify all started
      expect(mockRunner.calls.where((c) => c.method == 'start').length, count);

      for (var m in modules) {
        Directory(m.directory).deleteSync(recursive: true);
      }
    }
  });
}
