import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_toolkit/models/module.dart';
import 'package:neuro_toolkit/providers/module_provider.dart';
import 'package:neuro_toolkit/screens/tool_view.dart';
import 'package:neuro_toolkit/services/process_manager.dart';
import 'package:provider/provider.dart';

class _NoopProcessManager implements ProcessManager {
  final _statusController = StreamController<Module>.broadcast();

  @override
  Stream<Module> get statusUpdates => _statusController.stream;

  @override
  Future<void> init(List<Module> modules, [dynamic logLevel]) async {}

  @override
  Future<void> installModule(
    Module module, {
    void Function(double progress)? onProgress,
  }) async {}

  @override
  Future<void> startModule(Module module, {bool isRetry = false}) async {}

  @override
  Future<void> stopModule(String moduleId, {bool isFailure = false}) async {}

  @override
  void dispose() {
    _statusController.close();
  }

  @override
  Stream<String>? getOutput(String moduleId) => null;

  @override
  Future<void> saveModuleState(Module module) async {}

  @override
  set processRunner(ProcessRunner runner) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('ToolView shows launcher preflight error instead of polling',
      (WidgetTester tester) async {
    final provider = ModuleProvider(processManager: _NoopProcessManager());
    provider.modules = [
      Module(
        id: 'neurobench',
        name: 'NeuroBench',
        description: 'Benchmarking',
        directory: 'Neurobench',
        port: 8003,
        status: ModuleStatus.error,
        preflightStatus: 'failed',
        preflightMessage:
            'Missing required dependency: fastapi (needed by app.main)',
      ),
    ];
    provider.activeModuleIds.add('neurobench');

    await tester.pumpWidget(
      MaterialApp(
        home: ChangeNotifierProvider<ModuleProvider>.value(
          value: provider,
          child: const ToolViewScreen(initialModuleId: 'neurobench'),
        ),
      ),
    );
    await tester.pump();

    expect(
      find.text('Missing required dependency: fastapi (needed by app.main)'),
      findsOneWidget,
    );
    expect(find.text('Retry Start'), findsOneWidget);
    expect(find.textContaining('Checking http'), findsNothing);
  });
}
