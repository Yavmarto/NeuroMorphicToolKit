import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:neuro_toolkit/providers/settings_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_toolkit/main.dart';
import 'package:neuro_toolkit/models/module.dart';
import 'package:go_router/go_router.dart';
import 'package:neuro_toolkit/providers/module_provider.dart';
import 'package:neuro_toolkit/providers/riverpod_providers.dart';
import 'package:neuro_toolkit/services/update_service.dart';
import 'package:neuro_toolkit/widgets/module_picker_panel.dart';

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
  LauncherUpdate? get pendingLauncherUpdate => null;
  @override
  UpdateChannel get currentChannel => UpdateChannel.stable;
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
  Future<void> updateModule(String moduleId) async {}

  @override
  Future<void> updateModuleSettings(
    String moduleId, {
    bool? isEnabled,
    int? customPort,
    bool? startOnLaunch,
  }) async {}

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
}

void main() {
  testWidgets('App loads smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          moduleStateProvider.overrideWith((ref) => LocalMockModuleProvider()),
          settingsStateProvider.overrideWith((ref) => SettingsProvider()),
          goRouterProvider.overrideWith((ref) {
            return GoRouter(
              routes: [
                GoRoute(
                  path: '/',
                  builder: (context, state) => const Scaffold(
                    body: ModulePickerPanel(),
                  ),
                ),
              ],
            );
          }),
        ],
        child: const NeuroToolkitApp(),
      ),
    );

    await tester.pumpAndSettle();

    // Verify that the module picker is shown (empty state).
    expect(find.text('No Modules Available'), findsOneWidget);
  });
}
