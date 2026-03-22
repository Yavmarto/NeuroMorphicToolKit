import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_toolkit/models/module.dart';
import 'package:neuro_toolkit/providers/module_provider.dart';
import 'package:neuro_toolkit/services/process_manager.dart';

class MockProcessManager implements ProcessManager {
  final _statusController = StreamController<Module>.broadcast();
  final List<String> installCalls = [];
  final List<String> startCalls = [];
  final List<String> stopCalls = [];

  @override
  Stream<Module> get statusUpdates => _statusController.stream;

  @override
  Future<void> init(List<Module> modules) async {}

  @override
  Future<void> installModule(Module module, {Function(double)? onProgress}) async {
    installCalls.add(module.id);
  }

  @override
  Future<void> startModule(Module module) async {
    startCalls.add(module.id);
  }

  @override
  Future<void> stopModule(String moduleId) async {
    stopCalls.add(moduleId);
  }

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
  test('ModuleProvider can be initialized with a MockProcessManager', () async {
    final mockProcessManager = MockProcessManager();
    final provider = ModuleProvider(processManager: mockProcessManager);
    expect(provider, isNotNull);
  });
}
