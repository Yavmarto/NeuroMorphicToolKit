import 'package:flutter/material.dart';
import 'package:neuro_toolkit/services/update_service.dart';
import 'package:neuro_toolkit/models/module.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:neuro_toolkit/providers/module_provider.dart';
import 'package:neuro_toolkit/screens/tool_view.dart';
import 'package:neuro_toolkit/widgets/module_tab_bar.dart';

class MockModuleProvider extends ChangeNotifier implements ModuleProvider {
  final List<Module> _modules = [
    Module(
      id: 'm1',
      name: 'Module 1',
      description: 'Desc 1',
      directory: '/tmp/m1',
      port: 8001,
      hasFrontend: true,
      status: ModuleStatus.running,
    ),
    Module(
      id: 'm2',
      name: 'Module 2',
      description: 'Desc 2',
      directory: '/tmp/m2',
      port: 8002,
      hasFrontend: true,
      status: ModuleStatus.running,
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
  List<Module> get installedModules => _modules;

  @override
  void dismissLauncherUpdate() {}

  @override
  void setUpdateChannel(UpdateChannel channel) {}

  @override
  Future<void> setVersionPinned(String moduleId, bool pinned) async {}

  @override
  LauncherUpdate? get pendingLauncherUpdate => null;

  @override
  UpdateChannel get currentChannel => UpdateChannel.stable;
  @override
  List<Module> get availableModules => [];

  @override
  Future<void> recheckPython() async {}
  @override
  bool isMuJoCoAvailable() => false;
  @override
  Future<void> installModule(String moduleId) async {}

  @override
  Future<void> launchModule(String moduleId) async {
    if (!_activeModuleIds.contains(moduleId)) {
      _activeModuleIds.add(moduleId);
    }
    notifyListeners();
  }

  @override
  Future<void> stopModule(String moduleId) async {
    _activeModuleIds.remove(moduleId);
    notifyListeners();
  }

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
  void closeTab(String moduleId) {
    _activeModuleIds.remove(moduleId);
    notifyListeners();
  }

  @override
  Stream<String>? getModuleOutput(String moduleId) => null;
}

void main() {
  testWidgets('ToolViewScreen tab management test',
      (WidgetTester tester) async {
    final mockProvider = MockModuleProvider();

    // Initial launch of m1
    await mockProvider.launchModule('m1');

    await tester.pumpWidget(
      MaterialApp(
        home: ChangeNotifierProvider<ModuleProvider>.value(
          value: mockProvider,
          child: const ToolViewScreen(initialModuleId: 'm1'),
        ),
      ),
    );

    await tester.pump();

    // Verify m1 is active
    expect(find.text('Module 1'), findsWidgets);
    expect(find.byType(ModuleTabBar), findsOneWidget);

    // Launch m2
    await mockProvider.launchModule('m2');
    await tester.pump();

    // Verify both tabs exist in the tab bar
    expect(find.text('Module 1'), findsWidgets);
    expect(find.text('Module 2'), findsWidgets);

    // Switch to m2 tab (tap the InkWell containing 'Module 2')
    await tester.tap(find.text('Module 2').last);
    await tester.pump();

    // Close m1 tab
    final closeButtonM1 = find.descendant(
      of: find.ancestor(
          of: find.text('Module 1').last, matching: find.byType(Row)),
      matching: find.byIcon(Icons.close),
    );

    await tester.tap(closeButtonM1);
    await tester.pump();

    // Verify m1 tab is gone
    expect(find.text('Module 1'), findsNothing);
    expect(find.text('Module 2'), findsWidgets);
  });

  testWidgets('Fallback to browser button exists', (WidgetTester tester) async {
    final mockProvider = MockModuleProvider();
    await mockProvider.launchModule('m1');

    await tester.pumpWidget(
      MaterialApp(
        home: ChangeNotifierProvider<ModuleProvider>.value(
          value: mockProvider,
          child: const ToolViewScreen(initialModuleId: 'm1'),
        ),
      ),
    );

    await tester.pump();

    // Verify "Open in System Browser" icon button exists.
    // Use find.byTooltip to be more specific if possible, or just expect it to be there.
    expect(find.byIcon(Icons.open_in_browser), findsWidgets);

    // Verify wait screen elements (since it's not ready in the mock polling)
    expect(find.textContaining('Waiting for Module 1'), findsOneWidget);
    expect(find.text('Open in Browser instead'), findsOneWidget);
  });
}
