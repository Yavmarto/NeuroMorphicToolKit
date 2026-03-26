import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:neuro_toolkit/main.dart';
import 'package:neuro_toolkit/models/module.dart';
import 'package:neuro_toolkit/providers/module_provider.dart';
import 'package:neuro_toolkit/screens/tool_view.dart';
import 'package:provider/provider.dart';

class MockModuleProvider extends ChangeNotifier implements ModuleProvider {
  final List<Module> _modules = [
    Module(
      id: 'neurocnl',
      name: 'CNL Studio',
      description: 'CNL parser',
      directory: '/tmp/neurocnl',
      port: 8000,
      hasFrontend: true,
      status: ModuleStatus.notInstalled,
    ),
  ];

  @override
  List<Module> get modules => _modules;
  @override
  set modules(List<Module> val) {}
  @override
  List<Module> modulesForTesting = [];

  final List<String> _activeModuleIds = [];
  @override
  List<String> get activeModuleIds => _activeModuleIds;

  @override
  List<Module> get activeModules => _activeModuleIds
      .map((id) => _modules.firstWhere((m) => m.id == id))
      .toList();

  @override
  bool get isLoading => false;
  @override
  bool get pythonAvailable => true;
  @override
  String? get error => null;

  @override
  List<Module> get installedModules => _modules.where((m) => m.status != ModuleStatus.notInstalled).toList();
  @override
  List<Module> get availableModules => _modules.where((m) => m.status == ModuleStatus.notInstalled).toList();

  @override
  Future<void> recheckPython() async {}
  @override
  bool isMuJoCoAvailable() => false;

  @override
  Future<void> installModule(String moduleId) async {
    final idx = _modules.indexWhere((m) => m.id == moduleId);
    if (idx != -1) {
      _modules[idx] = _modules[idx].copyWith(status: ModuleStatus.installed);
      notifyListeners();
    }
  }

  @override
  Future<void> launchModule(String moduleId) async {
    final idx = _modules.indexWhere((m) => m.id == moduleId);
    if (idx != -1) {
      _modules[idx] = _modules[idx].copyWith(status: ModuleStatus.running);
      if (!_activeModuleIds.contains(moduleId)) {
        _activeModuleIds.add(moduleId);
      }
      notifyListeners();
    }
  }

  @override
  Future<void> stopModule(String moduleId) async {
    final idx = _modules.indexWhere((m) => m.id == moduleId);
    if (idx != -1) {
      _modules[idx] = _modules[idx].copyWith(status: ModuleStatus.installed);
      _activeModuleIds.remove(moduleId);
      notifyListeners();
    }
  }

  @override
  Future<void> uninstallModule(String moduleId) async {
    final idx = _modules.indexWhere((m) => m.id == moduleId);
    if (idx != -1) {
      _modules[idx] = _modules[idx].copyWith(status: ModuleStatus.notInstalled);
      _activeModuleIds.remove(moduleId);
      notifyListeners();
    }
  }

  @override
  void closeTab(String moduleId) {
    _activeModuleIds.remove(moduleId);
    notifyListeners();
  }

  @override
  Stream<String>? getModuleOutput(String moduleId) => null;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('End-to-end integration test (Dashboard to ToolView)', (WidgetTester tester) async {
    final mockProvider = MockModuleProvider();

    // Launch app with mock provider
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ModuleProvider>.value(value: mockProvider),
        ],
        child: const NeuroToolkitApp(),
      ),
    );

    await tester.pumpAndSettle();

    // 1. Verify we are on Dashboard and see the module
    expect(find.text('CNL Studio'), findsWidgets);
    expect(find.text('INSTALL'), findsOneWidget);

    // 2. Install module
    await tester.tap(find.text('INSTALL'));
    await tester.pumpAndSettle();

    // 3. Start module
    expect(find.text('START'), findsOneWidget);
    await tester.tap(find.text('START'));
    await tester.pumpAndSettle();

    // 4. Verify we navigated to ToolViewScreen (or can navigate to it)
    // The current UI might auto-navigate on launch, or we might need to click "OPEN"
    // Assuming launchModule in Mock adds it to active tabs and it shows up.
    expect(find.byType(ToolViewScreen), findsOneWidget);
    expect(find.text('Waiting for CNL Studio to become ready...'), findsOneWidget);

    // On Linux, we expect the "Open in System Browser" button because WebView is not supported.
    expect(find.text('Open in Browser instead'), findsOneWidget);
    expect(find.byIcon(Icons.open_in_browser), findsOneWidget);

    // 5. Close tab and go back to dashboard
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();

    expect(find.byType(ToolViewScreen), findsNothing);
    expect(find.text('CNL Studio'), findsWidgets);
  });
}
