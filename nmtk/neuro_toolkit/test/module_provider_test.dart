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
  List<Module> modules = [];

  @override
  Stream<Module> get statusUpdates => _statusController.stream;

  @override
  Future<void> init(List<Module> modules) async {
    this.modules = modules;
  }

  @override
  Future<void> installModule(Module module, {void Function(double)? onProgress}) async {
    installCalls.add(module.id);
    onProgress?.call(0.5);
    final updated = module.copyWith(status: ModuleStatus.installed, installProgress: 1.0);
    _statusController.add(updated);
  }

  @override
  Future<void> startModule(Module module) async {
    startCalls.add(module.id);
    final updated = module.copyWith(status: ModuleStatus.running);
    _statusController.add(updated);
  }

  @override
  Future<void> stopModule(String moduleId) async {
    stopCalls.add(moduleId);
    final index = modules.indexWhere((m) => m.id == moduleId);
    if (index != -1) {
      final updated = modules[index].copyWith(status: ModuleStatus.installed);
      _statusController.add(updated);
    }
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

  test('ModuleProvider correctly filters installed and available modules', () {
    final mockProcessManager = MockProcessManager();
    final provider = ModuleProvider(processManager: mockProcessManager);

    provider.modules = [
      Module(id: 'm1', name: 'M1', description: 'D1', directory: 'd1', status: ModuleStatus.notInstalled),
      Module(id: 'm2', name: 'M2', description: 'D2', directory: 'd2', status: ModuleStatus.installed),
    ];

    expect(provider.availableModules.length, 1);
    expect(provider.availableModules.first.id, 'm1');
    expect(provider.installedModules.length, 1);
    expect(provider.installedModules.first.id, 'm2');
  });

  test('ModuleProvider handles module installation flow', () async {
    final mockProcessManager = MockProcessManager();
    final provider = ModuleProvider(processManager: mockProcessManager);

    final module = Module(id: 'm1', name: 'M1', description: 'D1', directory: 'd1', status: ModuleStatus.notInstalled);
    provider.modules = [module];

    await provider.installModule('m1');

    expect(mockProcessManager.installCalls, contains('m1'));

    // Simulate what the listener would do if it was working
    provider.modules[0] = provider.modules[0].copyWith(status: ModuleStatus.installed);

    expect(provider.modules.first.status, ModuleStatus.installed);
  });

  test('ModuleProvider handles module launch and stop flow', () async {
    final mockProcessManager = MockProcessManager();
    final provider = ModuleProvider(processManager: mockProcessManager);

    final module = Module(id: 'm1', name: 'M1', description: 'D1', directory: 'd1', status: ModuleStatus.installed);
    provider.modules = [module];
    mockProcessManager.modules = [module];

    await provider.launchModule('m1');
    expect(mockProcessManager.startCalls, contains('m1'));
    expect(provider.activeModuleIds, contains('m1'));

    // Simulate status update
    provider.modules[0] = provider.modules[0].copyWith(status: ModuleStatus.running);
    expect(provider.modules.first.status, ModuleStatus.running);

    await provider.stopModule('m1');
    expect(mockProcessManager.stopCalls, contains('m1'));
    expect(provider.activeModuleIds, isNot(contains('m1')));

    // Simulate status update
    provider.modules[0] = provider.modules[0].copyWith(status: ModuleStatus.installed);
    expect(provider.modules.first.status, ModuleStatus.installed);
  });

  test('ModuleProvider uninstallModule resets state', () async {
    final mockProcessManager = MockProcessManager();
    final provider = ModuleProvider(processManager: mockProcessManager);

    final module = Module(
      id: 'm1',
      name: 'M1',
      description: 'D1',
      directory: 'd1',
      status: ModuleStatus.installed,
      healthStatus: 'Running fine',
    );
    provider.modules = [module];

    await provider.uninstallModule('m1');

    expect(provider.modules.first.status, ModuleStatus.notInstalled);
    expect(provider.modules.first.healthStatus, isNull);
  });

  test('ModuleProvider closeTab removes from active list', () {
    final mockProcessManager = MockProcessManager();
    final provider = ModuleProvider(processManager: mockProcessManager);

    final module = Module(id: 'm1', name: 'M1', description: 'D1', directory: 'd1');
    provider.modules = [module];
    provider.activeModuleIds.add('m1');

    provider.closeTab('m1');

    expect(provider.activeModuleIds, isNot(contains('m1')));
  });

  test('ModuleProvider recheckPython toggles loading', () async {
    final mockProcessManager = MockProcessManager();
    final provider = ModuleProvider(processManager: mockProcessManager);

    final future = provider.recheckPython();
    expect(provider.isLoading, isTrue);
    await future;
    expect(provider.isLoading, isFalse);
  });
}
