// ignore_for_file: unawaited_futures
import 'dart:async';
import 'dart:convert';
import 'dart:io';
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
          0, 1, '', ''); // Return 1 to indicate no process found
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
  TestWidgetsFlutterBinding.ensureInitialized();

  late ProcessManager processManager;
  late MockProcessRunner mockRunner;

  setUp(() {
    mockRunner = MockProcessRunner();
    processManager = ProcessManager(
      processRunner: mockRunner,
      httpClient:
          MockClient((request) async => http.Response('{"status":"ok"}', 200)),
    );
    processManager.dispose(); // Reset state
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

    final updatedModule =
        await completer.future.timeout(const Duration(seconds: 10));
    expect(updatedModule.status, ModuleStatus.starting);

    expect(
      mockRunner.calls.any((c) => c.arguments.contains('uvicorn')),
      isTrue,
    );
    expect(mockRunner.calls.any((c) => c.arguments.contains('8001')), isTrue);

    await subscription.cancel();
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

  test('Health check updates module status and handles retries', () async {
    final tempDir = Directory.systemTemp.createTempSync('nmtk_test_health');
    final runDir = tempDir.path;

    // Setup venv and python mock
    final venvPath = p.join(runDir, 'venv');
    Directory(venvPath).createSync(recursive: true);
    final pythonExe = Platform.isWindows
        ? p.join(venvPath, 'Scripts', 'python.exe')
        : p.join(venvPath, 'bin', 'python');
    File(pythonExe).createSync(recursive: true);

    final module = Module(
      id: 'health_test',
      name: 'Health Test',
      description: 'Desc',
      directory: runDir,
      port: 8003,
      status: ModuleStatus.installed,
    );

    await processManager.init([module]);

    int requestCount = 0;
    final mockClient = MockClient((request) async {
      requestCount++;
      if (requestCount == 1) {
        return http.Response('{"status":"ok"}', 200);
      } else if (requestCount == 2) {
        return http.Response('{"status":"degraded"}', 503);
      } else {
        return http.Response('Error', 500);
      }
    });

    processManager.httpClient = mockClient;
    mockRunner.mockProcesses[pythonExe] = MockProcess();
    // For retry
    mockRunner.mockProcesses[pythonExe] = MockProcess();

    // Capture status updates
    final statusList = <ModuleStatus>[];
    final subscription = processManager.statusUpdates.listen((m) {
      if (m.id == 'health_test') {
        statusList.add(m.status);
      }
    });

    await processManager.startModule(module);

    // Give it time for startModule's initial health check and two polling intervals (5s each)
    await Future<void>.delayed(const Duration(seconds: 13));

    expect(statusList, contains(ModuleStatus.running));
    expect(statusList, contains(ModuleStatus.degraded));
    expect(statusList, contains(ModuleStatus.error));

    await subscription.cancel();
    tempDir.deleteSync(recursive: true);
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
