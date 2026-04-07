import 'package:flutter/material.dart';
import 'package:neuro_toolkit/services/update_service.dart';
import 'package:neuro_toolkit/providers/settings_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_toolkit/models/module.dart';
import 'package:neuro_toolkit/providers/module_provider.dart';
import 'package:neuro_toolkit/screens/dashboard.dart';
import 'package:provider/provider.dart';

class MockDashboardProvider extends ChangeNotifier implements ModuleProvider {
  final List<Module> _mockInstalledModules = [];
  final List<String> launchCalls = [];
  final List<String> stopCalls = [];
  final List<String> uninstallCalls = [];

  @override
  List<Module> get installedModules => _mockInstalledModules;

  @override
  List<Module> get modules => _mockInstalledModules;
  @override
  set modules(List<Module> val) {
    _mockInstalledModules.clear();
    _mockInstalledModules.addAll(val);
    notifyListeners();
  }

  @override
  List<Module> modulesForTesting = [];
  @override
  bool get isLoading => false;
  @override
  bool get pythonAvailable => true;
  @override
  String? get error => null;
  @override
  List<String> get activeModuleIds => [];
  @override
  List<Module> get activeModules => [];
  @override
  List<Module> get availableModules => [];
  @override
  Future<void> recheckPython() async {}
  @override
  bool isMuJoCoAvailable() => false;
  @override
  Future<void> installModule(String moduleId) async {}
  @override
  void closeTab(String moduleId) {}

  @override
  void setUpdateChannel(UpdateChannel channel) {}

  @override
  Future<void> setVersionPinned(String moduleId, bool pinned) async {}

  @override
  void dismissLauncherUpdate() {}

  @override
  LauncherUpdate? get pendingLauncherUpdate => null;

  @override
  UpdateChannel get currentChannel => UpdateChannel.stable;
  @override
  Stream<String>? getModuleOutput(String moduleId) => null;

  @override
  Future<void> launchModule(String moduleId) async {
    launchCalls.add(moduleId);
  }

  @override
  Future<void> stopModule(String moduleId) async {
    stopCalls.add(moduleId);
  }

  @override
  Future<void> uninstallModule(String moduleId) async {
    uninstallCalls.add(moduleId);
  }

  @override
  Future<void> updateModule(String moduleId) async {}

  @override
  Future<void> updateModuleSettings(String moduleId,
      {bool? isEnabled, int? customPort}) async {}

  @override
  void updateSettingsProvider(SettingsProvider settingsProvider) {}

  @override
  Future<void> checkForUpdates() async {}

  void setInstalledModules(List<Module> modules) {
    _mockInstalledModules.clear();
    _mockInstalledModules.addAll(modules);
    notifyListeners();
  }
}

void main() {
  testWidgets('DashboardScreen shows PYNQ Deploy button',
      (WidgetTester tester) async {
    final mockProvider = MockDashboardProvider();
    mockProvider.setInstalledModules([]);

    await tester.pumpWidget(
      MaterialApp(
        home: ChangeNotifierProvider<ModuleProvider>.value(
          value: mockProvider,
          child: const DashboardScreen(),
        ),
      ),
    );

    expect(find.text('PYNQ Deploy'), findsOneWidget);
  });

  testWidgets('DashboardScreen shows Teensy Deploy button',
      (WidgetTester tester) async {
    final mockProvider = MockDashboardProvider();
    mockProvider.setInstalledModules([]);

    await tester.pumpWidget(
      MaterialApp(
        home: ChangeNotifierProvider<ModuleProvider>.value(
          value: mockProvider,
          child: const DashboardScreen(),
        ),
      ),
    );

    expect(find.text('Teensy Deploy'), findsOneWidget);
  });

  testWidgets('DashboardScreen shows empty state when no modules are installed',
      (WidgetTester tester) async {
    final mockProvider = MockDashboardProvider();
    mockProvider.setInstalledModules([]);

    await tester.pumpWidget(
      MaterialApp(
        home: ChangeNotifierProvider<ModuleProvider>.value(
          value: mockProvider,
          child: const DashboardScreen(),
        ),
      ),
    );

    expect(
      find.text(
        'No modules installed yet. Go to the Catalog to install modules.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('DashboardScreen shows installed modules and responds to buttons',
      (WidgetTester tester) async {
    final mockProvider = MockDashboardProvider();
    final installedModule = Module(
      id: 'test_module',
      name: 'Test Module',
      description: 'Test description',
      directory: 'dir',
      status: ModuleStatus.installed,
    );
    mockProvider.setInstalledModules([installedModule]);

    await tester.pumpWidget(
      MaterialApp(
        home: ChangeNotifierProvider<ModuleProvider>.value(
          value: mockProvider,
          child: const DashboardScreen(),
        ),
      ),
    );

    expect(find.text('Test Module'), findsOneWidget);
    expect(find.text('Test description'), findsOneWidget);

    // Find the Start button
    final startButton = find.text('Start');
    expect(startButton, findsOneWidget);

    // Tap the Start button
    await tester.tap(startButton);
    await tester.pump();

    expect(mockProvider.launchCalls, contains('test_module'));

    // Update status to running
    final runningModule =
        installedModule.copyWith(status: ModuleStatus.running);
    mockProvider.setInstalledModules([runningModule]);
    await tester.pump();

    expect(find.text('Open'), findsOneWidget);
    expect(find.text('Stop'), findsOneWidget);

    // Tap the Stop button
    await tester.tap(find.text('Stop'));
    await tester.pump();

    expect(mockProvider.stopCalls, contains('test_module'));

    // Tap the Uninstall button
    await tester.tap(find.byIcon(Icons.delete));
    await tester.pump();

    expect(mockProvider.uninstallCalls, contains('test_module'));
  });

  testWidgets('DashboardScreen handles Open button click',
      (WidgetTester tester) async {
    final mockProvider = MockDashboardProvider();
    final runningModule = Module(
      id: 'test_module',
      name: 'Test Module',
      description: 'Test description',
      directory: 'dir',
      status: ModuleStatus.running,
    );
    mockProvider.setInstalledModules([runningModule]);

    await tester.pumpWidget(
      MaterialApp(
        home: ChangeNotifierProvider<ModuleProvider>.value(
          value: mockProvider,
          child: const DashboardScreen(),
        ),
      ),
    );

    expect(find.text('Open'), findsOneWidget);
  });
}
