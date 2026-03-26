import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:neuro_toolkit/main.dart';
import 'package:neuro_toolkit/models/module.dart';
import 'package:neuro_toolkit/providers/module_provider.dart';
import 'package:neuro_toolkit/screens/tool_view.dart';
import 'package:neuro_toolkit/services/process_manager.dart';
import 'package:provider/provider.dart';
import 'package:path/path.dart' as p;

class MockProcess implements Process {
  final StreamController<List<int>> _stdoutController = StreamController<List<int>>.broadcast();
  final StreamController<List<int>> _stderrController = StreamController<List<int>>.broadcast();
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
    if (!_exitCodeCompleter.isCompleted) _exitCodeCompleter.complete(0);
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FastMockProcessRunner implements ProcessRunner {
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
    return MockProcess();
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
    // Simulate venv creation if needed
    if (arguments.contains('venv')) {
      final venvPath = p.join(workingDirectory!, 'venv');
      Directory(venvPath).createSync(recursive: true);
      final pythonBin = Platform.isWindows
          ? p.join(venvPath, 'Scripts', 'python.exe')
          : p.join(venvPath, 'bin', 'python');
      File(pythonBin).createSync(recursive: true);
    }
    return ProcessResult(0, 0, 'success', '');
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // Mock path_provider
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (MethodCall methodCall) async {
      return '.';
    },
  );

  testWidgets('End-to-end integration test (Dashboard to ToolView)', (WidgetTester tester) async {
    // Use real ModuleProvider but mocked ProcessRunner for speed/reliability in CI
    final mockRunner = FastMockProcessRunner();
    final processManager = ProcessManager(processRunner: mockRunner);
    final moduleProvider = ModuleProvider(processManager: processManager);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ModuleProvider>.value(value: moduleProvider),
        ],
        child: const NeuroToolkitApp(),
      ),
    );

    // Wait for initialization
    await tester.pumpAndSettle();

    // 1. Verify we are on Dashboard and see modules from assets/modules.json
    expect(find.text('CNL Studio'), findsWidgets);

    // 2. Install a module (neurocnl)
    final installButton = find.descendant(
      of: find.ancestor(of: find.text('CNL Studio'), matching: find.byType(Card)),
      matching: find.text('INSTALL'),
    );
    expect(installButton, findsOneWidget);
    await tester.tap(installButton);
    await tester.pumpAndSettle(const Duration(seconds: 1));

    // 3. Start module
    final startButton = find.descendant(
      of: find.ancestor(of: find.text('CNL Studio'), matching: find.byType(Card)),
      matching: find.text('START'),
    );
    expect(startButton, findsOneWidget);
    await tester.tap(startButton);

    // ModuleProvider.launchModule adds it to active tabs.
    // Dashboard might auto-navigate or we might need to click OPEN.
    // Current DashboardScreen logic usually navigates on start if successful.
    await tester.pumpAndSettle();

    // 4. Verify we navigated to ToolViewScreen
    expect(find.byType(ToolViewScreen), findsOneWidget);
    expect(find.textContaining('CNL Studio'), findsWidgets);

    // 5. Close tab and go back to dashboard
    final closeButton = find.byIcon(Icons.close);
    expect(closeButton, findsWidgets);
    await tester.tap(closeButton.first);
    await tester.pumpAndSettle();

    expect(find.byType(ToolViewScreen), findsNothing);
    expect(find.text('CNL Studio'), findsWidgets);
  });
}
