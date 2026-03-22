import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_toolkit/models/module.dart';
import 'package:neuro_toolkit/screens/catalog.dart';
import 'package:neuro_toolkit/providers/module_provider.dart';
import 'package:provider/provider.dart';

class MockModuleProvider extends ChangeNotifier implements ModuleProvider {
  final List<Module> _mockModules = [];

  @override
  List<Module> get modules => _mockModules;

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
      m.status != ModuleStatus.installing).toList();

  @override
  List<Module> get availableModules => _mockModules.where((m) =>
      m.status == ModuleStatus.notInstalled ||
      m.status == ModuleStatus.installing).toList();

  @override
  List<String> get activeModuleIds => [];

  @override
  List<Module> get activeModules => [];

  @override
  bool isMuJoCoAvailable() => false;

  @override
  Future<void> installModule(String moduleId) async {}

  @override
  Future<void> launchModule(String moduleId) async {}

  @override
  Future<void> stopModule(String moduleId) async {}

  @override
  Future<void> uninstallModule(String moduleId) async {}

  @override
  void closeTab(String moduleId) {}

  @override
  Stream<String>? getModuleOutput(String moduleId) => null;

  void loadModules() {
    final List<Map<String, dynamic>> mockData = [
      {
        "id": "neurocnl",
        "name": "CNL Studio",
        "description": "CNL parser",
        "icon": "code",
        "port": 8000,
        "installPath": "neurocnl/",
        "hasFrontend": true,
        "frontendStatus": "Yes",
        "requiresMuJoCo": false
      },
      {
        "id": "Neurosim",
        "name": "NeuroSim",
        "description": "Visual design",
        "icon": "architecture",
        "port": 8001,
        "installPath": "Neurosim/",
        "hasFrontend": true,
        "frontendStatus": "Minimal",
        "requiresMuJoCo": false
      },
      {
        "id": "Neurochip",
        "name": "NeuroChip",
        "description": "Hardware",
        "icon": "memory",
        "port": 8002,
        "installPath": "Neurochip/",
        "hasFrontend": true,
        "frontendStatus": "Partial",
        "requiresMuJoCo": false
      },
      {
        "id": "Neurobench",
        "name": "NeuroBench",
        "description": "Benchmarking",
        "icon": "speed",
        "port": 8003,
        "installPath": "Neurobench/",
        "hasFrontend": true,
        "frontendStatus": "Scaffold",
        "requiresMuJoCo": false
      },
      {
        "id": "Neurosense",
        "name": "NeuroSense",
        "description": "Biosignal",
        "icon": "sensors",
        "port": 8004,
        "installPath": "Neurosense/",
        "hasFrontend": true,
        "frontendStatus": "Partial",
        "requiresMuJoCo": false
      },
      {
        "id": "Neurohub",
        "name": "NeuroHub",
        "description": "Dashboard",
        "icon": "hub",
        "port": 8005,
        "installPath": "Neurohub/",
        "hasFrontend": true,
        "frontendStatus": "Scaffold",
        "requiresMuJoCo": false
      },
      {
        "id": "neuro_dream_hand",
        "name": "NDH Simulator",
        "description": "Physics",
        "icon": "precision_manufacturing",
        "port": null,
        "installPath": "Neuro-Dream-Hand/",
        "hasFrontend": false,
        "frontendStatus": "No",
        "requiresMuJoCo": true
      }
    ];

    _mockModules.clear();
    _mockModules.addAll(mockData.map((json) => Module.fromJson(json)));
    notifyListeners();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('CatalogScreen shows all 7 modules', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1920, 2000);
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
    expect(find.text('NeuroSim'), findsOneWidget);
    expect(find.text('NeuroChip'), findsOneWidget);
    expect(find.text('NeuroBench'), findsOneWidget);
    expect(find.text('NeuroSense'), findsOneWidget);
    expect(find.text('NeuroHub'), findsOneWidget);
    expect(find.text('NDH Simulator'), findsOneWidget);

    addTearDown(tester.view.resetPhysicalSize);
  });
}
