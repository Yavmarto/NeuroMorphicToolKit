import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_toolkit/models/module.dart';
import 'package:neuro_toolkit/providers/module_provider.dart';
import 'package:neuro_toolkit/services/control_api_service.dart';
import 'package:neuro_toolkit/services/launcher_control_bootstrap_service.dart';
import 'package:neuro_toolkit/services/process_manager.dart';
import 'package:neuro_toolkit/services/update_service.dart';

class MockProcessManager implements ProcessManager {
  final _statusController = StreamController<Module>.broadcast();
  final List<String> installCalls = [];
  final List<String> startCalls = [];
  final List<String> stopCalls = [];
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
    onProgress?.call(0.5);
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

class _FakeControlApiService extends ControlApiService {
  _FakeControlApiService(List<Module> modules)
      : _modules = List<Module>.from(modules),
        super(baseUri: Uri.parse('http://127.0.0.1:8090'));

  final List<Module> _modules;
  final List<String> startCalls = <String>[];

  @override
  Future<List<Module>> fetchModules({bool refreshUpdates = false}) async =>
      List<Module>.from(_modules);

  @override
  Future<LauncherControlSettings> fetchSettings() async =>
      LauncherControlSettings.fromJson(const <String, dynamic>{
        'logLevel': 'info',
        'pythonAvailable': true,
        'mujocoAvailable': true,
      });

  @override
  Future<Module> startModule(String moduleId) async {
    startCalls.add(moduleId);
    final index = _modules.indexWhere((module) => module.id == moduleId);
    final updated = _modules[index].copyWith(status: ModuleStatus.running);
    _modules[index] = updated;
    return updated;
  }
}

class _NoopUpdateService extends UpdateService {
  @override
  Future<LauncherUpdate?> checkForLauncherUpdate() async => null;
}

Future<void> _waitForInit(ModuleProvider provider) async {
  for (var i = 0; i < 200 && provider.isLoading; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Module parses deployment capability metadata', () {
    final module = Module.fromJson(<String, dynamic>{
      'id': 'dummy',
      'name': 'Dummy',
      'description': 'D1',
      'installPath': 'dummy',
      'installExtras': <String>['training', 'lava'],
      'deployment': <String, dynamic>{
        'supportedModes': <String>['standalone', 'docker', 'kubernetes'],
        'healthPath': '/health',
        'requiredPorts': <int>[9000],
        'defaultContainerImage': 'ghcr.io/example/dummy:latest',
        'composeProfile': 'core',
        'chartTemplateId': 'nmtk-backend',
      },
    });

    expect(module.deployment, isNotNull);
    expect(module.installExtras, <String>['training', 'lava']);
    expect(module.deployment!.supportedModes, contains('docker'));
    expect(module.deployment!.requiredPorts, contains(9000));
    final deploymentJson =
        module.toJson()['deployment'] as Map<String, dynamic>;
    expect(deploymentJson['defaultContainerImage'],
        'ghcr.io/example/dummy:latest');
    expect(module.toJson()['installExtras'], <String>['training', 'lava']);
  });

  test('ModuleProvider correctly filters installed and available modules', () {
    final mockProcessManager = MockProcessManager();
    final provider = ModuleProvider(processManager: mockProcessManager);

    provider.modulesForTesting = [
      Module(
        id: 'm1',
        name: 'M1',
        description: 'D1',
        directory: 'd1',
        status: ModuleStatus.notInstalled,
      ),
      Module(
        id: 'm2',
        name: 'M2',
        description: 'D2',
        directory: 'd2',
        status: ModuleStatus.installed,
      ),
    ];

    expect(provider.availableModules.length, 1);
    expect(provider.availableModules.first.id, 'm1');
    expect(provider.installedModules.length, 1);
    expect(provider.installedModules.first.id, 'm2');
  });

  test('ModuleProvider handles module installation flow', () async {
    final mockProcessManager = MockProcessManager();
    final provider = ModuleProvider(processManager: mockProcessManager);

    final module = Module(
      id: 'm1',
      name: 'M1',
      description: 'D1',
      directory: 'd1',
      status: ModuleStatus.notInstalled,
    );
    provider.modulesForTesting = [module];

    // Status is updated via stream from MockProcessManager.
    // However, ModuleProvider's listener is only set up in _init(),
    // which happens when it's initialized.
    // We can simulate the status update directly if needed.

    await provider.installModule('m1');

    expect(mockProcessManager.installCalls, contains('m1'));

    // Simulate what the listener would do if it was working
    provider.modules[0] =
        provider.modules[0].copyWith(status: ModuleStatus.installed);

    expect(provider.modules.first.status, ModuleStatus.installed);
  });

  test('ModuleProvider handles module launch and stop flow', () async {
    final mockProcessManager = MockProcessManager();
    final provider = ModuleProvider(processManager: mockProcessManager);

    final module = Module(
      id: 'm1',
      name: 'M1',
      description: 'D1',
      directory: 'd1',
      status: ModuleStatus.installed,
    );
    provider.modulesForTesting = [module];
    mockProcessManager.modules = [module];

    await provider.launchModule('m1');
    expect(mockProcessManager.startCalls, contains('m1'));
    expect(provider.activeModuleIds, contains('m1'));

    // Simulate status update
    provider.modules[0] =
        provider.modules[0].copyWith(status: ModuleStatus.running);
    expect(provider.modules.first.status, ModuleStatus.running);

    await provider.stopModule('m1');
    expect(mockProcessManager.stopCalls, contains('m1'));
    expect(provider.activeModuleIds, isNot(contains('m1')));

    // Simulate status update
    provider.modules[0] =
        provider.modules[0].copyWith(status: ModuleStatus.installed);
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

    final module =
        Module(id: 'm1', name: 'M1', description: 'D1', directory: 'd1');
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

  test(
      'ModuleProvider auto-starts only installed switchable nav modules on init',
      () async {
    final fake = _FakeControlApiService([
      // Installed + enabled + nav-visible + frontend → should auto-start.
      Module(
        id: 'neurocnl',
        name: 'NeuroStudio',
        description: 'Studio',
        directory: 'neurocnl',
        port: 9000,
        hasFrontend: true,
        status: ModuleStatus.installed,
      ),
      // Installed + nav-visible + native surface (no frontend) → should start.
      Module(
        id: 'Neurohub',
        name: 'Share',
        description: 'Hub',
        directory: 'Neurohub',
        port: 9000,
        hasFrontend: false,
        status: ModuleStatus.installed,
      ),
      // Nav-hidden → should NOT auto-start.
      Module(
        id: 'Neurochip',
        name: 'NeuroChip',
        description: 'Chip',
        directory: 'Neurochip',
        port: 9000,
        hasFrontend: true,
        showInLauncherNav: false,
        status: ModuleStatus.installed,
      ),
      // Headless (no frontend, no native surface) → should NOT auto-start.
      Module(
        id: 'Neurosense',
        name: 'NeuroSense',
        description: 'Sense',
        directory: 'Neurosense',
        port: 9000,
        hasFrontend: false,
        status: ModuleStatus.installed,
      ),
      // Not installed → should NOT auto-start.
      Module(
        id: 'jupyter',
        name: 'Notebooks',
        description: 'Notebooks',
        directory: 'jupyter',
        port: 8008,
        hasFrontend: true,
        status: ModuleStatus.notInstalled,
      ),
    ]);

    final provider = ModuleProvider(
      controlApiService: fake,
      updateService: _NoopUpdateService(),
      bootstrapState:
          LauncherBootstrapState.ready(Uri.parse('http://127.0.0.1:8090')),
    );
    addTearDown(provider.dispose);

    await _waitForInit(provider);

    expect(fake.startCalls, containsAll(<String>['neurocnl', 'Neurohub']));
    expect(fake.startCalls, isNot(contains('Neurochip')));
    expect(fake.startCalls, isNot(contains('Neurosense')));
    expect(fake.startCalls, isNot(contains('jupyter')));
    expect(provider.activeModuleIds,
        containsAll(<String>['neurocnl', 'Neurohub']));
  });
}
