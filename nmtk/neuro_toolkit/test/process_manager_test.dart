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
      _exitCodeCompleter.complete(signal == ProcessSignal.sigterm ? 0 : -1);
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

    // Special case for lsof to avoid hanging if ProcessManager calls it
    if (executable == 'lsof') {
      return ProcessResult(0, 1, '', ''); // Return 1 to indicate no process found
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

    unawaited(processManager.startModule(module));

    final updatedModule =
        await completer.future.timeout(const Duration(seconds: 10));
    expect(updatedModule.status, ModuleStatus.starting);

    expect(mockRunner.calls.any((c) => c.arguments.contains('uvicorn')), isTrue);
    expect(mockRunner.calls.any((c) => c.arguments.contains('8001')), isTrue);

    subscription.cancel();
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

    unawaited(processManager.startModule(module));

    // Wait a bit for startModule to proceed
    await Future<void>.delayed(const Duration(milliseconds: 100));

    await processManager.stopModule('test_module_stop');

    expect(await mockProcess.exitCode, 0);

    tempDir.deleteSync(recursive: true);
  });
}
