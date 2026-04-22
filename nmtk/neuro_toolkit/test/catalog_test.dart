import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_toolkit/models/module.dart';
import 'package:neuro_toolkit/providers/module_provider.dart';
import 'package:neuro_toolkit/providers/riverpod_providers.dart';
import 'package:neuro_toolkit/services/update_service.dart';
import 'package:neuro_toolkit/screens/catalog.dart';

class MockModuleProvider extends ChangeNotifier implements ModuleProvider {
  final List<Module> _mockModules = [];
  bool _isMuJoCoAvailableValue = false;
  final List<String> installCalls = [];

  void setMuJoCoAvailable(bool value) {
    _isMuJoCoAvailableValue = value;
    notifyListeners();
  }

  @override
  List<Module> modulesForTesting = [];

  @override
  List<Module> get modules => _mockModules;

  @override
  set modules(List<Module> val) {
    _mockModules.clear();
    _mockModules.addAll(val);
    notifyListeners();
  }

  @override
  bool get isLoading => false;

  @override
  bool get pythonAvailable => true;

  @override
  String? get error => null;

  @override
  Future<void> recheckPython() async {}

  @override
  List<Module> get installedModules => _mockModules
      .where(
        (Module m) =>
            m.status != ModuleStatus.notInstalled &&
            m.status != ModuleStatus.installing,
      )
      .toList();

  @override
  List<Module> get availableModules => _mockModules
      .where(
        (Module m) =>
            m.status == ModuleStatus.notInstalled ||
            m.status == ModuleStatus.installing,
      )
      .toList();

  @override
  List<String> get activeModuleIds => [];

  @override
  List<Module> get activeModules => [];

  @override
  bool isMuJoCoAvailable() => _isMuJoCoAvailableValue;

  @override
  Future<void> installModule(String moduleId) async {
    installCalls.add(moduleId);
    final index = _mockModules.indexWhere((m) => m.id == moduleId);
    if (index != -1) {
      _mockModules[index] =
          _mockModules[index].copyWith(status: ModuleStatus.installing);
      notifyListeners();
    }
  }

  @override
  Future<void> launchModule(String moduleId) async {}

  @override
  Future<void> stopModule(String moduleId) async {}

  @override
  Future<void> uninstallModule(String moduleId) async {}

  @override
  Future<void> updateModule(String moduleId) async {}

  @override
  Future<void> updateModuleSettings(String moduleId,
      {bool? isEnabled, int? customPort}) async {}

  @override
  void updateSettingsProvider(settingsProvider) {}

  @override
  Future<void> checkForUpdates() async {}

  @override
  void closeTab(String moduleId) {}

  @override
  void dismissLauncherUpdate() {}

  @override
  void setUpdateChannel(UpdateChannel channel) {}

  @override
  Future<void> setVersionPinned(String moduleId, bool pinned) async {}

  @override
  Stream<String>? getModuleOutput(String moduleId) => null;

  @override
  LauncherUpdate? get pendingLauncherUpdate => null;

  @override
  UpdateChannel get currentChannel => UpdateChannel.stable;

  void loadModules() {
    final List<Map<String, dynamic>> mockData = [
      {
        'id': 'neurocnl',
        'name': 'CNL Studio',
        'description': 'CNL parser',
        'icon': 'code',
        'port': 8000,
        'installPath': 'neurocnl/',
        'hasFrontend': true,
        'frontendStatus': 'Yes',
        'requiresMuJoCo': false,
      },
      {
        'id': 'Neurosim',
        'name': 'NeuroSim',
        'description': 'Visual design',
        'icon': 'architecture',
        'port': 8001,
        'installPath': 'Neurosim/',
        'hasFrontend': true,
        'frontendStatus': 'Minimal',
        'requiresMuJoCo': false,
      },
      {
        'id': 'Neurochip',
        'name': 'NeuroChip',
        'description': 'Hardware',
        'icon': 'memory',
        'port': 8002,
        'installPath': 'Neurochip/',
        'hasFrontend': true,
        'frontendStatus': 'Partial',
        'requiresMuJoCo': false,
      },
      {
        'id': 'Neurobench',
        'name': 'NeuroBench',
        'description': 'Benchmarking',
        'icon': 'speed',
        'port': 8003,
        'installPath': 'Neurobench/',
        'hasFrontend': true,
        'frontendStatus': 'Scaffold',
        'requiresMuJoCo': false,
      },
      {
        'id': 'Neurosense',
        'name': 'NeuroSense',
        'description': 'Biosignal',
        'icon': 'sensors',
        'port': 8004,
        'installPath': 'Neurosense/',
        'hasFrontend': true,
        'frontendStatus': 'Partial',
        'requiresMuJoCo': false,
      },
      {
        'id': 'Neurohub',
        'name': 'NeuroHub',
        'description': 'Dashboard',
        'icon': 'hub',
        'port': 8005,
        'installPath': 'Neurohub/',
        'hasFrontend': true,
        'frontendStatus': 'Scaffold',
        'requiresMuJoCo': false,
      },
      {
        'id': 'neuro_dream_hand',
        'name': 'NDH Simulator',
        'description': 'Physics',
        'icon': 'precision_manufacturing',
        'port': null,
        'installPath': 'Neuro-Dream-Hand/',
        'hasFrontend': false,
        'frontendStatus': 'No',
        'requiresMuJoCo': true,
      },
    ];

    _mockModules.clear();
    _mockModules.addAll(
      mockData.map((Map<String, dynamic> json) => Module.fromJson(json)),
    );
    notifyListeners();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Module.fromJson parses Akida runtime metadata', () {
    final module = Module.fromJson({
      'id': 'Neurochip',
      'name': 'NeuroChip',
      'description': 'Hardware deployment',
      'installPath': 'Neurochip/',
      'akidaRuntime': {
        'supportedPlatforms': ['linux', 'windows'],
        'pythonRange': '>=3.10,<3.13',
        'requiredPackages': ['akida==2.19.1'],
        'docsUrl': 'https://doc.brainchipinc.com/installation.html',
        'localModeFallback': 'simulator_only',
      },
      'akidaRuntimeState': {
        'status': 'ready',
        'message': 'Prepared',
        'preparedAt': '2026-04-22T10:00:00Z',
      },
    });

    expect(module.akidaRuntime, isNotNull);
    expect(module.akidaRuntime!.supportedPlatforms, ['linux', 'windows']);
    expect(module.akidaRuntimeState?.status, 'ready');
  });

  testWidgets('CatalogScreen shows all 7 modules', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1920, 2000);
    tester.view.devicePixelRatio = 1.0;

    final provider = MockModuleProvider();
    provider.loadModules();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          moduleStateProvider.overrideWith((ref) => provider),
        ],
        child: const MaterialApp(
          home: CatalogScreen(),
        ),
      ),
    );

    await tester.pump();

    expect(find.text('CNL Studio'), findsOneWidget);
    expect(find.text('NeuroSim'), findsOneWidget);
    expect(find.text('NeuroChip'), findsOneWidget);
    expect(find.text('NeuroBench'), findsOneWidget);
    expect(find.text('NeuroSense'), findsOneWidget);
    expect(find.text('NeuroHub'), findsOneWidget);
    expect(find.text('NDH Simulator'), findsOneWidget);

    addTearDown(tester.view.resetPhysicalSize);
  });

  testWidgets('CatalogScreen handles Install button click',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;

    final provider = MockModuleProvider();
    provider.loadModules();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          moduleStateProvider.overrideWith((ref) => provider),
        ],
        child: const MaterialApp(
          home: CatalogScreen(),
        ),
      ),
    );

    await tester.pump();

    // Find the Install button for CNL Studio
    final installButton = find.descendant(
      of: find.ancestor(
          of: find.text('CNL Studio'), matching: find.byType(Card)),
      matching: find.text('Install'),
    );

    expect(installButton, findsOneWidget);
    await tester.tap(installButton);
    await tester.pump();

    expect(provider.installCalls, contains('neurocnl'));
    expect(find.text('Installing'), findsOneWidget);

    addTearDown(tester.view.resetPhysicalSize);
  });
}
