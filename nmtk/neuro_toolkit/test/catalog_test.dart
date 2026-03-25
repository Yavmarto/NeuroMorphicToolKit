import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_toolkit/models/module.dart';
import 'package:neuro_toolkit/screens/catalog.dart';
import 'package:neuro_toolkit/providers/module_provider.dart';
import 'package:provider/provider.dart';

class MockModuleProvider extends ChangeNotifier implements ModuleProvider {
  final List<Module> _mockModules = [];
  final List<String> installCalls = [];
  final List<String> uninstallCalls = [];
  bool _isMuJoCoAvailable = false;

  @override
  List<Module> get modules => _mockModules;

  @override
  set modules(List<Module> val) {
    _mockModules.clear();
    _mockModules.addAll(val);
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
  Future<void> recheckPython() async {}

  @override
  List<Module> get installedModules => _mockModules.where((m) =>
      m.status != ModuleStatus.notInstalled &&
      m.status != ModuleStatus.installing,).toList();

  @override
  List<Module> get availableModules => _mockModules.where((m) =>
      m.status == ModuleStatus.notInstalled ||
      m.status == ModuleStatus.installing,).toList();

  @override
  List<String> get activeModuleIds => [];

  @override
  List<Module> get activeModules => [];

  @override
  bool isMuJoCoAvailable() => _isMuJoCoAvailable;

  void setMuJoCoAvailable(bool available) {
    _isMuJoCoAvailable = available;
    notifyListeners();
  }

  @override
  Future<void> installModule(String moduleId) async {
    installCalls.add(moduleId);
    final index = _mockModules.indexWhere((m) => m.id == moduleId);
    if (index != -1) {
      _mockModules[index] = _mockModules[index].copyWith(status: ModuleStatus.installing, installProgress: 0.5);
      notifyListeners();
    }
  }

  @override
  Future<void> launchModule(String moduleId) async {}

  @override
  Future<void> stopModule(String moduleId) async {}

  @override
  Future<void> uninstallModule(String moduleId) async {
    uninstallCalls.add(moduleId);
    final index = _mockModules.indexWhere((m) => m.id == moduleId);
    if (index != -1) {
      _mockModules[index] = _mockModules[index].copyWith(status: ModuleStatus.notInstalled, installProgress: 0.0);
      notifyListeners();
    }
  }

  @override
  void closeTab(String moduleId) {}

  @override
  Stream<String>? getModuleOutput(String moduleId) => null;

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
        'id': 'neuro_dream_hand',
        'name': 'NDH Simulator',
        'description': 'Physics',
        'icon': 'precision_manufacturing',
        'port': null,
        'installPath': 'Neuro-Dream-Hand/',
        'hasFrontend': false,
        'frontendStatus': 'No',
        'requiresMuJoCo': true,
      }
    ];

    _mockModules.clear();
    _mockModules.addAll(mockData.map((json) => Module.fromJson(json)));
    notifyListeners();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('CatalogScreen shows modules and handles interactions', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;

    final provider = MockModuleProvider();
    provider.loadModules();

    await tester.pumpWidget(
      MaterialApp(
        home: ChangeNotifierProvider<ModuleProvider>.value(
          value: provider,
          child: const CatalogScreen(),
        ),
      ),
    );

    await tester.pump();

    expect(find.text('CNL Studio'), findsOneWidget);
    expect(find.text('NDH Simulator'), findsOneWidget);

    // Find and tap Install button for CNL Studio
    final installButton = find.widgetWithText(ElevatedButton, 'Install').first;
    await tester.tap(installButton);
    await tester.pump();

    expect(provider.installCalls, contains('neurocnl'));
    expect(find.text('Installing'), findsOneWidget);

    addTearDown(tester.view.resetPhysicalSize);
  });

  testWidgets('CatalogScreen grays out MuJoCo modules when MuJoCo is missing', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    final provider = MockModuleProvider();
    provider.loadModules();
    provider.setMuJoCoAvailable(false);

    await tester.pumpWidget(
      MaterialApp(
        home: ChangeNotifierProvider<ModuleProvider>.value(
          value: provider,
          child: const CatalogScreen(),
        ),
      ),
    );

    await tester.pump();

    expect(find.text('MuJoCo Missing'), findsOneWidget);

    // The button should be disabled (onPressed is null)
    final ndhCard = find.ancestor(of: find.text('NDH Simulator'), matching: find.byType(Card));
    final installButton = find.descendant(of: ndhCard, matching: find.byType(ElevatedButton));

    final ElevatedButton buttonWidget = tester.widget(installButton);
    expect(buttonWidget.onPressed, isNull);

    addTearDown(tester.view.resetPhysicalSize);
  });
}
