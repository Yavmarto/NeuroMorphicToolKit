import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_toolkit/models/module.dart';
import 'package:neuro_toolkit/providers/module_provider.dart';
import 'package:neuro_toolkit/providers/riverpod_providers.dart';
import 'package:neuro_toolkit/services/update_service.dart';
import 'package:neuro_toolkit/widgets/module_picker_panel.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';

// ---------------------------------------------------------------------------
// Minimal mock — only overrides what the panel touches
// ---------------------------------------------------------------------------

class _MockProvider extends ChangeNotifier implements ModuleProvider {
  final List<Module> _modules = [];
  final List<String> installCalls = [];
  final List<String> launchCalls = [];
  final List<String> stopCalls = [];

  @override
  List<Module> get modules => _modules;
  @override
  set modules(List<Module> val) {
    _modules
      ..clear()
      ..addAll(val);
    notifyListeners();
  }

  void setModules(List<Module> m) {
    _modules
      ..clear()
      ..addAll(m);
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
  bool isMuJoCoAvailable() => false;
  @override
  LauncherUpdate? get pendingLauncherUpdate => null;
  @override
  UpdateChannel get currentChannel => UpdateChannel.stable;
  @override
  List<String> get activeModuleIds => [];
  @override
  List<Module> get activeModules => [];
  @override
  List<Module> get installedModules =>
      _modules.where((m) => m.status != ModuleStatus.notInstalled).toList();
  @override
  List<Module> get availableModules =>
      _modules.where((m) => m.status == ModuleStatus.notInstalled).toList();

  @override
  Future<void> installModule(String moduleId) async =>
      installCalls.add(moduleId);
  @override
  Future<void> launchModule(String moduleId) async => launchCalls.add(moduleId);
  @override
  Future<void> stopModule(String moduleId) async => stopCalls.add(moduleId);
  @override
  Future<void> updateModule(String moduleId) async {}
  @override
  Future<void> uninstallModule(String moduleId) async {}
  @override
  Future<void> recheckPython() async {}
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
  Future<void> updateModuleSettings(
    String moduleId, {
    bool? isEnabled,
    int? customPort,
    bool? startOnLaunch,
  }) async {}
  @override
  void updateSettingsProvider(dynamic settingsProvider) {}
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  Widget wrap(_MockProvider mock) => ProviderScope(
        overrides: [moduleStateProvider.overrideWith((ref) => mock)],
        child: const ShadApp(home: Scaffold(body: ModulePickerPanel())),
      );

  testWidgets('shows empty state when no modules are loaded', (tester) async {
    final mock = _MockProvider();
    await tester.pumpWidget(wrap(mock));
    expect(find.text('No Modules Available'), findsOneWidget);
  });

  testWidgets('shows Install button for not-installed module', (tester) async {
    final mock = _MockProvider();
    mock.setModules([
      Module(
        id: 'neurocnl',
        name: 'CNL Studio',
        description: 'CNL parser',
        directory: 'neurocnl/',
        status: ModuleStatus.notInstalled,
      ),
    ]);
    await tester.pumpWidget(wrap(mock));
    await tester.pump();

    expect(find.text('CNL Studio'), findsWidgets);
    expect(find.text('Install'), findsOneWidget);

    await tester.tap(find.text('Install'));
    await tester.pump();
    expect(mock.installCalls, contains('neurocnl'));
  });

  testWidgets('shows Start button for installed module', (tester) async {
    final mock = _MockProvider();
    mock.setModules([
      Module(
        id: 'neurocnl',
        name: 'CNL Studio',
        description: 'CNL parser',
        directory: 'neurocnl/',
        status: ModuleStatus.installed,
      ),
    ]);
    await tester.pumpWidget(wrap(mock));
    await tester.pump();

    expect(find.text('Start'), findsOneWidget);
    await tester.tap(find.text('Start'));
    await tester.pump();
    expect(mock.launchCalls, contains('neurocnl'));
  });

  testWidgets('shows Open and Stop for running module', (tester) async {
    final mock = _MockProvider();
    mock.setModules([
      Module(
        id: 'neurocnl',
        name: 'CNL Studio',
        description: 'CNL parser',
        directory: 'neurocnl/',
        status: ModuleStatus.running,
      ),
    ]);
    await tester.pumpWidget(wrap(mock));
    await tester.pump();

    expect(find.text('Open'), findsOneWidget);
    expect(find.text('Stop'), findsOneWidget);

    await tester.tap(find.text('Stop'));
    await tester.pump();
    expect(mock.stopCalls, contains('neurocnl'));
  });

  testWidgets('does not show hardware deploy buttons (relocated to Neurochip)',
      (tester) async {
    final mock = _MockProvider();
    await tester.pumpWidget(wrap(mock));
    expect(find.text('PYNQ Deploy'), findsNothing);
    expect(find.text('Teensy Deploy'), findsNothing);
    expect(find.text('Akida Deploy'), findsNothing);
  });

  testWidgets('hides Update action when remote version is not newer',
      (tester) async {
    final mock = _MockProvider();
    mock.setModules([
      Module(
        id: 'neurocnl',
        name: 'CNL Studio',
        description: 'CNL parser',
        directory: 'neurocnl/',
        status: ModuleStatus.installed,
        version: '1.0.0',
        remoteVersion: '0.5.0',
      ),
    ]);
    await tester.pumpWidget(wrap(mock));
    await tester.pump();

    expect(find.text('Update to 0.5.0'), findsNothing);
  });

  testWidgets('lays out multiple modules on a narrow viewport without overflow',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final mock = _MockProvider();
    mock.setModules([
      Module(
        id: 'neurocnl',
        name: 'CNL Studio',
        description: 'CNL parser',
        directory: 'neurocnl/',
        status: ModuleStatus.notInstalled,
      ),
      Module(
        id: 'neurochip',
        name: 'Neurochip',
        description: 'Hardware deployment',
        directory: 'Neurochip/',
        status: ModuleStatus.installed,
      ),
      Module(
        id: 'neurobench',
        name: 'Neurobench',
        description: 'Benchmark reports',
        directory: 'Neurobench/',
        status: ModuleStatus.running,
      ),
    ]);

    await tester.pumpWidget(wrap(mock));
    await tester.pumpAndSettle();

    expect(find.text('CNL Studio'), findsWidgets);
    expect(find.text('Neurochip'), findsWidgets);
    expect(find.text('Neurobench'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
