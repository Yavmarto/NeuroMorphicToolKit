// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_toolkit/main.dart';
import 'package:neuro_toolkit/models/module.dart';
import 'package:provider/provider.dart';
import 'package:neuro_toolkit/providers/module_provider.dart';
import 'package:neuro_toolkit/providers/settings_provider.dart';

class LocalMockSettingsProvider extends ChangeNotifier
    implements SettingsProvider {
  @override
  ThemeMode get themeMode => ThemeMode.system;
  @override
  bool get isHighContrast => false;
  @override
  double get fontSizeFactor => 1.0;

  @override
  void setThemeMode(ThemeMode mode) {}
  @override
  void setHighContrast(bool value) {}
  @override
  void setFontSizeFactor(double factor) {}
}

class LocalMockModuleProvider extends ChangeNotifier implements ModuleProvider {
  @override
  List<Module> get modules => [];
  @override
  set modules(List<Module> val) {}
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
  List<Module> get installedModules => [];
  @override
  List<Module> get availableModules => [];

  @override
  Future<void> recheckPython() async {}
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
}

void main() {
  testWidgets('App loads smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ModuleProvider>(
            create: (_) => LocalMockModuleProvider(),
          ),
          ChangeNotifierProvider<SettingsProvider>(
            create: (_) => LocalMockSettingsProvider(),
          ),
        ],
        child: const NeuroToolkitApp(),
      ),
    );

    await tester.pumpAndSettle();

    // Verify that the Dashboard is shown.
    expect(find.text('Dashboard'), findsWidgets);
  });
}
