import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_toolkit/models/module.dart';
import 'package:neuro_toolkit/providers/module_provider.dart';
import 'package:neuro_toolkit/screens/catalog.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';

class MockModuleProvider extends ModuleProvider {
  final List<Module> _mockModules = [];

  @override
  List<Module> get modules => _mockModules;

  @override
  bool get isLoading => false;

  @override
  String? get error => null;

  @override
  Future<void> loadModules() async {
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
    // Set a larger surface size to ensure all items are visible without scrolling
    tester.view.physicalSize = const Size(1920, 2000); // Very tall
    tester.view.devicePixelRatio = 1.0;

    final provider = MockModuleProvider();
    await provider.loadModules();

    await tester.pumpWidget(
      MaterialApp(
        home: ChangeNotifierProvider<ModuleProvider>.value(
          value: provider,
          child: const CatalogScreen(),
        ),
      ),
    );

    await tester.pump();

    // Check for some expected module names
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
