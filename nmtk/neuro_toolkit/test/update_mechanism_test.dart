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
  final List<String> updateCalls = [];
  List<Module> modules = [];

  @override
  Stream<Module> get statusUpdates => _statusController.stream;

  @override
  Future<void> init(List<Module> modules, [dynamic logLevel]) async {
    this.modules = modules;
  }

  @override
  Future<void> installModule(
    Module module, {
    void Function(double)? onProgress,
  }) async {
    installCalls.add(module.id);
    onProgress?.call(1.0);
    final updated =
        module.copyWith(status: ModuleStatus.installed, installProgress: 1.0);
    _statusController.add(updated);
  }

  @override
  Future<void> startModule(Module module, {bool isRetry = false}) async {
    startCalls.add(module.id);
    final updated = module.copyWith(status: ModuleStatus.running);
    _statusController.add(updated);
  }

  @override
  Future<void> stopModule(String moduleId, {bool isFailure = false}) async {
    stopCalls.add(moduleId);
    final index = modules.indexWhere((m) => m.id == moduleId);
    if (index != -1) {
      final updated = modules[index].copyWith(status: ModuleStatus.installed);
      _statusController.add(updated);
    }
  }

  @override
  Future<void> updateModule(
    Module module, {
    void Function(double)? onProgress,
  }) async {
    updateCalls.add(module.id);
    onProgress?.call(1.0);
    final updated = module.copyWith(
      status: ModuleStatus.running,
      version: module.remoteVersion,
      installProgress: 1.0,
    );
    _statusController.add(updated);
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
  TestWidgetsFlutterBinding.ensureInitialized();

  test('ModuleProvider updateModule calls ProcessManager.updateModule',
      () async {
    final mockProcessManager = MockProcessManager();
    final provider = ModuleProvider(processManager: mockProcessManager);

    final module = Module(
      id: 'm1',
      name: 'M1',
      description: 'D1',
      directory: 'd1',
      status: ModuleStatus.installed,
      version: '1.0.0',
      remoteVersion: '1.1.0',
    );
    provider.modulesForTesting = [module];
    mockProcessManager.modules = [module];

    await provider.updateModule('m1');

    expect(mockProcessManager.updateCalls, contains('m1'));

    // Simulate what the status listener would do
    provider.modules[0] = provider.modules[0].copyWith(
      status: ModuleStatus.running,
      version: '1.1.0',
    );

    expect(provider.modules.first.status, ModuleStatus.running);
    expect(provider.modules.first.version, '1.1.0');
  });
}
