// ignore_for_file: unawaited_futures
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_toolkit/models/module.dart';
import 'package:neuro_toolkit/services/process_manager.dart';
import 'package:path/path.dart' as p;

class MockProcess implements Process {
  final StreamController<List<int>> _stdoutController =
      StreamController<List<int>>();
  final StreamController<List<int>> _stderrController =
      StreamController<List<int>>();
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
    return mockProcesses[executable] ?? MockProcess();
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
    processManager = ProcessManager(processRunner: mockRunner);
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
        await completer.future.timeout(const Duration(seconds: 5));
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

    await processManager.stopModule('test_module_stop');

    await startFuture;
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
}
