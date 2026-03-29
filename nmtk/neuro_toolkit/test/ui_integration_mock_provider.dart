import 'dart:async';
import 'package:flutter/material.dart';
import 'package:neuro_toolkit/providers/settings_provider.dart';
import 'package:neuro_toolkit/models/module.dart';
import 'package:neuro_toolkit/providers/module_provider.dart';
import 'package:neuro_toolkit/services/update_service.dart';

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
  LauncherUpdate? get pendingLauncherUpdate => null;
  @override
  UpdateChannel get currentChannel => UpdateChannel.stable;
  @override
  List<Module> get installedModules => _modules;
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
  Future<void> checkForUpdates() async {}

  @override
  Future<void> updateModule(String moduleId) async {}

  @override
  Future<void> updateModuleSettings(String moduleId,
      {bool? isEnabled, int? customPort}) async {}

  @override
  void updateSettingsProvider(settingsProvider) {}

  @override
  void setUpdateChannel(UpdateChannel channel) {}

  @override
  Future<void> setVersionPinned(String moduleId, bool pinned) async {}

  @override
  void dismissLauncherUpdate() {}

  @override
  void closeTab(String moduleId) {
    _activeModuleIds.remove(moduleId);
    notifyListeners();
  }

  @override
  Stream<String>? getModuleOutput(String moduleId) => null;
}
